import Foundation

public enum Direction: String, Codable, CaseIterable, Identifiable, Sendable {
    case asset
    case liability

    public var id: String { rawValue }
    public var title: String { self == .asset ? "资产" : "负债" }
}

public enum Ownership: String, Codable, CaseIterable, Identifiable, Sendable {
    case me
    case partner
    case shared

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .me: "我"
        case .partner: "伴侣"
        case .shared: "共同"
        }
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
    public var ownership: Ownership
    public var tagIds: [UUID]
    public var sortOrder: Int
    public var archived: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), ledgerId: UUID, name: String, direction: Direction, typeId: UUID, currency: String = "CNY", ownership: Ownership = .me, tagIds: [UUID] = [], sortOrder: Int = 0, archived: Bool = false, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.ledgerId = ledgerId
        self.name = name
        self.direction = direction
        self.typeId = typeId
        self.currency = currency
        self.ownership = ownership
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
    public var snapshotDate: Date
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), ledgerId: UUID, month: String, baseCurrency: String = "CNY", exchangeRates: [String: Decimal] = ["CNY": 1], exchangeRateSource: String = "本地缓存", note: String = "", completed: Bool = false, snapshotDate: Date = Date(), createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.ledgerId = ledgerId
        self.month = month
        self.baseCurrency = baseCurrency
        self.exchangeRates = exchangeRates
        self.exchangeRateSource = exchangeRateSource
        self.note = note
        self.completed = completed
        self.snapshotDate = snapshotDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case ledgerId
        case month
        case baseCurrency
        case exchangeRates
        case exchangeRateSource
        case note
        case completed
        case snapshotDate
        case createdAt
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        ledgerId = try container.decode(UUID.self, forKey: .ledgerId)
        month = try container.decode(String.self, forKey: .month)
        baseCurrency = try container.decode(String.self, forKey: .baseCurrency)
        exchangeRates = try container.decode([String: Decimal].self, forKey: .exchangeRates)
        exchangeRateSource = try container.decode(String.self, forKey: .exchangeRateSource)
        note = try container.decode(String.self, forKey: .note)
        completed = try container.decode(Bool.self, forKey: .completed)
        let migratedMonthStart = Snapshot.monthStartDate(month) ?? Date(timeIntervalSince1970: 0)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? migratedMonthStart
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        snapshotDate = try container.decodeIfPresent(Date.self, forKey: .snapshotDate) ?? createdAt
    }

    private static func monthStartDate(_ month: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM"
        formatter.isLenient = false
        guard let date = formatter.date(from: month), formatter.string(from: date) == month else {
            return nil
        }
        return date
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

    public init(id: UUID = UUID(), snapshotId: UUID, accountId: UUID, amount: Decimal = 0, currency: String = "CNY", exchangeRate: Decimal = 1, confirmed: Bool = false, note: String = "", updatedAt: Date = Date()) {
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
    }
}

public struct WorthSnapData: Codable, Equatable, Sendable {
    public var ledger: Ledger
    public var accountTypes: [AccountType]
    public var tags: [Tag]
    public var accounts: [Account]
    public var snapshots: [Snapshot]
    public var entries: [SnapshotEntry]
    public var monthlyReminder: MonthlyReminderConfig

    public init(ledger: Ledger = Ledger(), accountTypes: [AccountType] = [], tags: [Tag] = [], accounts: [Account] = [], snapshots: [Snapshot] = [], entries: [SnapshotEntry] = [], monthlyReminder: MonthlyReminderConfig = MonthlyReminderConfig()) {
        self.ledger = ledger
        self.accountTypes = accountTypes
        self.tags = tags
        self.accounts = accounts
        self.snapshots = snapshots
        self.entries = entries
        self.monthlyReminder = monthlyReminder
    }

    private enum CodingKeys: String, CodingKey {
        case ledger
        case accountTypes
        case tags
        case accounts
        case snapshots
        case entries
        case monthlyReminder
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ledger = try container.decode(Ledger.self, forKey: .ledger)
        accountTypes = try container.decode([AccountType].self, forKey: .accountTypes)
        tags = try container.decode([Tag].self, forKey: .tags)
        accounts = try container.decode([Account].self, forKey: .accounts)
        snapshots = try container.decode([Snapshot].self, forKey: .snapshots)
        entries = try container.decode([SnapshotEntry].self, forKey: .entries)
        monthlyReminder = try container.decodeIfPresent(MonthlyReminderConfig.self, forKey: .monthlyReminder) ?? MonthlyReminderConfig()
        if monthlyReminder.lastCompletedMonth == nil {
            let currentMonth = WorthSnapEngine.currentMonth()
            if snapshots.contains(where: { $0.month == currentMonth && $0.completed }) {
                monthlyReminder.lastCompletedMonth = currentMonth
            }
        }
    }
}
