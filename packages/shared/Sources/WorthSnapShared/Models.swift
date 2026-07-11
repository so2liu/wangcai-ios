import Foundation

public enum Direction: String, Codable, CaseIterable, Identifiable, Sendable {
    case asset
    case liability

    public var id: String { rawValue }
    public var title: String { self == .asset ? "资产" : "负债" }
}

/// 账户相对「当前查看者」的归属视角。由 `Account.ownerMemberId` 结合当前成员动态计算，
/// 仅用于 UI 展示与三栏聚合，不直接持久化——同一份数据在不同成员设备上「我的 / TA的」会自动互换。
public enum OwnershipView: String, CaseIterable, Identifiable, Sendable {
    /// 归属当前查看者本人。
    case mine
    /// 归属其他成员（典型为伴侣；成员超过两人时统一归这一类）。
    case theirs
    /// 共同财产（ownerMemberId 为空）。
    case shared

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .mine: "我的"
        case .theirs: "TA的"
        case .shared: "共同"
        }
    }
}

/// 家庭成员：会登录、会录入的人（典型 2 人）。
/// 离开 = `archived`（人走数据留，绝不连带删除其录入的账户与历史）。
public struct Member: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// CloudKit 身份（`CKShare.Participant` 的 userRecordID）。阶段 A 的本机成员为 nil，
    /// 加入家庭后回填，用于把同一 iCloud 用户在不同设备上识别为同一成员。
    public var icloudUserRecordID: String?
    /// 成员标识色（十六进制，如 "F2B705"），用于头像/三栏点缀。
    public var colorHex: String
    public var archived: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), name: String, icloudUserRecordID: String? = nil, colorHex: String = "C8A24B", archived: Bool = false, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.icloudUserRecordID = icloudUserRecordID
        self.colorHex = colorHex
        self.archived = archived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct Ledger: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var baseCurrency: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), name: String = "旺财账本", baseCurrency: String = "CNY", createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.baseCurrency = baseCurrency
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct AccountType: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var direction: Direction
    public var isSystem: Bool
    public var archived: Bool

    public init(id: UUID = UUID(), name: String, direction: Direction, isSystem: Bool = false, archived: Bool = false) {
        self.id = id
        self.name = name
        self.direction = direction
        self.isSystem = isSystem
        self.archived = archived
    }
}

public struct Tag: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var archived: Bool

    public init(id: UUID = UUID(), name: String, archived: Bool = false) {
        self.id = id
        self.name = name
        self.archived = archived
    }
}

public struct Account: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var ledgerId: UUID
    public var name: String
    public var direction: Direction
    public var typeId: UUID
    public var currency: String
    /// 归属的成员 id；nil 表示「共同」财产（房产、房贷、家庭基金等）。
    public var ownerMemberId: UUID?
    /// 每月负责更新此账户的成员 id；nil 表示未指定（盘点时回退给归属成员）。
    public var responsibleMemberId: UUID?
    public var tagIds: [UUID]
    public var sortOrder: Int
    public var archived: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), ledgerId: UUID, name: String, direction: Direction, typeId: UUID, currency: String = "CNY", ownerMemberId: UUID? = nil, responsibleMemberId: UUID? = nil, tagIds: [UUID] = [], sortOrder: Int = 0, archived: Bool = false, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.ledgerId = ledgerId
        self.name = name
        self.direction = direction
        self.typeId = typeId
        self.currency = currency
        self.ownerMemberId = ownerMemberId
        self.responsibleMemberId = responsibleMemberId
        self.tagIds = tagIds
        self.sortOrder = sortOrder
        self.archived = archived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct Snapshot: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var ledgerId: UUID
    public var month: String
    public var baseCurrency: String
    public var exchangeRates: [String: Decimal]
    public var exchangeRateSource: String
    public var note: String
    public var completed: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), ledgerId: UUID, month: String, baseCurrency: String = "CNY", exchangeRates: [String: Decimal] = ["CNY": 1], exchangeRateSource: String = "本地缓存", note: String = "", completed: Bool = false, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.ledgerId = ledgerId
        self.month = month
        self.baseCurrency = baseCurrency
        self.exchangeRates = exchangeRates
        self.exchangeRateSource = exchangeRateSource
        self.note = note
        self.completed = completed
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct SnapshotEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var snapshotId: UUID
    public var accountId: UUID
    public var amount: Decimal
    public var currency: String
    public var exchangeRate: Decimal
    public var convertedAmount: Decimal
    public var confirmed: Bool
    public var note: String
    public var updatedAt: Date

    /// 创建快照时冻结的账户口径。账户之后改名、改类型或在资产/负债之间调整，
    /// 都不应重写已经发生的历史。
    public var accountName: String
    public var accountDirection: Direction
    public var accountTypeId: UUID
    public var accountOwnerMemberId: UUID?

    public init(id: UUID = UUID(), snapshotId: UUID, accountId: UUID, amount: Decimal = 0, currency: String = "CNY", exchangeRate: Decimal = 1, confirmed: Bool = false, note: String = "", updatedAt: Date = Date(), accountName: String, accountDirection: Direction, accountTypeId: UUID, accountOwnerMemberId: UUID?) {
        self.id = id
        self.snapshotId = snapshotId
        self.accountId = accountId
        self.amount = amount
        self.currency = currency
        self.exchangeRate = exchangeRate
        self.convertedAmount = amount * exchangeRate
        self.confirmed = confirmed
        self.note = note
        self.updatedAt = updatedAt
        self.accountName = accountName
        self.accountDirection = accountDirection
        self.accountTypeId = accountTypeId
        self.accountOwnerMemberId = accountOwnerMemberId
    }
}

public struct WorthSnapData: Codable, Equatable, Sendable {
    public var ledger: Ledger
    public var members: [Member]
    /// 本设备登录者对应的成员 id。决定「我的 / TA的」如何翻译。
    /// 加入家庭后指向自己在该家庭里的成员记录。
    public var currentMemberId: UUID
    public var accountTypes: [AccountType]
    public var tags: [Tag]
    public var accounts: [Account]
    public var snapshots: [Snapshot]
    public var entries: [SnapshotEntry]

    public init(ledger: Ledger = Ledger(), members: [Member] = [], currentMemberId: UUID = UUID(), accountTypes: [AccountType] = [], tags: [Tag] = [], accounts: [Account] = [], snapshots: [Snapshot] = [], entries: [SnapshotEntry] = []) {
        self.ledger = ledger
        self.members = members
        self.currentMemberId = currentMemberId
        self.accountTypes = accountTypes
        self.tags = tags
        self.accounts = accounts
        self.snapshots = snapshots
        self.entries = entries
    }

    /// 当前查看者成员。约定：`currentMemberId` 必然存在于 `members`（seed/迁移时保证）。
    public var currentMember: Member? { members.first { $0.id == currentMemberId } }

    public func member(id: UUID?) -> Member? {
        guard let id else { return nil }
        return members.first { $0.id == id }
    }

    /// 账户相对当前查看者的归属视角。
    public func ownershipView(of account: Account) -> OwnershipView {
        guard let owner = account.ownerMemberId else { return .shared }
        return owner == currentMemberId ? .mine : .theirs
    }
}
