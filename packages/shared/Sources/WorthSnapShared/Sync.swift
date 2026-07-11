import Foundation

/// 同步记录：把每个实体表达成一条「可独立同步」的记录。
/// payload 为该实体的 JSON 编码，`updatedAt` 用于后写覆盖（last-write-wins）冲突解决。
///
/// 设计取舍：CloudKit 里每条记录只存 `payload`(Bytes) + `updatedAt`(Date) 两个字段，
/// schema 统一、不需要为每个模型字段建列，映射出错面最小。代价是 CloudKit 端不可按字段查询——
/// 但家庭共享是「整 zone 全量拉取」，本就不需要字段级查询。
public struct SyncRecord: Equatable, Sendable {
    public var recordType: String
    /// 记录名 = 实体 UUID 字符串，全局稳定，作为 CKRecord.ID 的 recordName。
    public var recordName: String
    public var updatedAt: Date
    public var payload: Data

    public init(recordType: String, recordName: String, updatedAt: Date, payload: Data) {
        self.recordType = recordType
        self.recordName = recordName
        self.updatedAt = updatedAt
        self.payload = payload
    }
}

public enum SyncRecordType {
    public static let ledger = "Ledger"
    public static let member = "Member"
    public static let accountType = "AccountType"
    public static let tag = "Tag"
    public static let account = "Account"
    public static let snapshot = "Snapshot"
    public static let entry = "SnapshotEntry"

    /// 全部需要同步的类型。`currentMemberId` 是「本设备视角」，刻意不在其中——
    /// 同一份家庭数据在每台设备上「我」指向各自的成员。
    public static let all = [ledger, member, accountType, tag, account, snapshot, entry]
}

public extension WorthSnapData {
    /// 把整份数据拆成同步记录集合。用稳定的编码器（排序键 + ISO8601 日期）保证同一实体
    /// 反复编码得到一致的字节，避免「内容没变却被判为有改动」反复上传。
    func toSyncRecords() throws -> [SyncRecord] {
        let encoder = WorthSnapStore.makeEncoder()
        var records: [SyncRecord] = []

        records.append(SyncRecord(recordType: SyncRecordType.ledger, recordName: ledger.id.uuidString,
                                  updatedAt: ledger.updatedAt, payload: try encoder.encode(ledger)))
        for member in members {
            records.append(SyncRecord(recordType: SyncRecordType.member, recordName: member.id.uuidString,
                                      updatedAt: member.updatedAt, payload: try encoder.encode(member)))
        }
        // AccountType / Tag 无独立时间戳：用账本更新时间作为代理。它们是低频引用数据
        // （系统类型 + 少量自定义），冲突时按账本时间做 LWW 已足够。
        for type in accountTypes {
            records.append(SyncRecord(recordType: SyncRecordType.accountType, recordName: type.id.uuidString,
                                      updatedAt: ledger.updatedAt, payload: try encoder.encode(type)))
        }
        for tag in tags {
            records.append(SyncRecord(recordType: SyncRecordType.tag, recordName: tag.id.uuidString,
                                      updatedAt: ledger.updatedAt, payload: try encoder.encode(tag)))
        }
        for account in accounts {
            records.append(SyncRecord(recordType: SyncRecordType.account, recordName: account.id.uuidString,
                                      updatedAt: account.updatedAt, payload: try encoder.encode(account)))
        }
        for snapshot in snapshots {
            records.append(SyncRecord(recordType: SyncRecordType.snapshot, recordName: snapshot.id.uuidString,
                                      updatedAt: snapshot.updatedAt, payload: try encoder.encode(snapshot)))
        }
        for entry in entries {
            records.append(SyncRecord(recordType: SyncRecordType.entry, recordName: entry.id.uuidString,
                                      updatedAt: entry.updatedAt, payload: try encoder.encode(entry)))
        }
        return records
    }

