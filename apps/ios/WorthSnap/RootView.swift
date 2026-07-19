import SwiftUI
import WorthSnapShared

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var purchases: PurchaseManager

    var body: some View {
        Group {
            if store.data.accounts.isEmpty && !store.loadFailed {
                FirstRunView()
            } else {
                mainTabs
            }
        }
        .tint(WCTheme.goldDeep)
        .safeAreaInset(edge: .top) {
            if store.loadFailed {
                SafeModeBanner(backupName: store.corruptBackupURL?.lastPathComponent)
            }
        }
        // 锁定亮色暖色主题：旺财是统一的奶油+金棕风格，避免深色模式下
        // 「亮背景 + 深色系统元素」的半吊子冲突。也作用于 sheet 与键盘。
        .preferredColorScheme(.light)
        .task(id: purchases.isPremium) {
            store.selectCurrentMonth(
                createIfMissing: purchases.isPremium
                    || store.cloud.isParticipant
                    || store.sortedValidSnapshots.count < PurchaseManager.freeSnapshotLimit
            )
        }
        .sheet(isPresented: $purchases.showPaywall) {
            PaywallView()
        }
        .alert("购买", isPresented: Binding(
            get: { purchases.message != nil },
            set: { if !$0 { purchases.message = nil } }
        )) {
            Button("好") { purchases.message = nil }
        } message: {
            Text(purchases.message ?? "")
        }
        .alert("加入这个家庭账本？", isPresented: Binding(
            get: { store.pendingFamilyShareMetadata != nil },
            set: { if !$0 { store.declineFamilyShare() } }
        )) {
            Button("取消", role: .cancel) { store.declineFamilyShare() }
            Button("备份并加入") {
                Task { await store.confirmPendingFamilyShare() }
            }
        } message: {
            Text("共享家庭账本将替换本机当前显示的账本。加入前，旺财会自动保存一份完整的本地备份。")
        }
    }

    private var mainTabs: some View {
        TabView {
            OverviewView()
                .tabItem { Label("首页", systemImage: "house.fill") }
            SnapshotView()
                .tabItem { Label("月度盘点", systemImage: "checklist") }
            TrendView()
                .tabItem { Label("变化", systemImage: "chart.xyaxis.line") }
            AccountsView()
                .tabItem { Label("账户", systemImage: "list.bullet.rectangle") }
        }
    }
}

struct PaywallView: View {
    @EnvironmentObject private var purchases: PurchaseManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 46))
                        .foregroundStyle(WCTheme.goldDeep)
                    Text("一次购买，永久使用")
                        .font(WCTypography.hero)
                        .foregroundStyle(WCTheme.ink)
                    Text("无订阅、无续费。长期、私密地记录你的净资产变化。")
                        .font(.body)
                        .foregroundStyle(WCTheme.inkSecondary)
                    VStack(alignment: .leading, spacing: 15) {
                        benefit("无限账户和月度快照", "infinity")
                        benefit("私密的 iCloud 家庭共享", "person.2.fill")
                        benefit("完整趋势和变化分析", "chart.xyaxis.line")
                        benefit("CSV 报表和进阶洞察", "doc.text.magnifyingglass")
                        benefit("包含未来的高级功能更新", "arrow.triangle.2.circlepath")
                    }
                    .padding(.vertical, 6)
                    Button {
                        Task { await purchases.purchaseLifetime() }
                    } label: {
                        HStack {
                            if purchases.isLoading { ProgressView().tint(.white) }
                            Text("永久解锁 · \(purchases.displayPrice)")
                                .font(.headline)
                        }
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(WCPrimaryButtonStyle())
                    .disabled(purchases.isLoading)
                    Button("恢复购买") {
                        Task { await purchases.restorePurchases() }
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(WCTheme.goldDeep)
                    Text("费用将从 Apple 账户扣除。本项目为非消耗型永久购买，不会自动续费。")
                        .font(.caption)
                        .foregroundStyle(WCTheme.inkTertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .padding(24)
            }
            .background(WCTheme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("暂不购买") { dismiss() }
                }
            }
        }
    }

    private func benefit(_ title: LocalizedStringKey, _ icon: String) -> some View {
        Label {
            Text(title).foregroundStyle(WCTheme.ink)
        } icon: {
            Image(systemName: icon).foregroundStyle(WCTheme.goldDeep).frame(width: 28)
        }
        .font(.body.weight(.medium))
    }
}

