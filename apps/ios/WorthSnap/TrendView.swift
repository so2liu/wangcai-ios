import SwiftUI
import Charts
import WorthSnapShared

struct TrendView: View {
    @EnvironmentObject private var store: AppStore
    @State private var pendingDelete: Snapshot?

    private var trendPoints: [(month: String, value: Double)] {
        store.data.snapshots
            .filter { WorthSnapEngine.isValidMonth($0.month) }
            .sorted { $0.month < $1.month }
            .map { ($0.month, NSDecimalNumber(decimal: WorthSnapEngine.totals(for: $0, in: store.data).netWorth).doubleValue) }
    }

    var body: some View {
        NavigationStack {
            List {
                if trendPoints.count > 1 {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("月度净资产变化").font(.subheadline.weight(.semibold)).foregroundStyle(WCTheme.inkSecondary)
                            Chart {
                                ForEach(Array(trendPoints.enumerated()), id: \.offset) { index, point in
                                    LineMark(x: .value("月", index), y: .value("净资产", point.value))
                                        .interpolationMethod(.catmullRom)
                                        .foregroundStyle(WCTheme.gold)
                                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                                    AreaMark(x: .value("月", index), y: .value("净资产", point.value))
                                        .interpolationMethod(.catmullRom)
                                        .foregroundStyle(LinearGradient(colors: [WCTheme.gold.opacity(0.18), .clear], startPoint: .top, endPoint: .bottom))
                                }
                            }
                            .chartXAxis {
                                AxisMarks(values: Array(trendPoints.indices)) { value in
                                    if let index = value.as(Int.self), index < trendPoints.count {
                                        AxisValueLabel {
                                            Text(AppFormatters.shortMonth(trendPoints[index].month))
                                        }
                                    }
                                }
                            }
                            .chartYAxis {
                                AxisMarks(position: .leading) { value in
                                    AxisGridLine().foregroundStyle(WCTheme.gold.opacity(0.1))
                                    AxisValueLabel {
                                        if let amount = value.as(Double.self) {
                                            Text(AppFormatters.readableAmount(Decimal(amount)))
                                        }
                                    }
                                }
                            }
                            .frame(height: 140)
                        }
                        .padding(.vertical, 4)
                    }
                    .wcRow()
                }
                Section("趋势") {
                    ForEach(store.sortedSnapshots) { snapshot in
                        let totals = WorthSnapEngine.totals(for: snapshot, in: store.data)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(AppFormatters.monthTitle(snapshot.month))
                                    .font(.headline)
                                    .foregroundStyle(WCTheme.ink)
                                if !WorthSnapEngine.isValidMonth(snapshot.month) {
                                    Text("异常")
                                        .font(.caption)
                                        .foregroundStyle(WCTheme.down)
                                }
                                Spacer()
                                Text(AppFormatters.symbolized(totals.netWorth, currency: snapshot.baseCurrency))
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(WCTheme.ink)
                            }
                            HStack {
                                Label(AppFormatters.symbolized(totals.totalAssets, currency: snapshot.baseCurrency), systemImage: "arrow.up.right")
                                    .foregroundStyle(WCTheme.up)
                                Spacer()
                                Label(AppFormatters.symbolized(totals.totalLiabilities, currency: snapshot.baseCurrency), systemImage: "arrow.down.right")
                                    .foregroundStyle(WCTheme.down)
                            }
                            .font(.caption)
                        }
                    }
                    .onDelete { offsets in
                        let snapshots = store.sortedSnapshots
                        pendingDelete = offsets.first.map { snapshots[$0] }
                    }
                }
                .wcRow()
                Section("资产构成") {
                    ForEach(typeTotals(direction: .asset), id: \.0) { name, amount in
                        HStack {
                            Text(name).foregroundStyle(WCTheme.inkSecondary)
                            Spacer()
                            Text(AppFormatters.symbolized(amount, currency: store.data.ledger.baseCurrency))
                                .foregroundStyle(WCTheme.inkTertiary)
                        }
                    }
                }
                .wcRow()
                Section("负债构成") {
                    ForEach(typeTotals(direction: .liability), id: \.0) { name, amount in
                        HStack {
                            Text(name).foregroundStyle(WCTheme.inkSecondary)
                            Spacer()
                            Text(AppFormatters.symbolized(amount, currency: store.data.ledger.baseCurrency))
                                .foregroundStyle(WCTheme.inkTertiary)
                        }
                    }
                }
                .wcRow()
            }
            .wcScreen()
            .tint(WCTheme.goldDeep)
            .navigationTitle("资产变化")
            .alert("删除整月记录？", isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            )) {
                Button("取消", role: .cancel) { pendingDelete = nil }
                Button("确认删除", role: .destructive) {
                    if let pendingDelete { store.deleteSnapshot(pendingDelete) }
                    pendingDelete = nil
                }
            } message: {
                Text("将删除 \(AppFormatters.monthTitle(pendingDelete?.month ?? "")) 及其中全部账户记录。此操作无法撤销。")
            }
        }
    }

    private func typeTotals(direction: Direction) -> [(String, Decimal)] {
        var result: [String: Decimal] = [:]
        guard let latest = store.sortedValidSnapshots.first else { return [] }
        for entry in store.entries(for: latest) where entry.accountDirection == direction {
            result[store.typeName(id: entry.accountTypeId), default: 0] += entry.convertedAmount
        }
        return result.sorted { $0.value > $1.value }
    }
}
