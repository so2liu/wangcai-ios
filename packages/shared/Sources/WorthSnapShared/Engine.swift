import Foundation

public enum WorthSnapEngine {
    public static let assetTypeNames = ["银行存款", "现金", "股票/证券", "基金", "互联网钱包", "公积金/养老金", "其他资产"]
    public static let liabilityTypeNames = ["信用卡", "房贷", "消费贷", "其他负债"]

    public static func seededData(now: Date = Date()) -> WorthSnapData {
        let ledger = Ledger(createdAt: now, updatedAt: now)
        let types = assetTypeNames.map { AccountType(name: $0, direction: .asset, isSystem: true) }
            + liabilityTypeNames.map { AccountType(name: $0, direction: .liability, isSystem: true) }
        var data = WorthSnapData(ledger: ledger, accountTypes: types)
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

    public static func currentMonth(date: Date = Date(), calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", comps.year ?? 2026, comps.month ?? 1)
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