// MARK: - 首次使用引导

private struct FirstRunTemplate: Identifiable {
    let id: String
    let name: String
    let typeName: String
    let direction: Direction
    let icon: String
}

private struct FirstRunView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var purchases: PurchaseManager
    @State private var step = 0
    @State private var selectedIds: Set<String> = ["salary", "wallet", "fund", "credit"]
    @State private var amounts: [String: String] = [:]
    @FocusState private var focusedId: String?
    private let supportedCurrencies = ["CNY", "USD", "EUR", "GBP", "JPY", "HKD", "CAD", "AUD", "SGD"]

    private let templates: [FirstRunTemplate] = [
        .init(id: "salary", name: "工资卡", typeName: "银行存款", direction: .asset, icon: "creditcard"),
        .init(id: "bank", name: "其他银行卡", typeName: "银行存款", direction: .asset, icon: "building.columns"),
        .init(id: "wallet", name: "支付宝 / 微信", typeName: "互联网钱包", direction: .asset, icon: "iphone"),
        .init(id: "fund", name: "基金", typeName: "基金", direction: .asset, icon: "chart.line.uptrend.xyaxis"),
        .init(id: "stock", name: "股票账户", typeName: "股票/证券", direction: .asset, icon: "chart.bar"),
        .init(id: "pension", name: "公积金 / 养老金", typeName: "公积金/养老金", direction: .asset, icon: "umbrella"),
        .init(id: "cash", name: "现金", typeName: "现金", direction: .asset, icon: "banknote"),
        .init(id: "credit", name: "信用卡待还", typeName: "信用卡", direction: .liability, icon: "creditcard.fill"),
        .init(id: "mortgage", name: "房贷剩余本金", typeName: "房贷", direction: .liability, icon: "house"),
        .init(id: "loan", name: "其他贷款", typeName: "消费贷", direction: .liability, icon: "doc.text")
    ]

    private var selectedTemplates: [FirstRunTemplate] {
        templates.filter { selectedIds.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progressHeader
                Group {
                    if step == 0 { welcome }
                    else if step == 1 { templatePicker }
                    else { amountEntry }
                }
            }
            .background(WCTheme.background.ignoresSafeArea())
            .animation(.easeInOut(duration: 0.2), value: step)
        }
    }

    private var progressHeader: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(index <= step ? WCTheme.gold : WCTheme.gold.opacity(0.15))
                    .frame(height: 5)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 42))
                .foregroundStyle(WCTheme.goldDeep)
            Text("每月 3 分钟，\n看清自己的资产变化")
                .font(WCTypography.hero)
                .foregroundStyle(WCTheme.ink)
            Text("不用记每一笔消费。只需每月更新一次银行卡、基金和信用卡等账户余额，旺财会帮你留下长期变化。")
                .font(.body)
                .foregroundStyle(WCTheme.inkSecondary)
                .lineSpacing(5)
            VStack(alignment: .leading, spacing: 12) {
                Label("不连接银行，不读取交易流水", systemImage: "hand.raised")
                Label("数据默认保存在这台设备上", systemImage: "internaldrive")
                Label("第一次盘点约 3 分钟", systemImage: "clock")
            }
            .font(.subheadline)
            .foregroundStyle(WCTheme.inkSecondary)
            Spacer()
            primaryButton("开始第一次盘点") { step = 1 }
        }
        .padding(24)
    }

    private var templatePicker: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("你通常有哪些账户？")
                .wcTitle()
            Text("先勾选常用项目，之后都可以改名或增删。")
                .foregroundStyle(WCTheme.inkSecondary)
            HStack {
                Text("本位币").foregroundStyle(WCTheme.inkSecondary)
                Spacer()
                Picker("本位币", selection: Binding(
                    get: { store.data.ledger.baseCurrency },
                    set: { store.setInitialBaseCurrency($0) }
                )) {
                    ForEach(supportedCurrencies, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
            }
            .padding(.horizontal, 14)
            .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(templates) { item in
                        Button {
                            if selectedIds.contains(item.id) {
                                selectedIds.remove(item.id)
                            } else if purchases.isPremium || selectedIds.count < PurchaseManager.freeAccountLimit {
                                selectedIds.insert(item.id)
                            } else {
                                purchases.showPaywall = true
                            }
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: item.icon)
                                    .frame(width: 28)
                                    .foregroundStyle(item.direction == .asset ? WCTheme.up : WCTheme.down)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(LocalizedStringKey(item.name)).font(.body.weight(.semibold)).foregroundStyle(WCTheme.ink)
                                    Text(item.direction == .asset ? "我拥有的" : "我需要偿还的")
                                        .font(.caption).foregroundStyle(WCTheme.inkTertiary)
                                }
                                Spacer()
                                Image(systemName: selectedIds.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selectedIds.contains(item.id) ? WCTheme.goldDeep : WCTheme.inkFaint)
                            }
                            .padding(14)
                            .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Text("已选择 \(selectedIds.count) 个账户 · 预计 \(max(1, selectedIds.count / 3)) 分钟完成")
                .font(.footnote).foregroundStyle(WCTheme.inkTertiary)
            if !purchases.isPremium {
                Text("免费版最多可使用 5 个账户，随时可以解锁无限账户。")
                    .font(.caption).foregroundStyle(WCTheme.goldText)
            }
            HStack {
                Button("返回") { step = 0 }.foregroundStyle(WCTheme.inkSecondary)
                primaryButton("下一步") { step = 2 }
                    .disabled(selectedIds.isEmpty)
                    .opacity(selectedIds.isEmpty ? 0.45 : 1)
            }
        }
        .padding(20)
    }

    private var amountEntry: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("填写现在的余额")
                .wcTitle()
            Text("可以输入“12.3万”。暂时不清楚的账户可留空，按 0 元开始。")
                .font(.subheadline).foregroundStyle(WCTheme.inkSecondary)
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(selectedTemplates) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(LocalizedStringKey(item.name)).font(.body.weight(.semibold)).foregroundStyle(WCTheme.ink)
                                Spacer()
                                Text(item.direction == .asset ? "当前余额" : "当前待还")
                                    .font(.caption).foregroundStyle(WCTheme.inkTertiary)
                            }
                            HStack {
                                Text(AppFormatters.symbol(for: store.data.ledger.baseCurrency)).foregroundStyle(WCTheme.inkSecondary)
                                TextField("0", text: Binding(
                                    get: { amounts[item.id, default: ""] },
                                    set: { amounts[item.id] = $0 }
                                ))
                                .keyboardType(.decimalPad)
                                .focused($focusedId, equals: item.id)
                                .font(.title3.monospacedDigit())
                            }
                        }
                        .padding(14)
                        .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
            HStack {
                Button("返回") { focusedId = nil; step = 1 }.foregroundStyle(WCTheme.inkSecondary)
                primaryButton("完成第一次盘点") { finish() }
            }
        }
        .padding(20)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { focusedId = nil }
            }
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
        }
        .buttonStyle(WCPrimaryButtonStyle())
    }

    private func finish() {
        focusedId = nil
        let items = selectedTemplates.map { item in
            let raw = amounts[item.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
            return (name: String(localized: String.LocalizationValue(item.name)), typeName: item.typeName, direction: item.direction,
                    amount: AmountParser.parse(raw.isEmpty ? "0" : raw) ?? 0)
        }
        store.completeFirstRun(with: items)
    }
}

/// 数据读取失败时的安全模式提示：明确告知用户「数据没丢、已备份、当前改动不会被保存」，
/// 避免用户误以为数据丢失而重新录入、反而把损坏文件覆盖。
private struct SafeModeBanner: View {
    var backupName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("数据读取失败 · 已进入安全模式", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
            Text("你的原始数据仍保存在设备上，并已自动备份。为避免覆盖，当前的改动不会被保存。请稍后重试或联系支持。")
                .font(.caption)
            if let backupName {
                Text("备份文件：\(backupName)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.yellow.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.orange.opacity(0.4), lineWidth: 1))
        .padding(.horizontal)
        .padding(.bottom, 4)
    }
}
