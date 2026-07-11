import SwiftUI
import Charts
import WorthSnapShared

struct OverviewView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        NavigationStack {
            if let snapshot = store.selectedSnapshot {
                overview(snapshot)
            } else {
                ProgressView("正在准备本月快照…")
                    .task { store.ensureSelectedSnapshot() }
            }
        }
    }

    private func overview(_ snapshot: Snapshot) -> some View {
        let totals = WorthSnapEngine.totals(for: snapshot, in: store.data)
        let comparison = WorthSnapEngine.comparison(for: snapshot, in: store.data)
        let entries = store.entries(for: snapshot)
        let confirmed = entries.filter(\.confirmed).count
        let hasAccounts = store.data.accounts.contains { !$0.archived }
        return ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(snapshot: snapshot)
                    NetWorthCard(totals: totals, snapshot: snapshot, ratio: comparison.netWorthRatio)

                    HStack(spacing: 12) {
                        MetricTile(title: "总资产", dot: WCTheme.up, value: totals.totalAssets,
                                   currency: snapshot.baseCurrency, ratio: comparison.assetsRatio)
                        MetricTile(title: "总负债", dot: WCTheme.down, value: totals.totalLiabilities,
                                   currency: snapshot.baseCurrency, ratio: comparison.liabilitiesRatio, invertSentiment: true)
                    }

                    if hasAccounts {
                        if showsOwnershipBreakdown {
                            OwnershipBreakdownCard(snapshot: snapshot)
                        }
                        InventoryCard(snapshot: snapshot, confirmed: confirmed, total: entries.count, hasAccounts: hasAccounts)
                        TrendCard(snapshot: snapshot)
                        StructureCard(snapshot: snapshot, totalAssets: totals.totalAssets)
                    } else {
                        EmptyStateCard()
                    }
                }
                .padding(16)
            }
            .background(WCTheme.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
    }

    /// 仅当账本不是「纯本人单机」时才显示三栏：存在其他成员，或有账户归属他人/共同。
    private var showsOwnershipBreakdown: Bool {
        if store.activeMembers.count > 1 { return true }
        return store.data.accounts.contains { !$0.archived && $0.ownerMemberId != store.data.currentMemberId }
    }

    private func header(snapshot: Snapshot) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("旺财")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(WCTheme.goldDeep)
                Text("\(AppFormatters.monthTitle(snapshot.month)) · \(snapshot.completed ? "已完成" : "盘点中")")
                    .font(.subheadline)
                    .foregroundStyle(WCTheme.inkTertiary)
            }
            Spacer()
            NavigationLink(destination: SettingsView()) {
                // 诚实标注为「设置」入口：iCloud 同步尚未实现，不能用带锁的 iCloud
                // 标签暗示数据已上云，那会误导用户对数据安全的判断。
                Label("设置", systemImage: "gearshape")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WCTheme.goldText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.7), in: Capsule())
                    .overlay(Capsule().strokeBorder(WCTheme.gold.opacity(0.25), lineWidth: 0.5))
            }
        }
        .padding(.top, 8)
    }
}

// MARK: - 净资产卡

private struct NetWorthCard: View {
    var totals: SnapshotTotals
    var snapshot: Snapshot
    var ratio: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("净资产")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WCTheme.inkTertiary)
                Spacer()
                Text("本位币 \(snapshot.baseCurrency)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WCTheme.goldText)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(WCTheme.gold.opacity(0.14), in: Capsule())
            }
            Text(AppFormatters.symbolized(totals.netWorth, currency: snapshot.baseCurrency))
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .foregroundStyle(WCTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let ratio {
                Text("\(AppFormatters.signedPercent(ratio)) 较上月")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppFormatters.changeColor(ratio))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .wcCard(fill: WCTheme.netCard)
    }
}

// MARK: - 归属三栏（我的 / TA的 / 共同）

private struct OwnershipBreakdownCard: View {
    @EnvironmentObject private var store: AppStore
    var snapshot: Snapshot

    private var rows: [(view: OwnershipView, net: Decimal)] {
        OwnershipView.allCases.map { view in
            (view, WorthSnapEngine.totals(by: view, for: snapshot, in: store.data).netWorth)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("按归属").font(.headline).foregroundStyle(WCTheme.ink)
            ForEach(rows, id: \.view) { row in
                HStack {
                    Text(row.view.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(WCTheme.inkSecondary)
                    Spacer()
                    Text(AppFormatters.symbolized(row.net, currency: snapshot.baseCurrency))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WCTheme.ink)
                        .monospacedDigit()
                }
            }
            Text("家庭净资产 = 三栏之和")
                .font(.caption)
                .foregroundStyle(WCTheme.inkFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .wcCard()
    }
}

// MARK: - 总资产 / 总负债

private struct MetricTile: View {
    var title: String
    var dot: Color
    var value: Decimal
    var currency: String
    var ratio: Double?
    var invertSentiment: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(dot).frame(width: 7, height: 7)
                Text(title).font(.subheadline).foregroundStyle(WCTheme.inkSecondary)
            }
            Text(AppFormatters.symbolized(value, currency: currency))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(WCTheme.ink)
                .lineLimit(1).minimumScaleFactor(0.6)
            if let ratio {
                Text(AppFormatters.signedPercent(ratio))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppFormatters.changeColor(ratio, inverted: invertSentiment))
            } else {
                Text("—").font(.caption).foregroundStyle(WCTheme.inkFaint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .wcCard(fill: WCTheme.creamCard)
    }
}

// MARK: - 新用户空状态引导

private struct EmptyStateCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(WCTheme.goldDeep)
            Text("开始记录家庭净资产")
                .font(.headline)
                .foregroundStyle(WCTheme.ink)
            Text("添加银行、基金、房产等账户，每月花一分钟更新余额，趋势会自己长出来。")
                .font(.subheadline)
                .foregroundStyle(WCTheme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            NavigationLink(destination: AccountsView()) {
                Text("添加第一个账户")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(WCTheme.goldFill, in: Capsule())
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .wcCard(fill: WCTheme.netCard)
    }
}

// MARK: - 本月盘点

private struct InventoryCard: View {
    var snapshot: Snapshot
    var confirmed: Int
    var total: Int
    var hasAccounts: Bool