    /// 把远端拉取到的记录合并进本份数据，按 `updatedAt` 做后写覆盖：
    /// 远端记录的 updatedAt **不早于**本地同 id 实体时才采纳（远端较新或并列）。
    /// `deletedRecordNames` 里的实体（按 UUID 字符串）从本地移除。
    /// `currentMemberId` 始终保留本地值——它是本设备视角，不随同步改变。
    func merging(remote: [SyncRecord], deletedRecordNames: [String] = []) throws -> WorthSnapData {
        let decoder = WorthSnapStore.makeDecoder()
        var result = self

        // 旧版 CloudKit 的 SnapshotEntry payload 没有冻结账户口径。先合并其余实体，
        // 尤其是 Account，再处理 Entry，才能用同批次的账户记录安全补齐旧 payload。
        let orderedRemote = remote.sorted {
            ($0.recordType == SyncRecordType.entry ? 1 : 0) < ($1.recordType == SyncRecordType.entry ? 1 : 0)
        }
        for record in orderedRemote {
            guard let uuid = UUID(uuidString: record.recordName) else { continue }
            switch record.recordType {
            case SyncRecordType.ledger:
                // 账本单例：远端不早于本地则采纳。
                if record.updatedAt >= result.ledger.updatedAt, let value = try? decoder.decode(Ledger.self, from: record.payload) {
                    result.ledger = value
                }
            case SyncRecordType.member:
                let value = try decoder.decode(Member.self, from: record.payload)
                upsert(&result.members, value, id: \.id, remoteUpdatedAt: record.updatedAt, localUpdatedAt: { $0.updatedAt })
            case SyncRecordType.accountType:
                let value = try decoder.decode(AccountType.self, from: record.payload)
                // 无时间戳：缺失则插入，存在则远端覆盖（低频引用数据，见 toSyncRecords 注释）。
                if let index = result.accountTypes.firstIndex(where: { $0.id == uuid }) {
                    result.accountTypes[index] = value
                } else {
                    result.accountTypes.append(value)
                }
            case SyncRecordType.tag:
                let value = try decoder.decode(Tag.self, from: record.payload)
                if let index = result.tags.firstIndex(where: { $0.id == uuid }) {
                    result.tags[index] = value
                } else {
                    result.tags.append(value)
                }
            case SyncRecordType.account:
                let value = try decoder.decode(Account.self, from: record.payload)
                upsert(&result.accounts, value, id: \.id, remoteUpdatedAt: record.updatedAt, localUpdatedAt: { $0.updatedAt })
            case SyncRecordType.snapshot:
                let value = try decoder.decode(Snapshot.self, from: record.payload)
                upsert(&result.snapshots, value, id: \.id, remoteUpdatedAt: record.updatedAt, localUpdatedAt: { $0.updatedAt })
            case SyncRecordType.entry:
                let value: SnapshotEntry
                do {
                    value = try decoder.decode(SnapshotEntry.self, from: record.payload)
                } catch {
                    // schema v2 及更早的 CloudKit 明细是裸 JSON，不经过磁盘信封迁移。
                    // 用已合并的账户补齐 v3 新增字段，避免一条旧记录让整批远端数据被丢弃。
                    let legacy = try decoder.decode(LegacySnapshotEntry.self, from: record.payload)
                    guard let account = result.accounts.first(where: { $0.id == legacy.accountId }) else { throw error }
                    value = legacy.upgraded(using: account)
                }
                upsert(&result.entries, value, id: \.id, remoteUpdatedAt: record.updatedAt, localUpdatedAt: { $0.updatedAt })
            default:
                continue
            }
        }

        // 删除：按 UUID 从各集合移除。
        let deletedUUIDs = Set(deletedRecordNames.compactMap { UUID(uuidString: $0) })
        if !deletedUUIDs.isEmpty {
            result.members.removeAll { deletedUUIDs.contains($0.id) }
            result.accountTypes.removeAll { deletedUUIDs.contains($0.id) }
            result.tags.removeAll { deletedUUIDs.contains($0.id) }
            result.accounts.removeAll { deletedUUIDs.contains($0.id) }
            result.snapshots.removeAll { deletedUUIDs.contains($0.id) }
            result.entries.removeAll { deletedUUIDs.contains($0.id) }
        }
        return result
    }
}

/// CloudKit schema v2 及更早版本的 SnapshotEntry 裸 payload。
private struct LegacySnapshotEntry: Codable {
    var id: UUID
    var snapshotId: UUID
    var accountId: UUID
    var amount: Decimal
    var currency: String
    var exchangeRate: Decimal
    var convertedAmount: Decimal
    var confirmed: Bool
    var note: String
    var updatedAt: Date

    func upgraded(using account: Account) -> SnapshotEntry {
        SnapshotEntry(id: id, snapshotId: snapshotId, accountId: accountId, amount: amount,
                      currency: currency, exchangeRate: exchangeRate, confirmed: confirmed,
                      note: note, updatedAt: updatedAt, accountName: account.name,
                      accountDirection: account.direction, accountTypeId: account.typeId,
                      accountOwnerMemberId: account.ownerMemberId)
    }
}

/// 后写覆盖的 upsert：远端 updatedAt 不早于本地同 id 项时插入/替换；本地较新则保留本地。
private func upsert<T>(_ items: inout [T], _ value: T, id: (T) -> UUID, remoteUpdatedAt: Date, localUpdatedAt: (T) -> Date) {
    let targetId = id(value)
    if let index = items.firstIndex(where: { id($0) == targetId }) {
        if remoteUpdatedAt >= localUpdatedAt(items[index]) {
            items[index] = value
        }
    } else {
        items.append(value)
    }
}
