import Foundation
import WorthSnapShared

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("Check failed: \(message)\n", stderr)
        exit(1)
    }
}

// 开发辅助：`--emit-demo <path>` 导出一份演示数据文件（用于灌进模拟器截图对比设计稿）。
if let index = CommandLine.arguments.firstIndex(of: "--emit-demo"), index + 1 < CommandLine.arguments.count {
    let path = CommandLine.arguments[index + 1]
    let payload = try WorthSnapStore.encode(WorthSnapEngine.demoData())
    try payload.write(to: URL(fileURLWithPath: path))
    print("demo data written to \(path)")
    exit(0)
}

expect(AmountParser.parse("12.3万") == Decimal(123_000), "parse wan unit")
expect(AmountParser.parse("1,234.56") == Decimal(string: "1234.56"), "parse comma decimal")
expect(AmountParser.parse("-1") == nil, "reject negative")

var data = WorthSnapEngine.sampleData()
let snapshot = data.snapshots[0]
let accountsById = Dictionary(uniqueKeysWithValues: data.accounts.map { ($0.id, $0) })
for entry in data.entries.filter({ $0.snapshotId == snapshot.id }) {
    let amount: Decimal = accountsById[entry.accountId]?.direction == .asset ? 100 : 30
    WorthSnapEngine.updateEntry(entryId: entry.id, amount: amount, confirmed: true, in: &data)
}

let totals = WorthSnapEngine.totals(for: snapshot, in: data)
expect(totals.totalAssets == 200, "asset totals")
expect(totals.totalLiabilities == 30, "liability totals")
expect(totals.netWorth == 170, "net worth")
expect(data.snapshots.first?.completed == true, "completion")

let next = WorthSnapEngine.createSnapshot(month: "2099-01", in: &data)
expect(data.entries.contains { $0.snapshotId == next.id && $0.confirmed == false }, "new snapshot unconfirmed")
expect(WorthSnapExporter.summaryCSV(data: data).hasPrefix("month,base_currency,total_assets"), "summary csv header")
expect((try? WorthSnapExporter.json(data: data).isEmpty) == false, "json export")

// MARK: - 环比与趋势

func approx(_ value: Double?, _ expected: Double, _ tol: Double = 1e-9) -> Bool {
    guard let value else { return false }
    return abs(value - expected) < tol
}

var cmpData = WorthSnapEngine.sampleData()
let byId = Dictionary(uniqueKeysWithValues: cmpData.accounts.map { ($0.id, $0) })
let monthA = cmpData.snapshots[0].month
// 上月：两个资产各 100、负债 30 → 资产 200 / 负债 30 / 净 170
for entry in cmpData.entries where entry.snapshotId == cmpData.snapshots[0].id {
    let amount: Decimal = byId[entry.accountId]?.direction == .asset ? 100 : 30
    WorthSnapEngine.updateEntry(entryId: entry.id, amount: amount, confirmed: true, in: &cmpData)
}
let monthB = WorthSnapEngine.nextMonth(monthA)!
let snapB = WorthSnapEngine.createSnapshot(month: monthB, in: &cmpData)
// 本月：两个资产各 120、负债 30 → 资产 240 / 负债 30 / 净 210
for entry in cmpData.entries where entry.snapshotId == snapB.id {
    let amount: Decimal = byId[entry.accountId]?.direction == .asset ? 120 : 30
    WorthSnapEngine.updateEntry(entryId: entry.id, amount: amount, confirmed: true, in: &cmpData)
}

let snapBFresh = cmpData.snapshots.first { $0.month == monthB }!
let cmp = WorthSnapEngine.comparison(for: snapBFresh, in: cmpData)
expect(cmp.previous != nil, "comparison finds previous month")
expect(approx(cmp.assetsRatio, 0.2), "assets MoM +20%")
expect(approx(cmp.liabilitiesRatio, 0.0), "liabilities MoM 0%")
expect(approx(cmp.netWorthRatio, 40.0 / 170.0), "net worth MoM")

let cmpFirst = WorthSnapEngine.comparison(for: cmpData.snapshots.first { $0.month == monthA }!, in: cmpData)
expect(cmpFirst.previous == nil, "first month has no previous")
expect(cmpFirst.netWorthRatio == nil, "first month ratio is nil")