    private var progress: Double { total == 0 ? 0 : Double(confirmed) / Double(total) }
    private var remaining: Int { max(total - confirmed, 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("本月盘点").font(.headline).foregroundStyle(WCTheme.ink)
                Spacer()
                Text("\(confirmed) / \(total) 已确认")
                    .font(.subheadline).foregroundStyle(WCTheme.inkTertiary)
                    .monospacedDigit()
            }
            WCProgressBar(value: progress)
            HStack {
                if !hasAccounts {
                    NavigationLink(destination: AccountsView()) {
                        Text("先添加第一个账户 →").font(.subheadline.weight(.bold)).foregroundStyle(WCTheme.goldDeep)
                    }
                } else {
                    Text(remaining > 0 ? "还有 \(remaining) 个账户待确认" : "本月已全部确认")
                        .font(.subheadline).foregroundStyle(WCTheme.inkTertiary)
                    Spacer()
                    if remaining > 0 {
                        NavigationLink(destination: SnapshotView()) {
                            Text("继续盘点 →").font(.subheadline.weight(.bold)).foregroundStyle(WCTheme.goldDeep)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .wcCard()
    }
}

// MARK: - 近 6 个月净资产

private struct TrendCard: View {
    @EnvironmentObject private var store: AppStore
    var snapshot: Snapshot

    private var points: [(month: String, value: Double)] {
        store.data.snapshots
            .filter { WorthSnapEngine.isValidMonth($0.month) && $0.month <= snapshot.month }
            .sorted { $0.month < $1.month }
            .suffix(6)
            .map { ($0.month, NSDecimalNumber(decimal: WorthSnapEngine.totals(for: $0, in: store.data).netWorth).doubleValue) }
    }

    var body: some View {
        let data = points
        let change = WorthSnapEngine.netWorthTrendChange(endingAt: snapshot.month, in: store.data)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("近 6 个月净资产").font(.headline).foregroundStyle(WCTheme.ink)
                Spacer()
                if let change {
                    Text(AppFormatters.signedPercent(change))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppFormatters.changeColor(change))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(AppFormatters.changeColor(change).opacity(0.12), in: Capsule())
                }
            }
            if data.count > 1 {
                Chart {
                    ForEach(Array(data.enumerated()), id: \.offset) { index, point in
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
                    AxisMarks(values: Array(data.indices)) { value in
                        if let index = value.as(Int.self), index < data.count {
                            AxisValueLabel { Text(AppFormatters.shortMonth(data[index].month)).font(.caption2).foregroundStyle(WCTheme.inkFaint) }
                        }
                    }
                }
                .chartYAxis(.hidden)
                .frame(height: 130)
            } else {
                Text("再记录一个月，趋势就出现了。")
                    .font(.subheadline).foregroundStyle(WCTheme.inkTertiary)
                    .frame(height: 130, alignment: .center)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .wcCard()
    }
}

// MARK: - 资产结构

private struct StructureCard: View {
    @EnvironmentObject private var store: AppStore
    var snapshot: Snapshot
    var totalAssets: Decimal

    private func grouped() -> [(name: String, amount: Decimal)] {
        var totals: [String: Decimal] = [:]
        for entry in store.entries(for: snapshot) {
            guard entry.accountDirection == .asset else { continue }
            totals[store.typeName(id: entry.accountTypeId), default: 0] += entry.convertedAmount
        }
        return totals.filter { $0.value > 0 }.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    var body: some View {
        let rows = grouped()
        VStack(alignment: .leading, spacing: 14) {
            Text("资产结构").font(.headline).foregroundStyle(WCTheme.ink)
            if rows.isEmpty {
                Text("确认账户金额后，这里会显示资产构成。")
                    .font(.subheadline).foregroundStyle(WCTheme.inkTertiary)
            } else {
                ForEach(rows, id: \.name) { row in
                    let fraction = totalAssets > 0 ? NSDecimalNumber(decimal: row.amount / totalAssets).doubleValue : 0
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(row.name).font(.subheadline.weight(.medium)).foregroundStyle(WCTheme.inkSecondary)
                            Spacer()
                            Text("\(AppFormatters.symbolized(row.amount, currency: snapshot.baseCurrency)) · \(Int((fraction * 100).rounded()))%")
                                .font(.caption).foregroundStyle(WCTheme.inkTertiary)
                        }
                        WCProgressBar(value: fraction, height: 6)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .wcCard()
    }
}

// MARK: - 进度条

private struct WCProgressBar: View {
    var value: Double
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(WCTheme.gold.opacity(0.15))
                Capsule().fill(WCTheme.goldFill)
                    .frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: height)
    }
}
