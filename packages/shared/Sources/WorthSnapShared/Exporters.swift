import Foundation

public enum WorthSnapExporter {
    public static func json(data: WorthSnapData) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(data)
    }

    public static func summaryCSV(data: WorthSnapData) -> String {
        var rows = ["month,base_currency,total_assets,total_liabilities,net_worth,asset_change_amount,asset_change_percent,net_worth_change_amount,net_worth_change_percent,completed,note,updated_at"]
        let snapshots = data.snapshots.sorted(by: { $0.month < $1.month })
        for (index, snapshot) in snapshots.enumerated() {
            let totals = WorthSnapEngine.totals(for: snapshot, in: data)
            let previousTotals = index > 0 ? WorthSnapEngine.totals(for: snapshots[index - 1], in: data) : nil
            let assetChange = previousTotals.map { totals.totalAssets - $0.totalAssets } ?? 0
            let netWorthChange = previousTotals.map { totals.netWorth - $0.netWorth } ?? 0
            let assetPercent = previousTotals.flatMap { percent(change: assetChange, previous: $0.totalAssets) } ?? 0
            let netWorthPercent = previousTotals.flatMap { percent(change: netWorthChange, previous: $0.netWorth) } ?? 0
            rows.append([
                snapshot.month,
                snapshot.baseCurrency,
                totals.totalAssets.description,
                totals.totalLiabilities.description,
                totals.netWorth.description,
                assetChange.description,
                assetPercent.description,
                netWorthChange.description,
                netWorthPercent.description,
                snapshot.completed ? "true" : "false",
                escape(snapshot.note),
                ISO8601DateFormatter().string(from: snapshot.updatedAt)
            ].joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    public static func entriesCSV(data: WorthSnapData) -> String {
        let accountsById = Dictionary(uniqueKeysWithValues: data.accounts.map { ($0.id, $0) })
        let typesById = Dictionary(uniqueKeysWithValues: data.accountTypes.map { ($0.id, $0) })
        let tagsById = Dictionary(uniqueKeysWithValues: data.tags.map { ($0.id, $0) })
        let snapshotsById = Dictionary(uniqueKeysWithValues: data.snapshots.map { ($0.id, $0) })
        let membersById = Dictionary(uniqueKeysWithValues: data.members.map { ($0.id, $0) })
        func ownerLabel(_ id: UUID?) -> String { id.flatMap { membersById[$0]?.name } ?? "共同" }
        func responsibleLabel(_ id: UUID?) -> String { id.flatMap { membersById[$0]?.name } ?? "" }
        var rows = ["month,account_name,direction,type,owner,responsible,tags,currency,amount,exchange_rate,base_currency,converted_amount,confirmed,note,updated_at"]
        for entry in data.entries {
            guard let account = accountsById[entry.accountId], let snapshot = snapshotsById[entry.snapshotId] else { continue }
            let tagNames = account.tagIds.compactMap { tagsById[$0]?.name }.joined(separator: "|")
            rows.append([
                snapshot.month,
                escape(entry.accountName),
                entry.accountDirection.rawValue,
                escape(typesById[entry.accountTypeId]?.name ?? ""),
                escape(ownerLabel(entry.accountOwnerMemberId)),
                escape(responsibleLabel(account.responsibleMemberId)),
                escape(tagNames),
                entry.currency,
                entry.amount.description,
                entry.exchangeRate.description,
                snapshot.baseCurrency,
                entry.convertedAmount.description,
                entry.confirmed ? "true" : "false",
                escape(entry.note),
                ISO8601DateFormatter().string(from: entry.updatedAt)
            ].joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    public static func accountsCSV(data: WorthSnapData) -> String {
        let typesById = Dictionary(uniqueKeysWithValues: data.accountTypes.map { ($0.id, $0) })
        let tagsById = Dictionary(uniqueKeysWithValues: data.tags.map { ($0.id, $0) })
        let membersById = Dictionary(uniqueKeysWithValues: data.members.map { ($0.id, $0) })
        func ownerLabel(_ id: UUID?) -> String { id.flatMap { membersById[$0]?.name } ?? "共同" }
        func responsibleLabel(_ id: UUID?) -> String { id.flatMap { membersById[$0]?.name } ?? "" }
        var rows = ["account_name,direction,type,currency,owner,responsible,tags,sort_order,archived,created_at,updated_at"]
        for account in data.accounts.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            let tagNames = account.tagIds.compactMap { tagsById[$0]?.name }.joined(separator: "|")
            rows.append([
                escape(account.name),
                account.direction.rawValue,
                escape(typesById[account.typeId]?.name ?? ""),
                account.currency,
                escape(ownerLabel(account.ownerMemberId)),
                escape(responsibleLabel(account.responsibleMemberId)),
                escape(tagNames),
                String(account.sortOrder),
                account.archived ? "true" : "false",
                ISO8601DateFormatter().string(from: account.createdAt),
                ISO8601DateFormatter().string(from: account.updatedAt)
            ].joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    private static func escape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    private static func percent(change: Decimal, previous: Decimal) -> Decimal? {
        guard previous != 0 else { return nil }
        return change / previous
    }
}
