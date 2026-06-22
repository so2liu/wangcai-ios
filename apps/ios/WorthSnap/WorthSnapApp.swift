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
    /// 数据文件存在但无法读取时为 true：App 进入「安全模式」——展示警告、**禁止保存**，
    /// 以免用一份空数据覆盖掉用户磁盘上仍然完好的原文件。
    @Published private(set) var loadFailed: Bool = false
    /// 安全模式下，损坏原文件被复制到的备份路径（供 UI 告知用户）。
    @Published private(set) var corruptBackupURL: URL?

    private let url: URL

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        url = documents.appendingPathComponent("worthsnap-data.json")

        guard let stored = try? Data(contentsOf: url) else {
            // 全新安装：没有文件，正常初始化示例数据。
            let seeded = WorthSnapEngine.seededData()
            data = seeded
            selectedMonth = AppStore.latestMonth(in: seeded)
            return
        }

        do {
            let decoded = try WorthSnapStore.decode(stored)
            data = decoded
            selectedMonth = AppStore.latestMonth(in: decoded)
        } catch {
            // 关键：解码失败绝不静默覆盖。备份损坏文件、进入安全模式、禁止保存。
            let backup = AppStore.backupCorruptedFile(at: url)
            let placeholder = WorthSnapEngine.seededData()
            data = placeholder
            selectedMonth = AppStore.latestMonth(in: placeholder)
            loadFailed = true
            corruptBackupURL = backup
            NSLog("WorthSnap load failed, entered safe mode: \(error). Backup: \(backup?.lastPathComponent ?? "none")")
        }
    }

    private static func latestMonth(in data: WorthSnapData) -> String {
        data.snapshots
            .filter { WorthSnapEngine.isValidMonth($0.month) }
            .sorted { $0.month < $1.month }
            .last?.month ?? WorthSnapEngine.currentMonth()
    }

    func save() {
        // 安全模式下绝不写盘，保护磁盘上仍然完好的原文件。
        guard !loadFailed else { return }
        do {
            let encoded = try WorthSnapStore.encode(data)
            try AppStore.writeAtomically(encoded, to: url)
        } catch {
            // 写失败不致命：保留磁盘上的旧版本，下次操作会再次尝试。
            NSLog("WorthSnap save failed: \(error)")
        }
    }

    /// 用一份外部数据（如从 JSON 备份恢复）整体替换当前数据。
    /// 成功后退出安全模式并立即落盘——这也是安全模式用户找回数据的出口。
    func replaceAll(with newData: WorthSnapData) {
        data = newData
        loadFailed = false
        corruptBackupURL = nil
        selectedMonth = AppStore.latestMonth(in: newData)
        save()
    }

    /// 从备份文件原始字节恢复：用安全解码校验后替换。失败抛错，绝不破坏现有数据。
    func restore(from raw: Data) throws {
        let decoded = try WorthSnapStore.decode(raw)
        replaceAll(with: decoded)
    }

    /// 原子写入，并在覆盖前把现有文件保留成 `.bak`，作为最近一次的可回滚副本。
    private static func writeAtomically(_ payload: Data, to url: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            let backup = url.appendingPathExtension("bak")
            try? fm.removeItem(at: backup)
            try? fm.copyItem(at: url, to: backup)
        }
        try payload.write(to: url, options: .atomic)
    }

    /// 把无法解析的文件复制一份留证，**不删除、不覆盖**原文件。
    /// 用固定名并保留首份：重启多次不会堆积备份，也不会覆盖最初那次损坏的原始副本。
    @discardableResult
    private static func backupCorruptedFile(at url: URL) -> URL? {
        let fm = FileManager.default
        let dest = url.deletingPathExtension().appendingPathExtension("corrupt.json")
        if fm.fileExists(atPath: dest.path) { return dest }
        do {
            try fm.copyItem(at: url, to: dest)
            return dest
        } catch {
            NSLog("WorthSnap corrupt-backup failed: \(error)")
            return nil
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

    func addAccount(name: String, direction: Direction, typeId: UUID, currency: String, ownerMemberId: UUID?, responsibleMemberId: UUID?) {
        let order = (data.accounts.map(\.sortOrder).max() ?? 0) + 1
        let account = Account(ledgerId: data.ledger.id, name: name, direction: direction, typeId: typeId, currency: currency, ownerMemberId: ownerMemberId, responsibleMemberId: responsibleMemberId, sortOrder: order)
        WorthSnapEngine.addAccount(account, to: &data)
        save()
    }

    func updateAccount(_ account: Account, name: String, direction: Direction, typeId: UUID, currency: String, ownerMemberId: UUID?, responsibleMemberId: UUID?) {
        guard let index = data.accounts.firstIndex(where: { $0.id == account.id }) else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCurrency = currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        data.accounts[index].name = trimmedName
        data.accounts[index].direction = direction
        data.accounts[index].typeId = typeId
        data.accounts[index].currency = normalizedCurrency.isEmpty ? data.accounts[index].currency : normalizedCurrency
        data.accounts[index].ownerMemberId = ownerMemberId
        data.accounts[index].responsibleMemberId = responsibleMemberId
        data.accounts[index].updatedAt = Date()

        for snapshot in data.snapshots {
            WorthSnapEngine.updateCompletion(snapshotId: snapshot.id, in: &data)
        }
        save()
    }

    // MARK: - 成员

    /// 未归档成员，当前成员排在最前，便于表单默认选中本人。
    var activeMembers: [Member] {
        data.members.filter { !$0.archived }.sorted { lhs, rhs in
            if lhs.id == data.currentMemberId { return true }
            if rhs.id == data.currentMemberId { return false }
            return lhs.createdAt < rhs.createdAt
        }
    }

    func memberName(id: UUID?) -> String {
        data.member(id: id)?.name ?? "共同"
    }

    func addMember(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = WorthSnapEngine.addMember(name: trimmed, in: &data)
        save()
    }

    func renameMember(_ member: Member, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = data.members.firstIndex(where: { $0.id == member.id }) else { return }
        data.members[index].name = trimmed
        data.members[index].updatedAt = Date()
        save()
    }

    /// 成员离开：归档（人走数据留），其负责账户转交给本人。
    func archiveMember(_ member: Member) {
        guard member.id != data.currentMemberId else { return } // 不允许移除自己
        WorthSnapEngine.archiveMember(member.id, reassignResponsibleTo: data.currentMemberId, in: &data)
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