expect(approx(WorthSnapEngine.netWorthTrendChange(months: 6, endingAt: monthB, in: cmpData), 40.0 / 170.0), "trend change first->last")
expect(WorthSnapEngine.netWorthTrend(months: 6, endingAt: monthB, in: cmpData).count == 2, "trend has two points")

// MARK: - 持久化与数据安全

let sampleForStore = WorthSnapEngine.sampleData()

// 编解码往返：解码再编码应得到完全相同的字节（避免日期亚秒精度干扰直接相等比较）。
let encodedOnce = try WorthSnapStore.encode(sampleForStore)
let roundTripped = try WorthSnapStore.decode(encodedOnce)
let encodedTwice = try WorthSnapStore.encode(roundTripped)
expect(encodedOnce == encodedTwice, "encode/decode round-trip is stable")
expect(roundTripped.accounts.count == sampleForStore.accounts.count, "round-trip keeps accounts")
expect(roundTripped.snapshots.count == sampleForStore.snapshots.count, "round-trip keeps snapshots")
expect(roundTripped.entries.count == sampleForStore.entries.count, "round-trip keeps entries")

// 向后兼容 + v1→v2 迁移：构造一份「真实的 v1 数据」（Account 带 ownership 枚举、无 members）。
// 既覆盖「史前无信封文件」也覆盖「v1 信封文件」两条路径。
let v1DataObject: [String: Any] = [
    "ledger": ["id": UUID().uuidString, "name": "旺财账本", "baseCurrency": "CNY",
               "createdAt": "2025-01-01T00:00:00Z", "updatedAt": "2025-01-01T00:00:00Z"],
    "accountTypes": [], "tags": [], "snapshots": [], "entries": [],
    "accounts": [
        ["id": UUID().uuidString, "ledgerId": UUID().uuidString, "name": "我的工资卡",
         "direction": "asset", "typeId": UUID().uuidString, "currency": "CNY", "ownership": "me",
         "tagIds": [], "sortOrder": 0, "archived": false,
         "createdAt": "2025-01-01T00:00:00Z", "updatedAt": "2025-01-01T00:00:00Z"],
        ["id": UUID().uuidString, "ledgerId": UUID().uuidString, "name": "TA的卡",
         "direction": "asset", "typeId": UUID().uuidString, "currency": "CNY", "ownership": "partner",
         "tagIds": [], "sortOrder": 1, "archived": false,
         "createdAt": "2025-01-01T00:00:00Z", "updatedAt": "2025-01-01T00:00:00Z"],
        ["id": UUID().uuidString, "ledgerId": UUID().uuidString, "name": "家庭基金",
         "direction": "asset", "typeId": UUID().uuidString, "currency": "CNY", "ownership": "shared",
         "tagIds": [], "sortOrder": 2, "archived": false,
         "createdAt": "2025-01-01T00:00:00Z", "updatedAt": "2025-01-01T00:00:00Z"]
    ]
]

// 路径一：史前无信封文件（顶层即 WorthSnapData）。
let preEnvelope = try JSONSerialization.data(withJSONObject: v1DataObject)
let fromPre = try WorthSnapStore.decode(preEnvelope)
expect(fromPre.accounts.count == 3, "legacy pre-envelope decodes all accounts")
expect(fromPre.members.contains { $0.name == "我" }, "migration creates current member 我")
expect(fromPre.members.contains { $0.name == "伴侣" }, "migration creates partner member when ownership=partner exists")
expect(fromPre.currentMember?.name == "我", "currentMemberId points to 我")
let meId: UUID? = fromPre.currentMemberId
let myAccount = fromPre.accounts.first { $0.name == "我的工资卡" }!
expect(myAccount.ownerMemberId == meId, "ownership=me maps to current member")
expect(myAccount.responsibleMemberId == meId, "responsible defaults to owner")
expect(fromPre.accounts.first { $0.name == "家庭基金" }!.ownerMemberId == nil, "ownership=shared maps to nil owner (共同)")
let migratedPartnerId: UUID? = fromPre.members.first { $0.name == "伴侣" }!.id
expect(fromPre.accounts.first { $0.name == "TA的卡" }!.ownerMemberId == migratedPartnerId, "ownership=partner maps to partner member")

