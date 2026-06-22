import Foundation

public enum WorthSnapEngine {
    public static let assetTypeNames = ["银行存款", "现金", "股票/证券", "基金", "互联网钱包", "公积金/养老金", "其他资产"]
    public static let liabilityTypeNames = ["信用卡", "房贷", "消费贷", "其他负债"]

    /// 全新安装时默认的本机成员名。加入家庭后可改名。
    public static let defaultMemberName = "我"

    public static func seededData(now: Date = Date()) -> WorthSnapData {
        let ledger = Ledger(createdAt: now, updatedAt: now)
        let me = Member(name: defaultMemberName, createdAt: now, updatedAt: now)
        let types = assetTypeNames.map { AccountType(name: $0, direction: .asset, isSystem: true) }
            + liabilityTypeNames.map { AccountType(name: $0, direction: .liability, isSystem: true) }
        var data = WorthSnapData(ledger: ledger, members: [me], currentMemberId: me.id, accountTypes: types)
        createSnapshot(month: currentMonth(), in: &data)
        return data
    }

    public static func sampleData(now: Date = Date()) -> WorthSnapData {
        var data = seededData(now: now)
        let bank = data.accountTypes.first { $0.name == "银行存款" }!
        let wallet = data.accountTypes.first { $0.name == "互联网钱包" }!
        let card = data.accountTypes.first { $0.name == "信用卡" }!
        [
            Account(ledgerId: data.ledger.id, name: "测试资产账户", direction: .asset, typeId: bank.id, sortOrder: 0, createdAt: now, updatedAt: now),
            Account(ledgerId: data.ledger.id, name: "测试钱包账户", direction: .asset, typeId: wallet.id, sortOrder: 1, createdAt: now, updatedAt: now),
            Account(ledgerId: data.ledger.id, name: "测试负债账户", direction: .liability, typeId: card.id, sortOrder: 2, createdAt: now, updatedAt: now)
        ].forEach { addAccount($0, to: &data) }
        return data
    }

    /// 一份丰满的演示数据：多账户、近 6 个月递增的净资产（整体 +15.3%），当前月部分确认。
    /// 用于截图、onboarding 预览与设计对比；不用于真实用户首屏。
    public static func demoData(now: Date = Date()) -> WorthSnapData {
        var data = seededData(now: now)
        // 演示「夫妻两人」：本机成员（我）+ 伴侣。
        let me = data.currentMemberId
        let partner = Member(name: "TA", colorHex: "E08F6B", createdAt: now, updatedAt: now)
        data.members.append(partner)
        func type(_ name: String) -> AccountType { data.accountTypes.first { $0.name == name }! }

        // ownerMemberId 为 nil 表示共同财产。
        let specs: [(name: String, type: String, owner: UUID?)] = [
            ("工资卡", "银行存款", me),
            ("家庭基金", "基金", nil),
            ("股票账户", "股票/证券", me),
            ("自住房产", "其他资产", nil),
            ("微信钱包", "互联网钱包", partner.id),
            ("信用卡", "信用卡", partner.id),
            ("房贷", "房贷", nil)
        ]
        for (index, spec) in specs.enumerated() {
            let accountType = type(spec.type)
            addAccount(
                Account(ledgerId: data.ledger.id, name: spec.name, direction: accountType.direction,
                        typeId: accountType.id, ownerMemberId: spec.owner, responsibleMemberId: spec.owner,
                        sortOrder: index, createdAt: now, updatedAt: now),
                to: &data
            )
        }

        // 末月目标值（元）：资产合计 352.8 万 / 负债 66.4 万 / 净 286.4 万。
        let target: [String: Decimal] = [
            "工资卡": 450_000, "家庭基金": 910_000, "股票账户": 900_000,
            "自住房产": 1_200_000, "微信钱包": 68_000,
            "信用卡": 28_000, "房贷": 636_000
        ]
        // 6 个月缩放系数（首 0.867 → 末 1.0，整体增长约 15.3%）。
        let factor: [Decimal] = [0.867, 0.89, 0.92, 0.95, 0.975, 1.0]

        var monthsAsc: [String] = []
        var cursor = currentMonth(date: now)
        for _ in 0..<6 { monthsAsc.append(cursor); cursor = previousMonth(cursor) ?? cursor }
        monthsAsc.reverse()

        let current = currentMonth(date: now)
        let accountsById = Dictionary(uniqueKeysWithValues: data.accounts.map { ($0.id, $0) })
        for (index, month) in monthsAsc.enumerated() {
            let snap = createSnapshot(month: month, in: &data)
            let scale = factor[min(index, factor.count - 1)]
            for entry in data.entries where entry.snapshotId == snap.id {
                guard let account = accountsById[entry.accountId] else { continue }
                let amount = (target[account.name] ?? 0) * scale
                // 历史月全部确认；当前月留 3 个账户待确认，演示「继续盘点」。
                let confirmed = month < current ? true : account.sortOrder < 4
                updateEntry(entryId: entry.id, amount: amount, confirmed: confirmed, in: &data)
            }
        }
        return data
    }

