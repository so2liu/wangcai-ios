import Foundation
import SwiftUI
import CloudKit
import os
import WorthSnapShared

// ⚠️ 同 CloudSync.swift：CKShare 邀请/接受流程的完整实现，但未经真机验证。

private let log = Logger(subsystem: "com.yueyu.WorthSnap", category: "FamilySharing")

/// 本设备相对「家庭」的角色，决定数据走私有库还是共享库。持久化在 UserDefaults。
enum FamilyRole: String {
    /// 发起人 / 单机：家庭数据在自己的私有库 Family zone。
    case owner
    /// 受邀者：家庭数据在共享库（对方的 Family zone）。
    case participant
}

/// CloudKit 同步协调器：对 AppStore 暴露「开启同步 / 邀请家人 / 接受邀请」，
/// 内部按角色选用 private 或 shared 引擎，并把远端变更按后写覆盖合并回 AppStore。
@available(iOS 17.0, *)
@MainActor
final class CloudSyncCoordinator: ObservableObject {
    enum Status: Equatable { case off, syncing, idle, error(String) }

    static let enabledKey = "family.syncEnabled"

    @Published private(set) var status: Status = .off
    @Published private(set) var enabled: Bool = UserDefaults.standard.bool(forKey: CloudSyncCoordinator.enabledKey)

    private func setEnabled(_ value: Bool) {
        enabled = value
        UserDefaults.standard.set(value, forKey: Self.enabledKey)
    }

    private let container: CKContainer
    /// 发起人/单机自己的 Family zone（私有库）。
    private let ownerZoneID: CKRecordZone.ID
    private var privateEngine: DatabaseSyncEngine?
    private var sharedEngine: DatabaseSyncEngine?

    /// 受邀者要同步的共享 zone：归发起人所有，从被接受的 CKShare.Metadata 取得后持久化。
    /// 必须用它而非本机 zone，否则共享库引擎会指向参与者自己的空 zone，永远拉不到家庭数据。
    private var sharedZoneID: CKRecordZone.ID? {
        get {
            let defaults = UserDefaults.standard
            guard let name = defaults.string(forKey: "family.sharedZone.name"),
                  let owner = defaults.string(forKey: "family.sharedZone.owner") else { return nil }
            return CKRecordZone.ID(zoneName: name, ownerName: owner)
        }
        set {
            let defaults = UserDefaults.standard
            defaults.set(newValue?.zoneName, forKey: "family.sharedZone.name")
            defaults.set(newValue?.ownerName, forKey: "family.sharedZone.owner")
        }
    }

    /// 读取 AppStore 当前全量数据（用于 diff 出待上传记录、materialize payload）。
    private let dataProvider: () -> WorthSnapData
    /// 把远端变更合并回 AppStore（在主线程执行）。
    private let applyRemote: ([SyncRecord], [String]) -> Void

    /// 上次已同步的记录指纹（recordName → updatedAt），用于本地改动时算增量。
    private var lastSynced: [String: Date] = [:]

