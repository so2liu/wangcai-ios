import Foundation

public enum MonthlyReminderDay: Codable, Equatable, Sendable {
    case day(Int)
    case lastDay

    public var title: String {
        switch self {
        case .day(let day): "\(day) 日"
        case .lastDay: "最后一天"
        }
    }

    public var rawStorageValue: String {
        switch self {
        case .day(let day): "day:\(day)"
        case .lastDay: "last"
        }
    }

    public init(day: Int) {
        self = .day(min(max(day, 1), 28))
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case day
    }

    private enum Kind: String, Codable {
        case day
        case lastDay
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .day:
            let day = try container.decode(Int.self, forKey: .day)
            self = .day(min(max(day, 1), 28))
        case .lastDay:
            self = .lastDay
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .day(let day):
            try container.encode(Kind.day, forKey: .kind)
            try container.encode(min(max(day, 1), 28), forKey: .day)
        case .lastDay:
            try container.encode(Kind.lastDay, forKey: .kind)
        }
    }
}

public struct MonthlyReminderConfig: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var day: MonthlyReminderDay
    public var hour: Int
    public var minute: Int
    public var lastCompletedMonth: String?

    public init(isEnabled: Bool = false, day: MonthlyReminderDay = .day(25), hour: Int = 20, minute: Int = 0, lastCompletedMonth: String? = nil) {
        self.isEnabled = isEnabled
        self.day = day
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
        self.lastCompletedMonth = lastCompletedMonth
    }
}

public struct MonthlyReminderSchedule: Equatable, Sendable {
    public var fireDate: Date
    public var snapshotMonth: String

    public init(fireDate: Date, snapshotMonth: String) {
        self.fireDate = fireDate
        self.snapshotMonth = snapshotMonth
    }
}

public enum MonthlyReminderScheduler {
    public static func nextSchedule(
        config: MonthlyReminderConfig,
        snapshots: [Snapshot],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> MonthlyReminderSchedule? {
        guard config.isEnabled else { return nil }

        let completedMonths = Set(snapshots.filter(\.completed).map(\.month))
        let currentMonth = WorthSnapEngine.currentMonth(date: now, calendar: calendar)
        let suppressedCurrentMonth = completedMonths.contains(currentMonth) || config.lastCompletedMonth == currentMonth
        var cursor = suppressedCurrentMonth ? monthOffset(from: now, offset: 1, calendar: calendar) : now

        for _ in 0..<36 {
            let month = WorthSnapEngine.currentMonth(date: cursor, calendar: calendar)
            guard let candidate = reminderDate(forMonthContaining: cursor, config: config, calendar: calendar) else {
                return nil
            }
            if candidate > now, !completedMonths.contains(month), config.lastCompletedMonth != month {
                return MonthlyReminderSchedule(fireDate: candidate, snapshotMonth: month)
            }
            cursor = monthOffset(from: cursor, offset: 1, calendar: calendar)
        }

        return nil
    }

    public static func reminderDate(
        forMonthContaining date: Date,
        config: MonthlyReminderConfig,
        calendar: Calendar = .current
    ) -> Date? {
        var comps = calendar.dateComponents([.year, .month], from: date)
        comps.day = dayNumber(inMonthContaining: date, day: config.day, calendar: calendar)
        comps.hour = config.hour
        comps.minute = config.minute
        comps.second = 0
        return calendar.date(from: comps)
    }

    public static func dayNumber(
        inMonthContaining date: Date,
        day: MonthlyReminderDay,
        calendar: Calendar = .current
    ) -> Int {
        switch day {
        case .day(let day):
            return min(max(day, 1), 28)
        case .lastDay:
            return calendar.range(of: .day, in: .month, for: date)?.count ?? 28
        }
    }

    private static func monthOffset(from date: Date, offset: Int, calendar: Calendar) -> Date {
        let start = calendar.dateInterval(of: .month, for: date)?.start ?? date
        return calendar.date(byAdding: .month, value: offset, to: start) ?? date
    }
}
