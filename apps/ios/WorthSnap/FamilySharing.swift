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

    @Published private(set) var status: Status = .off
    @Published private(set) var enabled: Bool = false

    private let container: CKContainer
    private let zoneID: CKRecordZone.ID
    private var privateEngine: DatabaseSyncEngine?
    private var sharedEngine: DatabaseSyncEngine?

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
        // owner 的数据放自己私有库；participant 通过共享库访问对方 zone（owner 名也即对方）。
        self.zoneID = CKRecordZone.ID(zoneName: familyZoneName, ownerName: CKCurrentUserDefaultName)
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
        enabled = true
        status = .syncing
        startEngines()
        // 首次开启：建 zone 并把本地全量标记为待上传。
        privateEngine?.ensureZone()
        localDidChange(dataProvider())
        status = .idle
    }

    private func startEngines() {
        let privateState = SyncStateStore(filename: "cksync-private.state")
        privateEngine = DatabaseSyncEngine(
            database: container.privateCloudDatabase, zoneID: zoneID, stateStore: privateState,
            recordProvider: { [weak self] name in self?.record(named: name) },
            onRemoteChanges: { [weak self] records, deletions in
                Task { @MainActor in self?.handleRemoteChanges(records, deletions) }
            }
        )
        // 受邀者：共享库引擎（zone 归对方所有，ownerName 由接受流程确定）。
        if role == .participant {
            let sharedState = SyncStateStore(filename: "cksync-shared.state")
            sharedEngine = DatabaseSyncEngine(
                database: container.sharedCloudDatabase, zoneID: zoneID, stateStore: sharedState,
                recordProvider: { [weak self] name in self?.record(named: name) },
                onRemoteChanges: { [weak self] records, deletions in
                    Task { @MainActor in self?.applyRemote(records, deletions) }
                }
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
        let zone = CKRecordZone(zoneID: zoneID)
        // zone 已存在时 save 幂等。
        _ = try? await container.privateCloudDatabase.save(zone)

        let share = CKShare(recordZoneID: zoneID)
        share[CKShare.SystemFieldKey.title] = "旺财 · 家庭账本" as CKRecordValue
        share.publicPermission = .none // 仅被邀请者可访问
        _ = try await container.privateCloudDatabase.save(share)
        return (share, container)
    }

    // MARK: 接受邀请（受邀者）

    /// 处理系统回调的 CKShare.Metadata：接受共享、切换为受邀者角色、拉取家庭数据。
    func acceptShare(_ metadata: CKShare.Metadata) async {
        do {
            try await container.accept(metadata)
            role = .participant
            enabled = true
            // 受邀者本地原有的「单机家庭」让位给共享家庭：清掉本地同步指纹并重建共享引擎，
            // 全量拉取由 CKSyncEngine 自动完成，远端记录经 merging 合并进 AppStore。
            lastSynced = [:]
            startEngines()
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
