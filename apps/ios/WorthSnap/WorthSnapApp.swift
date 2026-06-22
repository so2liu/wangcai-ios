import SwiftUI
import CloudKit
import Combine
import WorthSnapShared

@main
struct WorthSnapApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .onAppear {
                    appDelegate.store = store
                    if #available(iOS 17.0, *) { store.bootstrapCloudSync() }
                }
        }
    }
}

/// 仅用于接收 CloudKit 共享邀请的系统回调（SwiftUI 生命周期没有等价入口）。
final class AppDelegate: NSObject, UIApplicationDelegate {
    weak var store: AppStore? {
        didSet { flushPendingShareIfPossible() }
    }
    /// 冷启动场景：App 因点开邀请而启动时，系统可能在 RootView.onAppear 注入 store 之前
    /// 就回调 userDidAcceptCloudKitShareWith。此时先缓冲 metadata，待 store 就绪再处理，
    /// 否则邀请会被静默丢弃、用户无法加入家庭。
    private var pendingShareMetadata: CKShare.Metadata?

    func application(_ application: UIApplication, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        if store == nil {
            pendingShareMetadata = cloudKitShareMetadata
        } else {
            handle(cloudKitShareMetadata)
        }
    }

    private func flushPendingShareIfPossible() {
        guard store != nil, let metadata = pendingShareMetadata else { return }
        pendingShareMetadata = nil
        handle(metadata)
    }

    private func handle(_ metadata: CKShare.Metadata) {
        guard #available(iOS 17.0, *) else { return }
        Task { @MainActor in
            await store?.acceptFamilyShare(metadata)
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

    /// iCloud 家庭共享协调器。懒加载：仅在用户开启同步后创建。
    private var _cloud: Any?
    private var cloudCancellable: AnyCancellable?
    @available(iOS 17.0, *)
    var cloud: CloudSyncCoordinator {
        if let existing = _cloud as? CloudSyncCoordinator { return existing }
        let coordinator = CloudSyncCoordinator(
            dataProvider: { [weak self] in self?.data ?? WorthSnapEngine.seededData() },
            applyRemote: { [weak self] records, deletions in self?.applyRemoteRecords(records, deletions: deletions) },
            isSafeMode: { [weak self] in self?.loadFailed ?? true }
        )
        // 把协调器的 @Published（enabled/status）变更转发给 AppStore，
        // 否则只观察 AppStore 的 SettingsView 不会随异步 enable/disable 刷新开关与状态。
        cloudCancellable = coordinator.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        _cloud = coordinator
        return coordinator
    }

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
            // 旧格式（史前无信封 / v1）经迁移会生成新的成员 UUID。若不立即回写 v2，
            // 下次启动会对同一文件重新迁移、生成不同 UUID，开启同步后造成重复成员、owner 漂移。
            // 检测：重新编码与磁盘字节不一致即说明发生了迁移（已是 v2 的文件 round-trip 稳定、不会写）。
            if let reencoded = try? WorthSnapStore.encode(decoded), reencoded != stored {
                try? AppStore.writeAtomically(reencoded, to: url)
            }
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
        persist()
        // 本地改动落盘后，把增量推给 iCloud（仅在已开启同步时生效）。
        if #available(iOS 17.0, *), _cloud != nil {
            cloud.localDidChange(data)
        }
    }

    /// 只写盘、不触发云推送。供本地保存与「合并远端变更」复用，避免远端→本地→再回推的回声。
    private func persist() {
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

    /// 把远端拉取到的同步记录按后写覆盖合并进本地，并落盘（不回推）。
    @available(iOS 17.0, *)
    func applyRemoteRecords(_ records: [SyncRecord], deletions: [String]) {
        guard let merged = try? data.merging(remote: records, deletedRecordNames: deletions) else { return }
        data = merged
        // 合并后当前选中月可能已不存在（远端删了快照），交给 snapshot() 兜底重选。
        if !data.snapshots.contains(where: { $0.month == selectedMonth }) {
            selectedMonth = AppStore.latestMonth(in: data)
        }
        persist()
    }

    /// 接受家庭共享邀请：交给协调器处理，成功后远端数据会自动合并进来。
    /// 加入前清空本地单机的可同步数据（仅保留「自己」这名成员），让位给共享家庭、
    /// 避免旧账户/快照被回传污染对方家庭。
    @available(iOS 17.0, *)
    func acceptFamilyShare(_ metadata: CKShare.Metadata) async {
        await cloud.acceptShare(metadata) { [weak self] in
            guard let self else { return }
            let me = self.data.currentMember ?? Member(name: WorthSnapEngine.defaultMemberName)
            var fresh = self.data
            fresh.members = [me]            // 仅保留自己，作为加入家庭的新成员
            fresh.currentMemberId = me.id
            fresh.accounts = []
            fresh.snapshots = []
            fresh.entries = []
            fresh.tags = []
            fresh.accountTypes = []         // 采用发起人的账户类型，避免重复/冲突
            // 账本是单例：把本地种子账本时间戳压到最早，确保合并时一定采纳发起人的账本，
            // 而不是因「种子账本在安装时创建、反而更新」把对方账本挡在外面。
            fresh.ledger.updatedAt = .distantPast
            self.data = fresh
            self.persist()
        }
    }

    /// App 启动后恢复 iCloud 同步：之前开启过的用户自动重连，无需手动再开。
    /// 安全模式下不启动（避免在数据可疑时触发云端写入）。
    @available(iOS 17.0, *)
    func bootstrapCloudSync() {
        guard !loadFailed, UserDefaults.standard.bool(forKey: CloudSyncCoordinator.enabledKey) else { return }
        cloud.resume()
    }

    /// 用一份外部数据（如从 JSON 备份恢复）整体替换当前数据。
    /// 成功后退出安全模式并立即落盘——这也是安全模式用户找回数据的出口。
    ///
    /// 恢复是「权威操作」：用户明确选定这份数据为准。开启同步时，备份里实体的 updatedAt
    /// 往往比云端旧，若按时间戳增量 diff 既不会上传、还会被云端较新记录合并盖回，恢复就失效了。
    /// 因此把所有实体时间戳顶到当前，确保恢复值上传成功并在本地合并中胜出。
    func replaceAll(with newData: WorthSnapData) {
        var authoritative = newData
        AppStore.touchAllTimestamps(in: &authoritative)
        data = authoritative
        loadFailed = false
        corruptBackupURL = nil
        selectedMonth = AppStore.latestMonth(in: authoritative)
        save()
    }

    /// 把整份数据所有实体的 updatedAt 顶到当前，使其成为同步中的最新版本。
    private static func touchAllTimestamps(in data: inout WorthSnapData) {
        let now = Date()
        data.ledger.updatedAt = now
        for index in data.members.indices { data.members[index].updatedAt = now }
        for index in data.accounts.indices { data.accounts[index].updatedAt = now }
        for index in data.snapshots.indices { data.snapshots[index].updatedAt = now }
        for index in data.entries.indices { data.entries[index].updatedAt = now }
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
