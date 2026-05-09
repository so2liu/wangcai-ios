import Foundation
import WorthSnapShared

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("Check failed: \(message)\n", stderr)
        exit(1)
    }
}

func date(_ text: String) -> Date {
    guard let date = ISO8601DateFormatter().date(from: text) else {
        fputs("Invalid fixture date: \(text)\n", stderr)
        exit(1)
    }
    return date
}

var utcCalendar = Calendar(identifier: .gregorian)
utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!

expect(AmountParser.parse("12.3万") == Decimal(123_000), "parse wan unit")
expect(AmountParser.parse("1,234.56") == Decimal(string: "1234.56"), "parse comma decimal")
expect(AmountParser.parse("-1") == nil, "reject negative")

var data = WorthSnapEngine.sampleData()
let snapshot = data.snapshots[0]
let accountsById = Dictionary(uniqueKeysWithValues: data.accounts.map { ($0.id, $0) })
for entry in data.entries.filter({ $0.snapshotId == snapshot.id }) {
    let amount: Decimal = accountsById[entry.accountId]?.direction == .asset ? 100 : 30
    WorthSnapEngine.updateEntry(entryId: entry.id, amount: amount, confirmed: true, in: &data)
}

let totals = WorthSnapEngine.totals(for: snapshot, in: data)
expect(totals.totalAssets == 200, "asset totals")
expect(totals.totalLiabilities == 30, "liability totals")
expect(totals.netWorth == 170, "net worth")
expect(data.snapshots.first?.completed == true, "completion")
expect(data.monthlyReminder.lastCompletedMonth == snapshot.month, "completion history")

let next = WorthSnapEngine.createSnapshot(month: "2099-01", in: &data)
expect(data.entries.contains { $0.snapshotId == next.id && $0.confirmed == false }, "new snapshot unconfirmed")
expect(WorthSnapExporter.summaryCSV(data: data).hasPrefix("month,snapshot_date,base_currency,total_assets"), "summary csv header")
expect((try? WorthSnapExporter.json(data: data).isEmpty) == false, "json export")

let config = MonthlyReminderConfig(isEnabled: true, day: .day(25), hour: 20, minute: 0)
let maySchedule = MonthlyReminderScheduler.nextSchedule(config: config, snapshots: [], now: date("2026-05-09T10:00:00Z"), calendar: utcCalendar)
expect(maySchedule?.snapshotMonth == "2026-05", "schedule current month")
expect(maySchedule?.fireDate == date("2026-05-25T20:00:00Z"), "schedule day and time")

let leapConfig = MonthlyReminderConfig(isEnabled: true, day: .lastDay, hour: 20, minute: 30)
let leapSchedule = MonthlyReminderScheduler.nextSchedule(config: leapConfig, snapshots: [], now: date("2028-02-01T10:00:00Z"), calendar: utcCalendar)
expect(leapSchedule?.fireDate == date("2028-02-29T20:30:00Z"), "last day leap year")

let completedSnapshot = Snapshot(ledgerId: UUID(), month: "2026-05", completed: true)
let suppressedSchedule = MonthlyReminderScheduler.nextSchedule(config: config, snapshots: [completedSnapshot], now: date("2026-05-09T10:00:00Z"), calendar: utcCalendar)
expect(suppressedSchedule?.snapshotMonth == "2026-06", "completed current month schedules next month")

let reopenedConfig = MonthlyReminderConfig(isEnabled: true, day: .day(25), hour: 20, minute: 0, lastCompletedMonth: "2026-05")
let reopenedSnapshot = Snapshot(ledgerId: UUID(), month: "2026-05", completed: false)
let reopenedSchedule = MonthlyReminderScheduler.nextSchedule(config: reopenedConfig, snapshots: [reopenedSnapshot], now: date("2026-05-09T10:00:00Z"), calendar: utcCalendar)
expect(reopenedSchedule?.snapshotMonth == "2026-06", "reopened completed month remains suppressed")

let snapshotMigrationJSON = """
{
  "id": "11111111-1111-1111-1111-111111111111",
  "ledgerId": "22222222-2222-2222-2222-222222222222",
  "month": "2026-05",
  "baseCurrency": "CNY",
  "exchangeRates": { "CNY": 1 },
  "exchangeRateSource": "本地缓存",
  "note": "",
  "completed": true,
  "createdAt": "2026-05-26T12:34:56Z",
  "updatedAt": "2026-05-27T12:34:56Z"
}
""".data(using: .utf8)!
let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .iso8601
let migratedSnapshot = try decoder.decode(Snapshot.self, from: snapshotMigrationJSON)
expect(migratedSnapshot.snapshotDate == date("2026-05-26T12:34:56Z"), "migrate snapshotDate from createdAt")

