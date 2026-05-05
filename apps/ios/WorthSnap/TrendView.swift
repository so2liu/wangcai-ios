import SwiftUI
import WorthSnapShared

struct TrendView: View {
    @EnvironmentObject private var store: AppStore
    @State private var direction: Direction?

    var body: some View {
        NavigationStack {
            List {
                Section("趋势") {
                    ForEach(store.data.snapshots.sorted(by: { $0.month > $1.month })) { snapshot in
                        let totals = WorthSnapEngine.totals(for: snapshot, in: store.data)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(snapshot.month)
                                    .font(.headline)
                                Spacer()
                                Text(AppFormatters.money(totals.netWorth, currency: snapshot.baseCurrency))
                            }
                            HStack {
                                Label(AppFormatters.money(totals.totalAssets), systemImage: "arrow.up.right")
                                    .foregroundStyle(.green)
                                Spacer()
                                Label(AppFormatters.money(totals.totalLiabilities), systemImage: "arrow.down.right")
                                    .foregroundStyle(.red)
                            }
                            .font(.caption)
                        }
                    }
                }
                Section("类型占比") {
                    ForEach(typeTotals(), id: \.0) { name, amount in
                        HStack {
                            Text(name)
                            Spacer()
                            Text(AppFormatters.money(amount))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("趋势")
        }
    }

    private func typeTotals() -> [(String, Decimal)] {
        var result: [String: Decimal] = [:]
        for snapshot in store.data.snapshots {
            for entry in store.entries(for: snapshot) {
                guard let account = store.account(id: entry.accountId) else { continue }
                result[store.typeName(id: account.typeId), default: 0] += entry.convertedAmount
            }
        }
        return result.sorted { $0.value > $1.value }
    }
}
