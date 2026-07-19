import Foundation
import CloudKit
import os
import WorthSnapShared

// 本文件实现 CKShare 家庭共享的 CloudKit 同步层。
// 上线门槛：必须在两台真机、两个 iCloud 账号下完成 docs/cloudkit-sharing-testing.md 全部项目。
// 依赖配置（见 project.yml / 项目说明）：
//   1) iCloud capability，容器 = iCloud.com.yueyu.WorthSnap
//   2) Background Modes → Remote notifications
//   3) Push Notifications capability
//   4) CloudKit Dashboard 会在首次写入时自动建出记录类型（含 payload/updatedAt 字段）

private let log = Logger(subsystem: "com.yueyu.WorthSnap", category: "CloudSync")

// TODO: 容器标识硬编码为约定值；若 CloudKit Dashboard 里实际容器不同，改这里。
let familyContainerID = "iCloud.com.yueyu.WorthSnap"
/// 家庭数据所在的自定义 zone。共享以「整 zone 共享」方式进行（CKShare(recordZoneID:)）。
let familyZoneName = "Family"

// MARK: - SyncRecord ↔ CKRecord 映射

enum CloudKitMapping {
    /// 把同步记录写进 CKRecord。payload 放进 encryptedValues：家庭内成员可见明细（金额全透明），
    /// 但对 Apple 与传输层加密，符合「资产数据不应明文驻留」的安全取向。
    static func apply(_ record: SyncRecord, to ck: CKRecord) {
        ck.encryptedValues["payload"] = record.payload
        ck["updatedAt"] = record.updatedAt as CKRecordValue
    }

    static func makeRecord(_ record: SyncRecord, zoneID: CKRecordZone.ID) -> CKRecord {
        let id = CKRecord.ID(recordName: record.recordName, zoneID: zoneID)
        let ck = CKRecord(recordType: record.recordType, recordID: id)
        apply(record, to: ck)
        return ck
    }

    /// 从 CKRecord 还原同步记录；字段缺失（非本 App 写入的记录）时返回 nil。
    static func syncRecord(from ck: CKRecord) -> SyncRecord? {
        guard let payload = ck.encryptedValues["payload"] as? Data,
              let updatedAt = ck["updatedAt"] as? Date else { return nil }
        return SyncRecord(recordType: ck.recordType, recordName: ck.recordID.recordName,
                          updatedAt: updatedAt, payload: payload)
    }
}

// MARK: - 单个数据库（private 或 shared）的同步引擎封装

/// 封装一个 CKSyncEngine。本 App 同时持有两个：
/// - private：本设备作为「发起人」时，家庭数据存自己的私有库 Family zone。
/// - shared：本设备作为「受邀者」时，通过共享库访问对方的 Family zone。
/// 两者共用同一套合并逻辑（WorthSnapData.merging，后写覆盖）。
@available(iOS 17.0, *)
final class DatabaseSyncEngine: NSObject, CKSyncEngineDelegate, @unchecked Sendable {
    private let database: CKDatabase
    private let zoneID: CKRecordZone.ID
    // engine 仅在 init 内赋值一次（delegate 自引用的鸡生蛋顺序所致），之后只读；
    // 远端回调统一 Task @MainActor 跳回主线程，故并发安全由我们自行保证。
    private var engine: CKSyncEngine!

    /// 读取「当前要上传的某条记录」的最新 payload。由协调器接入 AppStore。
    private let recordProvider: (String) -> SyncRecord?
    /// 把远端拉取/删除的变更交回协调器合并进本地。
    private let onRemoteChanges: ([SyncRecord], [String]) -> Void
    private let onZoneDeleted: () -> Void
    /// 持久化 CKSyncEngine 状态（change token 等）。
    private let stateStore: SyncStateStore

    init(database: CKDatabase,
         zoneID: CKRecordZone.ID,
         stateStore: SyncStateStore,
         recordProvider: @escaping (String) -> SyncRecord?,
         onRemoteChanges: @escaping ([SyncRecord], [String]) -> Void,
         onZoneDeleted: @escaping () -> Void = {}) {
        self.database = database
        self.zoneID = zoneID
        self.stateStore = stateStore
        self.recordProvider = recordProvider
        self.onRemoteChanges = onRemoteChanges
        self.onZoneDeleted = onZoneDeleted
        super.init()

        var configuration = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: stateStore.load(),
            delegate: self
        )
        configuration.automaticallySync = true
        engine = CKSyncEngine(configuration)
    }

    /// 标记一批记录待上传（本地有改动时调用）。
    func pushChanges(saveRecordNames: [String], deleteRecordNames: [String]) {
        let saves = saveRecordNames.map { CKSyncEngine.PendingRecordZoneChange.saveRecord(CKRecord.ID(recordName: $0, zoneID: zoneID)) }
        let deletes = deleteRecordNames.map { CKSyncEngine.PendingRecordZoneChange.deleteRecord(CKRecord.ID(recordName: $0, zoneID: zoneID)) }
        engine.state.add(pendingRecordZoneChanges: saves + deletes)
    }

    /// 确保 zone 存在（发起人首次开启共享时需要）。
    func ensureZone() {
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
    }

    /// 主动拉取一次远端变更（开启同步时先看云端是否已有家庭数据）。
    func fetchChanges() async {
        try? await engine.fetchChanges()
    }

    // MARK: CKSyncEngineDelegate

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            stateStore.save(update.stateSerialization)
        case .accountChange(let change):
            // 账号登入/登出/切换：登出时本地 CloudKit 缓存应清空（本地业务数据仍保留）。
            log.info("CloudKit account change: \(String(describing: change.changeType))")
        case .fetchedRecordZoneChanges(let changes):
            let records = changes.modifications.compactMap { CloudKitMapping.syncRecord(from: $0.record) }
            let deletions = changes.deletions.map { $0.recordID.recordName }
            if !records.isEmpty || !deletions.isEmpty {
                onRemoteChanges(records, deletions)
            }
        case .fetchedDatabaseChanges(let changes):
            // 整个 zone 被删除（如对方停止共享）：把该 zone 下数据视为不可用。
            for deletion in changes.deletions {
                log.info("zone deleted: \(deletion.zoneID.zoneName)")
                if deletion.zoneID == zoneID { onZoneDeleted() }
            }
        case .sentRecordZoneChanges, .sentDatabaseChanges,
             .willFetchChanges, .didFetchChanges, .willSendChanges, .didSendChanges,
             .willFetchRecordZoneChanges, .didFetchRecordZoneChanges:
            break
        @unknown default:
            break
        }
    }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        guard !pending.isEmpty else { return nil }

        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { recordID in
            // 为每条待上传记录materialize 出最新 payload；已不存在的记录返回 nil（引擎会清掉该 pending）。
            guard let record = self.recordProvider(recordID.recordName) else {
                syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
                return nil
            }
            let ck = CKRecord(recordType: record.recordType, recordID: recordID)
            CloudKitMapping.apply(record, to: ck)
            return ck
        }
    }
}

// MARK: - CKSyncEngine 状态持久化

/// 把 CKSyncEngine.State.Serialization 存到 Documents，供下次启动续传增量。
final class SyncStateStore: @unchecked Sendable {
    private let url: URL

    init(filename: String) {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        url = documents.appendingPathComponent(filename)
    }

    @available(iOS 17.0, *)
    func load() -> CKSyncEngine.State.Serialization? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    @available(iOS 17.0, *)
    func save(_ serialization: CKSyncEngine.State.Serialization) {
        guard let data = try? JSONEncoder().encode(serialization) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
