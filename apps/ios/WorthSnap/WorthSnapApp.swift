import SwiftUI
import WorthSnapShared

@main
struct WorthSnapApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
        }
    }
}

@MainActor
final class AppStore: ObservableObject {
    @Published var data: WorthSnapData
    @Published var selectedMonth: String

    private let url: URL

    init() {
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
    }

    func confirm(_ entry: SnapshotEntry) {
        WorthSnapEngine.updateEntry(entryId: entry.id, amount: entry.amount, confirmed: true, in: &data)
        save()
    }

    func addAccount(name: String, direction: Direction, typeId: UUID, currency: String, ownership: Ownership) {
        let order = (data.accounts.map(\.sortOrder).max() ?? 0) + 1
        let account = Account(ledgerId: data.ledger.id, name: name, direction: direction, typeId: typeId, currency: currency, ownership: ownership, sortOrder: order)
        WorthSnapEngine.addAccount(account, to: &data)
        save()
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
            WorthSnapEngine.updateCompletion(snapshotId: snapshot.id, in: &data)
        }
        save()
    }

    func toggleArchive(account: Account) {
        guard let index = data.accounts.firstIndex(where: { $0.id == account.id }) else { return }
        data.accounts[index].archived.toggle()
        data.accounts[index].updatedAt = Date()
        for snapshot in data.snapshots {
            WorthSnapEngine.updateCompletion(snapshotId: snapshot.id, in: &data)
        }
        save()
    }
}
