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
                VStack(alignment: .leading, spacing: WCSpacing.section) {
                    header(snapshot: snapshot)

                    NetWorthCard(
                        totals: totals,
                        snapshot: snapshot,
                        ratio: snapshot.completed ? comparison.netWorthRatio : nil,
                        unconfirmedCount: max(entries.count - confirmed, 0)
                    )

                    VStack(alignment: .leading, spacing: 12) {
                        WCSectionHeader("资产概览", detail: "较上月")
                        HStack(spacing: 12) {
                            MetricTile(title: "总资产", dot: WCTheme.up, value: totals.totalAssets,
                                       currency: snapshot.baseCurrency, ratio: comparison.assetsRatio)
                            MetricTile(title: "总负债", dot: WCTheme.down, value: totals.totalLiabilities,
                                       currency: snapshot.baseCurrency, ratio: comparison.liabilitiesRatio, invertSentiment: true)
                        }
                    }

                    if hasAccounts {
                        VStack(alignment: .leading, spacing: 12) {
                            WCSectionHeader("本月变化")
                            MonthlyChangeCard(snapshot: snapshot)
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            WCSectionHeader("资产构成", detail: "前三项")
                            StructureCard(snapshot: snapshot, totalAssets: totals.totalAssets)
                        }
                    } else {
                        EmptyStateCard()
                    }
                }
                .padding(.horizontal, WCSpacing.page)
                .padding(.vertical, 14)
            }
            .background(WCTheme.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
    }

    private func header(snapshot: Snapshot) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("我的净资产")
                    .font(WCTypography.title)
                    .foregroundStyle(WCTheme.ink)
                Text("\(AppFormatters.monthTitle(snapshot.month)) · \(snapshot.completed ? "已完成" : "盘点中")")
                    .font(.subheadline)
                    .foregroundStyle(WCTheme.inkTertiary)
            }
            Spacer()
            NavigationLink(destination: SettingsView()) {
                // 诚实标注为「设置」入口：iCloud 同步尚未实现，不能用带锁的 iCloud
                // 标签暗示数据已上云，那会误导用户对数据安全的判断。
                Image(systemName: "gearshape")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(WCTheme.goldText)
                    .frame(width: 40, height: 40)
                    .background(WCTheme.surface, in: Circle())
                    .overlay(Circle().strokeBorder(WCTheme.cardStroke, lineWidth: 1))
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
    var unconfirmedCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("净资产")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WCTheme.inkTertiary)
                Spacer()
                Text(unconfirmedCount > 0 ? "暂估 · \(snapshot.baseCurrency)" : "已确认 · \(snapshot.baseCurrency)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WCTheme.goldText)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(WCTheme.gold.opacity(0.14), in: Capsule())
            }
            Text(AppFormatters.symbolized(totals.netWorth, currency: snapshot.baseCurrency))
                .font(WCTypography.largeNumber)
                .foregroundStyle(WCTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let ratio {
                Text("\(AppFormatters.signedPercent(ratio)) 较上月")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppFormatters.changeColor(ratio))
            } else if unconfirmedCount > 0 {
                NavigationLink(destination: SnapshotView()) {
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                        Text("\(unconfirmedCount) 个账户待确认")
                        Spacer()
                        Text("去确认")
                        Image(systemName: "chevron.right")
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WCTheme.goldText)
                    .padding(.top, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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

// MARK: - 本月变化摘要

private struct MonthlyChangeCard: View {
    @EnvironmentObject private var store: AppStore
    var snapshot: Snapshot

    private var previousSnapshot: Snapshot? {
        guard let month = WorthSnapEngine.previousMonth(snapshot.month) else { return nil }
        return store.data.snapshots.first { $0.month == month }
    }

    var body: some View {
        let current = WorthSnapEngine.totals(for: snapshot, in: store.data).netWorth
        let previous = previousSnapshot.map { WorthSnapEngine.totals(for: $0, in: store.data).netWorth }
        let delta = previous.map { current - $0 }
        let ratio = previous.flatMap { value -> Double? in
            guard value != 0 else { return nil }
            return NSDecimalNumber(decimal: (current - value) / abs(value)).doubleValue
        }
        return HStack(spacing: 12) {
            Image(systemName: delta.map { $0 >= 0 ? "arrow.up.right" : "arrow.down.right" } ?? "minus")
                .font(.headline.weight(.semibold))
                .foregroundStyle(ratio.map { AppFormatters.changeColor($0) } ?? WCTheme.inkTertiary)
                .frame(width: 40, height: 40)
                .background((ratio.map { AppFormatters.changeColor($0) } ?? WCTheme.inkTertiary).opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                if let delta, let ratio {
                    Text("净资产较上月\(delta >= 0 ? "增加" : "减少") \(AppFormatters.symbolized(abs(delta), currency: snapshot.baseCurrency))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WCTheme.ink)
                    Text(AppFormatters.signedPercent(ratio))
                        .font(.caption)
                        .foregroundStyle(AppFormatters.changeColor(ratio))
                } else {
                    Text("完成下个月盘点后即可查看月度变化")
                        .font(.subheadline)
                        .foregroundStyle(WCTheme.inkSecondary)
                }
            }
            Spacer()
            NavigationLink(destination: TrendView()) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WCTheme.inkFaint)
            }
        }
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
        return totals.filter { $0.value > 0 }.sorted { $0.value > $1.value }.prefix(3).map { ($0.key, $0.value) }
    }

    var body: some View {
        let rows = grouped()
        VStack(alignment: .leading, spacing: 14) {
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
