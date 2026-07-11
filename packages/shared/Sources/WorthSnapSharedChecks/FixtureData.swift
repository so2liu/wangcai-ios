import Foundation
import WorthSnapShared

/// 仅编译进命令行检查工具的测试/截图数据。正式 App target 无法访问这些 API。
extension WorthSnapEngine {
    static func sampleData(now: Date = Date()) -> WorthSnapData {
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

    static func demoData(now: Date = Date()) -> WorthSnapData {
        var data = seededData(now: now)
        let me = data.currentMemberId
        let partner = Member(name: "TA", colorHex: "E08F6B", createdAt: now, updatedAt: now)
        data.members.append(partner)
        func type(_ name: String) -> AccountType { data.accountTypes.first { $0.name == name }! }
        let specs: [(String, String, UUID?)] = [
            ("工资卡", "银行存款", me), ("家庭基金", "基金", nil),
            ("股票账户", "股票/证券", me), ("自住房产", "其他资产", nil),
            ("微信钱包", "互联网钱包", partner.id), ("信用卡", "信用卡", partner.id),
            ("房贷", "房贷", nil)
        ]
        for (index, spec) in specs.enumerated() {
            let accountType = type(spec.1)
            addAccount(Account(ledgerId: data.ledger.id, name: spec.0, direction: accountType.direction,
                               typeId: accountType.id, ownerMemberId: spec.2, responsibleMemberId: spec.2,
                               sortOrder: index, createdAt: now, updatedAt: now), to: &data)
        }
        let target: [String: Decimal] = [
            "工资卡": 450_000, "家庭基金": 910_000, "股票账户": 900_000,
            "自住房产": 1_200_000, "微信钱包": 68_000, "信用卡": 28_000, "房贷": 636_000
        ]
        let factor: [Decimal] = [0.867, 0.89, 0.92, 0.95, 0.975, 1.0]
        var months: [String] = []
        var cursor = currentMonth(date: now)
        for _ in 0..<6 { months.append(cursor); cursor = previousMonth(cursor) ?? cursor }
        months.reverse()
        let current = currentMonth(date: now)
        let accountsById = Dictionary(uniqueKeysWithValues: data.accounts.map { ($0.id, $0) })
        for (index, month) in months.enumerated() {
            let snapshot = createSnapshot(month: month, in: &data)
            for entry in data.entries where entry.snapshotId == snapshot.id {
                guard let account = accountsById[entry.accountId] else { continue }
                updateEntry(entryId: entry.id, amount: (target[account.name] ?? 0) * factor[index],
                            confirmed: month < current || account.sortOrder < 4, in: &data)
            }
        }
        return data
    }
}
