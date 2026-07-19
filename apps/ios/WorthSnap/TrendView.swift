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
            ScrollView {
                VStack(alignment: .leading, spacing: WCSpacing.section) {
                if trendPoints.count > 1 {
                    VStack(alignment: .leading, spacing: 12) {
                            WCSectionHeader("净资产趋势", detail: LocalizedStringKey("\(trendPoints.count) 个月"))
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
                            .frame(height: 180)
                    }
                    .wcCard()
                }
                VStack(alignment: .leading, spacing: 10) {
                    WCSectionHeader("月度记录", detail: "长按可删除")
                    VStack(spacing: 0) {
                        ForEach(Array(store.sortedSnapshots.enumerated()), id: \.element.id) { index, snapshot in
                            snapshotRow(snapshot)
                                .padding(16)
                                .contextMenu {
                                    Button("删除这个月", role: .destructive) { pendingDelete = snapshot }
                                }
                            if index < store.sortedSnapshots.count - 1 {
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                    .wcCard(padding: 0)
                }
                }
                .padding(WCSpacing.page)
            }
            .background(WCTheme.background.ignoresSafeArea())
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

    private func snapshotRow(_ snapshot: Snapshot) -> some View {
        let totals = WorthSnapEngine.totals(for: snapshot, in: store.data)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(AppFormatters.monthTitle(snapshot.month))
                    .font(WCTypography.headline)
                    .foregroundStyle(WCTheme.ink)
                Spacer()
                Text(AppFormatters.symbolized(totals.netWorth, currency: snapshot.baseCurrency))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(WCTheme.ink)
            }
            HStack(spacing: 16) {
                Text("资产 \(AppFormatters.symbolized(totals.totalAssets, currency: snapshot.baseCurrency))")
                Text("负债 \(AppFormatters.symbolized(totals.totalLiabilities, currency: snapshot.baseCurrency))")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(WCTheme.inkSecondary)
        }
    }

}