    public static func currentMonth(date: Date = Date(), calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.year, .month], from: date)
        // year/month 对任意 Date 都能取到，?? 仅为可选解包兜底，不是业务默认值。
        return String(format: "%04d-%02d", comps.year ?? 1, comps.month ?? 1)
    }

    public static func previousMonth(_ month: String) -> String? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        formatter.isLenient = false
        guard let date = formatter.date(from: month),
              let previous = formatter.calendar.date(byAdding: .month, value: -1, to: date) else { return nil }
        return formatter.string(from: previous)
    }

    public static func nextMonth(_ month: String) -> String? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        formatter.isLenient = false
        guard let date = formatter.date(from: month),
              let next = formatter.calendar.date(byAdding: .month, value: 1, to: date) else { return nil }
        return formatter.string(from: next)
    }

    public static func isValidMonth(_ month: String) -> Bool {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        formatter.isLenient = false
        guard let date = formatter.date(from: month) else { return false }
        return formatter.string(from: date) == month
    }

    @discardableResult
    public static func createSnapshot(month: String, in data: inout WorthSnapData) -> Snapshot {
        precondition(isValidMonth(month), "Snapshot month must use YYYY-MM format.")
        if let existing = data.snapshots.first(where: { $0.month == month }) {
            return existing
        }
        let previous = previousMonth(month).flatMap { previousMonth in
            data.snapshots.first(where: { $0.month == previousMonth })
        }
        var snapshot = Snapshot(ledgerId: data.ledger.id, month: month, baseCurrency: data.ledger.baseCurrency)
        data.snapshots.append(snapshot)
        let previousEntries = data.entries.filter { $0.snapshotId == previous?.id }
        for account in data.accounts where !account.archived {
            let previousEntry = previousEntries.first { $0.accountId == account.id }
            let amount = previousEntry?.amount ?? 0
            let rate = snapshot.exchangeRates[account.currency] ?? 1
            data.entries.append(SnapshotEntry(snapshotId: snapshot.id, accountId: account.id, amount: amount, currency: account.currency, exchangeRate: rate, confirmed: false))
        }
        updateCompletion(snapshotId: snapshot.id, in: &data)
        snapshot = data.snapshots.first { $0.id == snapshot.id }!
        return snapshot
    }

    public static func addAccount(_ account: Account, to data: inout WorthSnapData) {
        data.accounts.append(account)
        for snapshot in data.snapshots {
            let isCurrentOrFuture = snapshot.month >= currentMonth()
            let rate = snapshot.exchangeRates[account.currency] ?? 1
            data.entries.append(SnapshotEntry(snapshotId: snapshot.id, accountId: account.id, amount: 0, currency: account.currency, exchangeRate: rate, confirmed: !isCurrentOrFuture))
            updateCompletion(snapshotId: snapshot.id, in: &data)
        }
    }

    public static func updateEntry(entryId: UUID, amount: Decimal, confirmed: Bool? = nil, note: String? = nil, in data: inout WorthSnapData) {
        guard let index = data.entries.firstIndex(where: { $0.id == entryId }) else { return }
        data.entries[index].amount = amount
        data.entries[index].convertedAmount = amount * data.entries[index].exchangeRate
        data.entries[index].updatedAt = Date()
        if let confirmed { data.entries[index].confirmed = confirmed }
        if let note { data.entries[index].note = note }
        updateCompletion(snapshotId: data.entries[index].snapshotId, in: &data)
    }

    public static func setExchangeRate(month: String, currency: String, rate: Decimal, in data: inout WorthSnapData) {
        guard let snapshotIndex = data.snapshots.firstIndex(where: { $0.month == month }) else { return }
        let snapshotId = data.snapshots[snapshotIndex].id
        data.snapshots[snapshotIndex].exchangeRates[currency] = rate
        data.snapshots[snapshotIndex].exchangeRateSource = "手动覆盖"
        for index in data.entries.indices where data.entries[index].snapshotId == snapshotId && data.entries[index].currency == currency {
            data.entries[index].exchangeRate = rate
            data.entries[index].convertedAmount = data.entries[index].amount * rate
        }
    }

    public static func updateCompletion(snapshotId: UUID, in data: inout WorthSnapData) {
        guard let snapshotIndex = data.snapshots.firstIndex(where: { $0.id == snapshotId }) else { return }
        let activeAccountIds = Set(data.accounts.filter { !$0.archived }.map(\.id))
        let related = data.entries.filter { $0.snapshotId == snapshotId && activeAccountIds.contains($0.accountId) }
        data.snapshots[snapshotIndex].completed = !related.isEmpty && related.allSatisfy(\.confirmed)
        data.snapshots[snapshotIndex].updatedAt = Date()
    }

    public static func totals(for snapshot: Snapshot, in data: WorthSnapData) -> SnapshotTotals {
        let accountsById = Dictionary(uniqueKeysWithValues: data.accounts.map { ($0.id, $0) })
        let entries = data.entries.filter { $0.snapshotId == snapshot.id }
        var assets: Decimal = 0
        var liabilities: Decimal = 0
        for entry in entries {
            guard let account = accountsById[entry.accountId] else { continue }
            switch account.direction {
            case .asset: assets += entry.convertedAmount
            case .liability: liabilities += entry.convertedAmount
            }
        }
        return SnapshotTotals(totalAssets: assets, totalLiabilities: liabilities, netWorth: assets - liabilities)
    }

    /// 按「我的 / TA的 / 共同」三栏聚合某月的资产负债净值。
    /// 视角由 `data.currentMemberId` 决定：家庭净资产 = 三栏净值之和。
    public static func totals(by view: OwnershipView, for snapshot: Snapshot, in data: WorthSnapData) -> SnapshotTotals {
        let accountsById = Dictionary(uniqueKeysWithValues: data.accounts.map { ($0.id, $0) })
        var assets: Decimal = 0
        var liabilities: Decimal = 0
        for entry in data.entries where entry.snapshotId == snapshot.id {
            guard let account = accountsById[entry.accountId], data.ownershipView(of: account) == view else { continue }
            switch account.direction {
            case .asset: assets += entry.convertedAmount
            case .liability: liabilities += entry.convertedAmount
            }
        }
        return SnapshotTotals(totalAssets: assets, totalLiabilities: liabilities, netWorth: assets - liabilities)
    }

    // MARK: - 成员

    public static func addMember(name: String, colorHex: String = "C8A24B", icloudUserRecordID: String? = nil, in data: inout WorthSnapData) -> Member {
        let member = Member(name: name, icloudUserRecordID: icloudUserRecordID, colorHex: colorHex)
        data.members.append(member)
        return member
    }

    /// 成员离开：人走数据留。归档成员，其归属/负责的账户**不删除**；
    /// 负责的账户转交给 `reassignResponsibleTo`（nil 则置为未指定，回退给归属成员）。
    public static func archiveMember(_ memberId: UUID, reassignResponsibleTo newOwner: UUID? = nil, in data: inout WorthSnapData) {
        guard let index = data.members.firstIndex(where: { $0.id == memberId }) else { return }
        data.members[index].archived = true
        data.members[index].updatedAt = Date()
        for accountIndex in data.accounts.indices where data.accounts[accountIndex].responsibleMemberId == memberId {
            data.accounts[accountIndex].responsibleMemberId = newOwner
            data.accounts[accountIndex].updatedAt = Date()
        }
    }

    /// 某月相对上一月的环比对比（总资产 / 总负债 / 净资产）。无上一月时 ratio 为 nil。
    public static func comparison(for snapshot: Snapshot, in data: WorthSnapData) -> TotalsComparison {
        let current = totals(for: snapshot, in: data)
        let previous = previousMonth(snapshot.month)
            .flatMap { month in data.snapshots.first { $0.month == month } }
            .map { totals(for: $0, in: data) }
        return TotalsComparison(
            current: current,
            previous: previous,
            assetsRatio: ratio(current.totalAssets, previous?.totalAssets),
            liabilitiesRatio: ratio(current.totalLiabilities, previous?.totalLiabilities),
            netWorthRatio: ratio(current.netWorth, previous?.netWorth)
        )
    }

    /// 最近 `months` 个有效月份的净资产序列（按月份升序）。
    public static func netWorthTrend(months: Int = 6, endingAt month: String? = nil, in data: WorthSnapData) -> [Decimal] {
        let valid = data.snapshots
            .filter { isValidMonth($0.month) }
            .sorted { $0.month < $1.month }
        let scoped = month.map { upper in valid.filter { $0.month <= upper } } ?? valid
        return scoped.suffix(months).map { totals(for: $0, in: data).netWorth }
    }

    /// 趋势区间内净资产的整体变化比例（首月 → 末月），对应设计稿的 `+15.3%`。
    public static func netWorthTrendChange(months: Int = 6, endingAt month: String? = nil, in data: WorthSnapData) -> Double? {
        let series = netWorthTrend(months: months, endingAt: month, in: data)
        guard series.count > 1, let first = series.first, let last = series.last else { return nil }
        return ratio(last, first)
    }

    /// 环比比例 = (现在 - 之前) / |之前|。用绝对值做分母，避免净资产为负时符号翻转。
    private static func ratio(_ now: Decimal, _ before: Decimal?) -> Double? {
        guard let before, before != 0 else { return nil }
        let delta = (now - before as NSDecimalNumber).doubleValue
        let base = abs((before as NSDecimalNumber).doubleValue)
        guard base != 0 else { return nil }
        return delta / base
    }
}

public struct TotalsComparison: Equatable, Sendable {
    public var current: SnapshotTotals
    public var previous: SnapshotTotals?
    public var assetsRatio: Double?
    public var liabilitiesRatio: Double?
    public var netWorthRatio: Double?
}

public struct SnapshotTotals: Equatable, Sendable {
    public var totalAssets: Decimal
    public var totalLiabilities: Decimal
    public var netWorth: Decimal
}

public enum AmountParser {
    public static func parse(_ raw: String) -> Decimal? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "")
        guard !text.isEmpty else { return nil }
        let multiplier: Decimal = text.hasSuffix("万") ? 10_000 : 1
        let numberText = text.hasSuffix("万") ? String(text.dropLast()) : text
        guard let value = Decimal(string: numberText), value >= 0 else { return nil }
        return value * multiplier
    }
}
