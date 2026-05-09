import SwiftUI
import UserNotifications
import WorthSnapShared

@main
struct WorthSnapApp: App {
    @StateObject private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .task {
                    await store.reconcileMonthlyReminder()
                }
                .onChange(of: scenePhase) { _, newValue in
                    guard newValue == .active else { return }
                    Task {
                        await store.reconcileMonthlyReminder()
                    }
                }
        }
    }
}

enum AppTab: Hashable {
    case overview
    case snapshot
    case trend
    case accounts
}

private enum MonthlyReminderNotification {
    static let identifier = "worthsnap.monthly-reminder.next"
}

@MainActor
final class AppStore: NSObject, ObservableObject {
    @Published var data: WorthSnapData
    @Published var selectedMonth: String
    @Published var selectedTab: AppTab = .overview

    private let url: URL
    private let notificationCenter: UNUserNotificationCenter

    override init() {
        notificationCenter = .current()
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        url = documents.appendingPathComponent("worthsnap-data.json")
        let loadedData: WorthSnapData
        if let stored = try? Data(contentsOf: url) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            loadedData = (try? decoder.decode(WorthSnapData.self, from: stored)) ?? WorthSnapEngine.seededData()
        } else {
            loadedData = WorthSnapEngine.seededData()
        }
        data = loadedData
        selectedMonth = loadedData.snapshots.filter { WorthSnapEngine.isValidMonth($0.month) }.sorted(by: { $0.month < $1.month }).last?.month ?? WorthSnapEngine.currentMonth()
        super.init()
        notificationCenter.delegate = self
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let encoded = try? encoder.encode(data) {
            try? encoded.write(to: url, options: .atomic)
        }
    }

    func snapshot(month: String? = nil) -> Snapshot {
        let target = month ?? selectedMonth
        guard WorthSnapEngine.isValidMonth(target) else {
            let fallback = data.snapshots.filter { WorthSnapEngine.isValidMonth($0.month) }.sorted(by: { $0.month < $1.month }).last?.month ?? WorthSnapEngine.currentMonth()
            selectedMonth = fallback
            return snapshot(month: fallback)
        }
        if let existing = data.snapshots.first(where: { $0.month == target }) {
            return existing
        }
        let created = WorthSnapEngine.createSnapshot(month: target, in: &data)
        save()
        return created
    }

    var sortedSnapshots: [Snapshot] {
        data.snapshots.sorted { $0.month > $1.month }
    }

    var sortedValidSnapshots: [Snapshot] {
        sortedSnapshots.filter { WorthSnapEngine.isValidMonth($0.month) }
    }

    func createAdjacentSnapshot(offset: Int) {
        let current = WorthSnapEngine.isValidMonth(selectedMonth) ? selectedMonth : WorthSnapEngine.currentMonth()
        let target = offset < 0 ? WorthSnapEngine.previousMonth(current) : WorthSnapEngine.nextMonth(current)
        guard let target else { return }
        selectedMonth = target
        _ = snapshot(month: target)
    }

    func deleteSnapshot(_ target: Snapshot) {
        data.entries.removeAll { $0.snapshotId == target.id }
        data.snapshots.removeAll { $0.id == target.id }
        if selectedMonth == target.month {
            selectedMonth = sortedValidSnapshots.first?.month ?? WorthSnapEngine.currentMonth()
            if data.snapshots.isEmpty {
                _ = snapshot(month: selectedMonth)
            }
        }
        save()
        Task {
            await reconcileMonthlyReminder()
        }
    }

    func entries(for snapshot: Snapshot) -> [SnapshotEntry] {
        data.entries.filter { $0.snapshotId == snapshot.id }.sorted { left, right in
            let leftOrder = data.accounts.first { $0.id == left.accountId }?.sortOrder ?? 0
            let rightOrder = data.accounts.first { $0.id == right.accountId }?.sortOrder ?? 0
            return leftOrder < rightOrder
        }
    }

    func account(id: UUID) -> Account? {
        data.accounts.first { $0.id == id }
    }

    func typeName(id: UUID) -> String {
        data.accountTypes.first { $0.id == id }?.name ?? "未分类"
    }

    func updateEntry(_ entry: SnapshotEntry, rawAmount: String, confirmed: Bool? = nil) {
        guard let amount = AmountParser.parse(rawAmount) else { return }
        WorthSnapEngine.updateEntry(entryId: entry.id, amount: amount, confirmed: confirmed, in: &data)
        save()
        Task {
            await reconcileMonthlyReminder()
        }
    }

    func confirm(_ entry: SnapshotEntry) {
        WorthSnapEngine.updateEntry(entryId: entry.id, amount: entry.amount, confirmed: true, in: &data)
        save()
        Task {
            await reconcileMonthlyReminder()
        }
    }

    func addAccount(name: String, direction: Direction, typeId: UUID, currency: String, ownership: Ownership) {
        let order = (data.accounts.map(\.sortOrder).max() ?? 0) + 1
        let account = Account(ledgerId: data.ledger.id, name: name, direction: direction, typeId: typeId, currency: currency, ownership: ownership, sortOrder: order)
        WorthSnapEngine.addAccount(account, to: &data)
        save()
        Task {
            await reconcileMonthlyReminder()
        }
    }

    func updateAccount(_ account: Account, name: String, direction: Direction, typeId: UUID, currency: String, ownership: Ownership) {
        guard let index = data.accounts.firstIndex(where: { $0.id == account.id }) else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCurrency = currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        data.accounts[index].name = trimmedName
        data.accounts[index].direction = direction
        data.accounts[index].typeId = typeId
        data.accounts[index].currency = normalizedCurrency.isEmpty ? data.accounts[index].currency : normalizedCurrency
        data.accounts[index].ownership = ownership
        data.accounts[index].updatedAt = Date()

        for snapshot in data.snapshots {
            WorthSnapEngine.updateCompletion(snapshotId: snapshot.id, updateSnapshotDate: false, in: &data)
        }
        save()
        Task {
            await reconcileMonthlyReminder()
        }
    }

    func toggleArchive(account: Account) {
        guard let index = data.accounts.firstIndex(where: { $0.id == account.id }) else { return }
        data.accounts[index].archived.toggle()
        data.accounts[index].updatedAt = Date()
        for snapshot in data.snapshots {
            WorthSnapEngine.updateCompletion(snapshotId: snapshot.id, updateSnapshotDate: false, in: &data)
        }
        save()
        Task {
            await reconcileMonthlyReminder()
        }
    }

    func updateSnapshotNote(snapshotId: UUID, note: String) {
        guard let index = data.snapshots.firstIndex(where: { $0.id == snapshotId }) else { return }
        let now = Date()
        data.snapshots[index].note = note
        data.snapshots[index].snapshotDate = now
        data.snapshots[index].updatedAt = now
        save()
        Task {
            await reconcileMonthlyReminder()
        }
    }

    func setMonthlyReminderEnabled(_ isEnabled: Bool) async -> Bool {
        data.monthlyReminder.isEnabled = isEnabled
        save()
        return await reconcileMonthlyReminder(requestAuthorizationIfNeeded: isEnabled)
    }

    func updateMonthlyReminderDay(_ day: MonthlyReminderDay) {
        data.monthlyReminder.day = day
        save()
        Task {
            await reconcileMonthlyReminder()
        }
    }

    func updateMonthlyReminderTime(hour: Int, minute: Int) {
        data.monthlyReminder.hour = hour
        data.monthlyReminder.minute = minute
        save()
        Task {
            await reconcileMonthlyReminder()
        }
    }

    @discardableResult
    func reconcileMonthlyReminder(requestAuthorizationIfNeeded: Bool = false) async -> Bool {
        let config = data.monthlyReminder
        if !config.isEnabled {
            notificationCenter.removePendingNotificationRequests(withIdentifiers: [MonthlyReminderNotification.identifier])
            return true
        }

        let settings = await notificationCenter.notificationSettings()
        var isAuthorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional || settings.authorizationStatus == .ephemeral
        if settings.authorizationStatus == .notDetermined && requestAuthorizationIfNeeded {
            isAuthorized = (try? await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }

        guard isAuthorized else {
            notificationCenter.removePendingNotificationRequests(withIdentifiers: [MonthlyReminderNotification.identifier])
            return false
        }

        guard let schedule = MonthlyReminderScheduler.nextSchedule(config: config, snapshots: data.snapshots) else {
            notificationCenter.removePendingNotificationRequests(withIdentifiers: [MonthlyReminderNotification.identifier])
            return true
        }

        let content = UNMutableNotificationContent()
        content.title = "旺财"
        content.body = "该记录本月资产快照啦"
        content.sound = .default
        content.userInfo = ["route": "currentMonthSnapshot", "month": schedule.snapshotMonth]

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: schedule.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: MonthlyReminderNotification.identifier, content: content, trigger: trigger)

        notificationCenter.removePendingNotificationRequests(withIdentifiers: [MonthlyReminderNotification.identifier])
        do {
            try await notificationCenter.add(request)
            return true
        } catch {
            return false
        }
    }

    func openMonthlyReminderSnapshot(month: String?) {
        let month = month.flatMap { WorthSnapEngine.isValidMonth($0) ? $0 : nil } ?? WorthSnapEngine.currentMonth()
        selectedMonth = month
        _ = snapshot(month: month)
        selectedTab = .snapshot
    }
}

extension AppStore: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.notification.request.identifier == MonthlyReminderNotification.identifier else { return }
        let month = response.notification.request.content.userInfo["month"] as? String
        await MainActor.run {
            openMonthlyReminderSnapshot(month: month)
        }
    }
}