// 路径二：v1 信封文件（{schemaVersion:1, data:{...}}）。
let v1Envelope = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "data": v1DataObject])
let fromV1 = try WorthSnapStore.decode(v1Envelope)
expect(fromV1.accounts.count == 3, "v1 envelope decodes all accounts")
expect(fromV1.members.count == 2, "v1 envelope migration creates two members")

// 损坏文件必须抛错（绝不静默返回空数据）。
var corruptedThrew = false
do {
    _ = try WorthSnapStore.decode(Data("{ this is not valid json".utf8))
} catch {
    corruptedThrew = true
}
expect(corruptedThrew, "corrupted data throws instead of returning empty")

// 合法 JSON 但结构不符（缺字段）也必须抛错。
var wrongShapeThrew = false
do {
    _ = try WorthSnapStore.decode(Data(#"{"foo": 1}"#.utf8))
} catch {
    wrongShapeThrew = true
}
expect(wrongShapeThrew, "valid-but-wrong-shape data throws")

// 未来版本（比当前 App 新）必须被识别并拒绝，且错误类型是 future-version 而非 corrupted——
// 这样 App 层能区分「文件坏了」和「文件比我新」，后者绝不能覆盖。
var futureError: WorthSnapStoreError?
do {
    _ = try WorthSnapStore.decode(Data(#"{"schemaVersion": 9999, "data": {}}"#.utf8))
} catch let error as WorthSnapStoreError {
    futureError = error
} catch {
    // 其它错误类型不符合预期
}
expect(futureError == .unsupportedFutureVersion(found: 9999, supported: WorthSnapSchema.current), "future version is rejected, not treated as corrupt")

// MARK: - 演示数据正确性（UI 截图依赖）

let demo = WorthSnapEngine.demoData()
let demoCurrent = demo.snapshots.first { $0.month == WorthSnapEngine.currentMonth() }!
let demoTotals = WorthSnapEngine.totals(for: demoCurrent, in: demo)
expect(demoTotals.totalAssets == 3_528_000, "demo 总资产 352.8 万")
expect(demoTotals.totalLiabilities == 664_000, "demo 总负债 66.4 万")
expect(demoTotals.netWorth == 2_864_000, "demo 净资产 286.4 万")
expect(approx(WorthSnapEngine.netWorthTrendChange(in: demo), 0.1534, 0.001), "demo 趋势约 +15.3%")

// MARK: - 成员与三栏聚合

// 全新安装：seed 数据自带本机成员「我」，currentMemberId 指向它。
let seeded = WorthSnapEngine.seededData()
expect(seeded.members.count == 1 && seeded.currentMember?.name == "我", "seed 自带本机成员 我")

// demo 数据：两个成员，三栏净值之和 == 家庭净资产。
expect(demo.members.count == 2, "demo 含两名成员")
let mine = WorthSnapEngine.totals(by: .mine, for: demoCurrent, in: demo)
let theirs = WorthSnapEngine.totals(by: .theirs, for: demoCurrent, in: demo)
let sharedT = WorthSnapEngine.totals(by: .shared, for: demoCurrent, in: demo)
expect(mine.netWorth + theirs.netWorth + sharedT.netWorth == demoTotals.netWorth, "三栏净值之和 == 家庭净资产")
// demo 里「我」名下：工资卡 45万 + 股票 90万 = 135万资产、无负债。
expect(mine.totalAssets == 1_350_000 && mine.totalLiabilities == 0, "我的栏资产 135 万")

// 成员离开：归档不删账户，负责账户转交他人。
var leaveData = demo
let leavingId = leaveData.members.first { $0.name == "TA" }!.id
let accountCountBefore = leaveData.accounts.count
WorthSnapEngine.archiveMember(leavingId, reassignResponsibleTo: leaveData.currentMemberId, in: &leaveData)
expect(leaveData.accounts.count == accountCountBefore, "成员离开不删除账户（人走数据留）")
expect(leaveData.members.first { $0.id == leavingId }!.archived, "离开成员被归档")
expect(!leaveData.accounts.contains { $0.responsibleMemberId == leavingId }, "离开成员的负责账户已转交")

print("WorthSnapSharedChecks passed")