let dataMigrationJSON = """
{
  "ledger": {
    "id": "22222222-2222-2222-2222-222222222222",
    "name": "旺财账本",
    "baseCurrency": "CNY",
    "createdAt": "2026-05-01T00:00:00Z",
    "updatedAt": "2026-05-01T00:00:00Z"
  },
  "accountTypes": [],
  "tags": [],
  "accounts": [],
  "snapshots": [],
  "entries": []
}
""".data(using: .utf8)!
let migratedData = try decoder.decode(WorthSnapData.self, from: dataMigrationJSON)
expect(migratedData.monthlyReminder == MonthlyReminderConfig(), "migrate default reminder config")

let migrationCurrentMonth = WorthSnapEngine.currentMonth()
let migrationPreviousMonth = WorthSnapEngine.previousMonth(migrationCurrentMonth) ?? "2026-04"
let completedCurrentMonthMigrationJSON = """
{
  "ledger": {
    "id": "22222222-2222-2222-2222-222222222222",
    "name": "旺财账本",
    "baseCurrency": "CNY",
    "createdAt": "2026-05-01T00:00:00Z",
    "updatedAt": "2026-05-01T00:00:00Z"
  },
  "accountTypes": [],
  "tags": [],
  "accounts": [],
  "snapshots": [
    {
      "id": "11111111-1111-1111-1111-111111111111",
      "ledgerId": "22222222-2222-2222-2222-222222222222",
      "month": "\(migrationPreviousMonth)",
      "baseCurrency": "CNY",
      "exchangeRates": { "CNY": 1 },
      "exchangeRateSource": "本地缓存",
      "note": "",
      "completed": true,
      "createdAt": "2026-04-26T12:34:56Z",
      "updatedAt": "2026-04-27T12:34:56Z"
    },
    {
      "id": "33333333-3333-3333-3333-333333333333",
      "ledgerId": "22222222-2222-2222-2222-222222222222",
      "month": "\(migrationCurrentMonth)",
      "baseCurrency": "CNY",
      "exchangeRates": { "CNY": 1 },
      "exchangeRateSource": "本地缓存",
      "note": "",
      "completed": true,
      "createdAt": "2026-05-26T12:34:56Z",
      "updatedAt": "2026-05-27T12:34:56Z"
    }
  ],
  "entries": []
}
""".data(using: .utf8)!
let completedCurrentMonthMigratedData = try decoder.decode(WorthSnapData.self, from: completedCurrentMonthMigrationJSON)
expect(completedCurrentMonthMigratedData.monthlyReminder.lastCompletedMonth == migrationCurrentMonth, "migrate completed current month reminder suppression")

let completedHistoricalMonthMigrationJSON = """
{
  "ledger": {
    "id": "22222222-2222-2222-2222-222222222222",
    "name": "旺财账本",
    "baseCurrency": "CNY",
    "createdAt": "2026-05-01T00:00:00Z",
    "updatedAt": "2026-05-01T00:00:00Z"
  },
  "accountTypes": [],
  "tags": [],
  "accounts": [],
  "snapshots": [
    {
      "id": "11111111-1111-1111-1111-111111111111",
      "ledgerId": "22222222-2222-2222-2222-222222222222",
      "month": "\(migrationPreviousMonth)",
      "baseCurrency": "CNY",
      "exchangeRates": { "CNY": 1 },
      "exchangeRateSource": "本地缓存",
      "note": "",
      "completed": true,
      "createdAt": "2026-04-26T12:34:56Z",
      "updatedAt": "2026-04-27T12:34:56Z"
    }
  ],
  "entries": []
}
""".data(using: .utf8)!
let completedHistoricalMonthMigratedData = try decoder.decode(WorthSnapData.self, from: completedHistoricalMonthMigrationJSON)
expect(completedHistoricalMonthMigratedData.monthlyReminder.lastCompletedMonth == nil, "migrate does not suppress historical months")

print("WorthSnapSharedChecks passed")