    private var role: FamilyRole {
        get { FamilyRole(rawValue: UserDefaults.standard.string(forKey: "family.role") ?? "") ?? .owner }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "family.role") }
    }

    init(dataProvider: @escaping () -> WorthSnapData,
         applyRemote: @escaping ([SyncRecord], [String]) -> Void) {
        self.container = CKContainer(identifier: familyContainerID)
        self.ownerZoneID = CKRecordZone.ID(zoneName: familyZoneName, ownerName: CKCurrentUserDefaultName)
        self.dataProvider = dataProvider
        self.applyRemote = applyRemote
    }

    // MARK: 开启 / 增量推送

    /// 开启 iCloud 同步：检查账号、起对应角色的引擎、把本地全量推一遍。
    func enable() async {
        let accountStatus = (try? await container.accountStatus()) ?? .couldNotDetermine
        guard accountStatus == .available else {
            status = .error("请先在系统设置登录 iCloud")
            return
        }
        setEnabled(true)
        status = .syncing
        startEngines()
        // 首次开启：建 zone 并把本地全量标记为待上传。
        privateEngine?.ensureZone()
        localDidChange(dataProvider())
        status = .idle
    }

    /// App 启动时恢复同步：之前已开启过的用户无需手动再开。
    /// 不重新全量推送——CKSyncEngine 的 pending 变更与 change token 已随状态序列化持久化，
    /// 这里只重建引擎并按当前数据重置指纹，供后续增量 diff 使用。
    func resume() {
        guard enabled else { return }
        status = .syncing
        startEngines()
        if let records = try? dataProvider().toSyncRecords() {
            lastSynced = Dictionary(uniqueKeysWithValues: records.map { ($0.recordName, $0.updatedAt) })
        }
        status = .idle
    }

    private func startEngines() {
        let onRemote: ([SyncRecord], [String]) -> Void = { [weak self] records, deletions in
            Task { @MainActor in self?.handleRemoteChanges(records, deletions) }
        }
        switch role {
        case .owner:
            // 发起人/单机：数据在自己私有库的 Family zone。
            privateEngine = DatabaseSyncEngine(
                database: container.privateCloudDatabase, zoneID: ownerZoneID,
                stateStore: SyncStateStore(filename: "cksync-private.state"),
                recordProvider: { [weak self] name in self?.record(named: name) },
                onRemoteChanges: onRemote
            )
        case .participant:
            // 受邀者：数据在共享库里发起人拥有的 zone（来自被接受的邀请），不是本机 zone。
            guard let sharedZone = sharedZoneID else {
                status = .error("尚未取得共享家庭信息，请重新接受邀请")
                return
            }
            sharedEngine = DatabaseSyncEngine(
                database: container.sharedCloudDatabase, zoneID: sharedZone,
                stateStore: SyncStateStore(filename: "cksync-shared.state"),
                recordProvider: { [weak self] name in self?.record(named: name) },
                onRemoteChanges: onRemote
            )
        }
    }

    /// 本地数据有改动：算出与上次同步的差异，把变更/删除推给当前角色对应的引擎。
    func localDidChange(_ data: WorthSnapData) {
        guard enabled, let records = try? data.toSyncRecords() else { return }
        let current = Dictionary(uniqueKeysWithValues: records.map { ($0.recordName, $0.updatedAt) })

        let changed = records.filter { rec in
            guard let prev = lastSynced[rec.recordName] else { return true } // 新增
            return rec.updatedAt > prev // 更新
        }.map(\.recordName)
        let deleted = lastSynced.keys.filter { current[$0] == nil }

        let engine = (role == .participant ? sharedEngine : privateEngine)
        engine?.pushChanges(saveRecordNames: changed, deleteRecordNames: Array(deleted))
        lastSynced = current
    }

    /// 远端变更进来：合并进 AppStore，并刷新同步指纹，避免把刚收到的远端记录又回推（回声）。
    private func handleRemoteChanges(_ records: [SyncRecord], _ deletions: [String]) {
        applyRemote(records, deletions)
        if let refreshed = try? dataProvider().toSyncRecords() {
            lastSynced = Dictionary(uniqueKeysWithValues: refreshed.map { ($0.recordName, $0.updatedAt) })
        }
    }

    /// 为指定 recordName materialize 当前 payload。
    private func record(named name: String) -> SyncRecord? {
        (try? dataProvider().toSyncRecords())?.first { $0.recordName == name }
    }

    // MARK: 邀请家人（发起人）

    /// 创建（或取得）家庭 zone 的共享对象，供 UICloudSharingController 展示邀请界面。
    func makeShare() async throws -> (CKShare, CKContainer) {
        role = .owner
        if !enabled { await enable() }
        let zone = CKRecordZone(zoneID: ownerZoneID)
        // zone 已存在时 save 幂等。
        _ = try? await container.privateCloudDatabase.save(zone)

        let share = CKShare(recordZoneID: ownerZoneID)
        share[CKShare.SystemFieldKey.title] = "旺财 · 家庭账本" as CKRecordValue
        share.publicPermission = .none // 仅被邀请者可访问
        _ = try await container.privateCloudDatabase.save(share)
        return (share, container)
    }

    // MARK: 接受邀请（受邀者）

    /// 处理系统回调的 CKShare.Metadata：接受共享、切换为受邀者角色、拉取家庭数据。
    /// `clearLocalForJoin` 在首次拉取前清空本地可同步集合（见调用方 AppStore），
    /// 避免单机旧数据残留并被回传污染共享家庭。
    func acceptShare(_ metadata: CKShare.Metadata, clearLocalForJoin: @MainActor () -> Void) async {
        do {
            try await container.accept(metadata)
            role = .participant
            setEnabled(true)
            // 记下共享 zone（归发起人所有）：CKShare 记录所在的 zone 即家庭数据 zone。
            sharedZoneID = metadata.share.recordID.zoneID
            // 让位给共享家庭：先清本地单机数据，再清同步指纹、重建共享引擎。
            clearLocalForJoin()
            lastSynced = [:]
            startEngines()
            // 把「自己」作为新成员推进家庭（清理后本地仅保留当前成员）。
            localDidChange(dataProvider())
            status = .idle
        } catch {
            log.error("accept share failed: \(error.localizedDescription)")
            status = .error("接受邀请失败：\(error.localizedDescription)")
        }
    }
}

// MARK: - 邀请界面（UICloudSharingController 包装）

/// 包装系统共享控制器：展示「通过 AirDrop / 信息 / 二维码邀请家人」。
@available(iOS 17.0, *)
struct FamilyShareSheet: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowReadWrite, .allowPrivate] // 家庭成员人人平等、可读写
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            log.error("share save failed: \(error.localizedDescription)")
        }
        func itemTitle(for csc: UICloudSharingController) -> String? { "旺财 · 家庭账本" }
    }
}
