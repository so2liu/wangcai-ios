import SwiftUI
import WorthSnapShared

struct OverviewView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        NavigationStack {
            let snapshot = store.snapshot()
            let totals = WorthSnapEngine.totals(for: snapshot, in: store.data)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(snapshot.month)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(AppFormatters.money(totals.netWorth, currency: snapshot.baseCurrency))
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                        Text("净资产")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                    HStack {
                        MetricTile(title: "总资产", value: AppFormatters.money(totals.totalAssets, currency: snapshot.baseCurrency), color: .green)
                        MetricTile(title: "总负债", value: AppFormatters.money(totals.totalLiabilities, currency: snapshot.baseCurrency), color: .red)
                    }

                    let entries = store.entries(for: snapshot)
                    let confirmed = entries.filter(\.confirmed).count
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("本月完成度")
                                .font(.headline)
                            Spacer()
                            Text("\(confirmed)/\(entries.count)")
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: entries.isEmpty ? 0 : Double(confirmed) / Double(entries.count))
                        if store.data.accounts.filter({ !$0.archived }).isEmpty {
                            NavigationLink(destination: AccountsView()) {
                                Label("添加第一个账户", systemImage: "plus.circle.fill")
                                    .frame(maxWidth: .infinity)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                            }
                            .buttonStyle(.borderedProminent)
                        } else if !snapshot.completed {
                            NavigationLink(destination: SnapshotView()) {
                                Label("继续盘点", systemImage: "arrow.right.circle.fill")
                                    .frame(maxWidth: .infinity)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding()
                    .background(.background, in: RoundedRectangle(cornerRadius: 8))
                    .shadow(color: .black.opacity(0.06), radius: 8, y: 2)

                    TrendStrip()
                    StructureList(snapshot: snapshot)
                }
                .padding()
            }
            .navigationTitle("月余")
            .toolbar {
                NavigationLink(destination: SettingsView()) {
                    Image(systemName: "gearshape")
                }
            }
        }
    }
}

private struct MetricTile: View {
    var title: String
    var value: String
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct TrendStrip: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近净资产")
                .font(.headline)
            let points = store.data.snapshots.sorted { $0.month < $1.month }.suffix(6).map { WorthSnapEngine.totals(for: $0, in: store.data).netWorth }
            GeometryReader { proxy in
                Path { path in
                    guard points.count > 1 else { return }
                    let doubles = points.map { NSDecimalNumber(decimal: $0).doubleValue }
                    let minValue = doubles.min() ?? 0
                    let maxValue = doubles.max() ?? 1
                    for index in doubles.indices {
                        let x = proxy.size.width * CGFloat(index) / CGFloat(max(doubles.count - 1, 1))
                        let ratio = (doubles[index] - minValue) / max(maxValue - minValue, 1)
                        let y = proxy.size.height - proxy.size.height * CGFloat(ratio)
                        if index == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(.teal, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
            .frame(height: 120)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }
}

private struct StructureList: View {
    @EnvironmentObject private var store: AppStore
    var snapshot: Snapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("结构概览")
                .font(.headline)
            ForEach(grouped(), id: \.0) { name, amount in
                HStack {
                    Text(name)
                    Spacer()
                    Text(AppFormatters.money(amount, currency: snapshot.baseCurrency))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }

    private func grouped() -> [(String, Decimal)] {
        var totals: [String: Decimal] = [:]
        for entry in store.entries(for: snapshot) {
            guard let account = store.account(id: entry.accountId) else { continue }
            totals[store.typeName(id: account.typeId), default: 0] += entry.convertedAmount
        }
        return totals.sorted { $0.value > $1.value }
    }
}
