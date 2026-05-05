import Foundation
import WorthSnapShared

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("Check failed: \(message)\n", stderr)
        exit(1)
    }
}

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

let next = WorthSnapEngine.createSnapshot(month: "2099-01", in: &data)
expect(data.entries.contains { $0.snapshotId == next.id && $0.confirmed == false }, "new snapshot unconfirmed")
expect(WorthSnapExporter.summaryCSV(data: data).hasPrefix("month,base_currency,total_assets"), "summary csv header")
expect((try? WorthSnapExporter.json(data: data).isEmpty) == false, "json export")

print("WorthSnapSharedChecks passed")
