import SwiftUI
import WorthSnapShared

struct AccountsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var purchases: PurchaseManager
    @State private var showingAdd = false
    @State private var editingAccount: Account?
    @State private var showArchived = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("显示范围", selection: $showArchived) {
                        Text("正在使用").tag(false)
                        Text("包含归档").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
                .wcRow()
                ForEach(store.data.accounts.filter { showArchived || !$0.archived }.sorted(by: { $0.sortOrder < $1.sortOrder })) { account in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(account.direction == .asset ? WCTheme.up : WCTheme.down)
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(account.name)
                                .font(.headline)
                                .foregroundStyle(WCTheme.ink)
                            Text(accountSubtitle(account))
                                .font(.caption)
                                .foregroundStyle(WCTheme.inkTertiary)
                        }
                        Spacer()
                        if account.archived {
                            Text("已归档")
                                .font(.caption)
                                .foregroundStyle(WCTheme.inkFaint)
                        } else if !store.canManage(account) {
                            Label("View only", systemImage: "lock")
                                .font(.caption)
                                .foregroundStyle(WCTheme.inkFaint)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if store.canManage(account) { editingAccount = account }
                    }
                    .wcRow()
                    .swipeActions {
                        if store.canManage(account) {
                        Button(account.archived ? "恢复" : "归档") {
                            store.toggleArchive(account: account)
                        }
                        .tint(account.archived ? WCTheme.up : WCTheme.gold)
                        }
                    }
                }
            }
            .wcScreen()
            .navigationTitle("账户")
            .toolbar {
                Button {
                    if purchases.isPremium || store.cloud.isParticipant || store.data.accounts.count < PurchaseManager.freeAccountLimit {
                        showingAdd = true
                    } else {
                        purchases.showPaywall = true
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !purchases.isPremium && !store.cloud.isParticipant {
                    Text("Free: \(store.data.accounts.count) / \(PurchaseManager.freeAccountLimit) accounts")
                        .font(.caption)
                        .foregroundStyle(WCTheme.inkTertiary)
                        .padding(.vertical, 6)
                }
            }
            .sheet(isPresented: $showingAdd) {
                AccountFormView(mode: .add)
            }
            .sheet(item: $editingAccount) { account in
                AccountFormView(mode: .edit(account))
            }
        }
    }

    private func accountSubtitle(_ account: Account) -> String {
        var parts = [store.typeName(id: account.typeId), account.currency]
        if store.activeMembers.count > 1 {
            parts.append(store.memberName(id: account.ownerMemberId))
        }
        return parts.joined(separator: " · ")
    }
}

private enum AccountFormMode {
    case add
    case edit(Account)

    var title: String {
        switch self {
        case .add:
            return "新增账户"
        case .edit:
            return "编辑账户"
        }
    }
}

private struct AccountFormView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    private let currencies = ["CNY", "USD", "HKD", "EUR", "JPY", "GBP", "SGD", "AUD", "CAD"]
    let mode: AccountFormMode
    @State private var name: String
    @State private var direction: Direction
    @State private var currency: String
    @State private var ownerMemberId: UUID?
    @State private var responsibleMemberId: UUID?
    @State private var selectedTypeId: UUID?
    @State private var initialAmountText = ""
    @State private var pendingSensitiveSave = false
    @State private var didDefaultOwner = false

    var filteredTypes: [AccountType] {
        store.data.accountTypes.filter { $0.direction == direction && !$0.archived }
    }

    private var availableCurrencies: [String] {
        currencies.contains(normalizedCurrency) ? currencies : currencies + [normalizedCurrency]
    }

    private var normalizedCurrency: String {
        let trimmed = currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return trimmed.isEmpty ? "CNY" : trimmed
    }

    private var sensitiveChangeMessage: String? {
        guard case .edit(let account) = mode else { return nil }
        var changes: [String] = []
        if account.currency != normalizedCurrency {
            changes.append("币种会从 \(currencyTitle(account.currency)) 改为 \(currencyTitle(normalizedCurrency))。已有快照明细会保留原币种、汇率和折算金额；新的快照会使用新币种。")
        }
        if account.direction != direction {
            changes.append("方向会从 \(account.direction.title) 改为 \(direction.title)。修改仅影响之后新建的快照，已有历史保持原口径。")
        }
        return changes.isEmpty ? nil : changes.joined(separator: "\n\n")
    }

    init(mode: AccountFormMode) {
        self.mode = mode
        switch mode {
        case .add:
            _name = State(initialValue: "")
            _direction = State(initialValue: .asset)
            _currency = State(initialValue: "CNY")
            // 归属默认本人，在 .onAppear 里从 store 填充（init 拿不到 EnvironmentObject）。
            _ownerMemberId = State(initialValue: nil)
            _responsibleMemberId = State(initialValue: nil)
            _selectedTypeId = State(initialValue: nil)
        case .edit(let account):
            _name = State(initialValue: account.name)
            _direction = State(initialValue: account.direction)
            _currency = State(initialValue: account.currency)
            _ownerMemberId = State(initialValue: account.ownerMemberId)
            _responsibleMemberId = State(initialValue: account.responsibleMemberId)
            _selectedTypeId = State(initialValue: account.typeId)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("账户名称", text: $name)
                    .keyboardDismissToolbar()
                Picker("方向", selection: $direction) {
                    ForEach(Direction.allCases) { Text($0.title).tag($0) }
                }
                Picker("类型", selection: Binding(
                    get: { selectedTypeId ?? filteredTypes.first?.id },
                    set: { selectedTypeId = $0 }
                )) {
                    ForEach(filteredTypes) { type in
                        Text(type.name).tag(Optional(type.id))
                    }
                }
                Picker("币种", selection: $currency) {
                    ForEach(availableCurrencies, id: \.self) { code in
                        Text(currencyTitle(code)).tag(code)
                    }
                }
                if case .add = mode {
                    Section("本月余额（可选）") {
                        if normalizedCurrency == store.data.ledger.baseCurrency {
                            TextField(direction == .asset ? "当前余额，例如 12.3万" : "当前待还，例如 3200", text: $initialAmountText)
                                .keyboardType(.decimalPad)
                                .keyboardDismissToolbar()
                        } else {
                            Text("外币账户保存后，请在月度盘点中先设置汇率，再填写余额。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if store.activeMembers.count > 1 {
                    Section("家庭协作") {
                        Picker("归属", selection: $ownerMemberId) {
                            ForEach(store.activeMembers) { member in
                                Text(member.name).tag(Optional(member.id))
                            }
                            Text("共同").tag(UUID?.none)
                        }
                        Picker("每月由谁更新", selection: $responsibleMemberId) {
                            Text("未指定（归属人）").tag(UUID?.none)
                            ForEach(store.activeMembers) { member in
                                Text(member.name).tag(Optional(member.id))
                            }
                        }
                    } footer: {
                        Text("归属仅用于在账本中区分“我的、TA 的、共同”，不代表法律上的财产归属。")
                    }
                }
                if case .edit = mode {
                    Section {
                        Text("修改币种或资产/负债方向只影响之后新建的快照；已有快照会保留当时的币种、汇率、方向和类型。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(mode.title)
            .onAppear {
                // 新增账户：归属默认本人（init 拿不到 store，放到这里填充）。只执行一次，
                // 否则用户主动选「共同」(nil) 后再次 onAppear 会被改回本人。
                if case .add = mode, !didDefaultOwner {
                    ownerMemberId = store.data.currentMemberId
                    didDefaultOwner = true
                }
            }
            .onChange(of: direction) { _, newDirection in
                if !filteredTypes.contains(where: { $0.id == selectedTypeId && $0.direction == newDirection }) {
                    selectedTypeId = filteredTypes.first?.id
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if sensitiveChangeMessage == nil {
                            save()
                        } else {
                            pendingSensitiveSave = true
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || filteredTypes.isEmpty)
                }
            }
            .alert("确认修改账户口径？", isPresented: $pendingSensitiveSave) {
                Button("取消", role: .cancel) {}
                Button("确认保存", role: .destructive) {
                    save()
                }
            } message: {
                Text(sensitiveChangeMessage ?? "")
            }
        }
    }

    private func save() {
        let typeId = selectedTypeId ?? filteredTypes.first!.id
        switch mode {
        case .add:
            let raw = initialAmountText.trimmingCharacters(in: .whitespacesAndNewlines)
            let initialAmount = raw.isEmpty ? nil : AmountParser.parse(raw)
            store.addAccount(name: name, direction: direction, typeId: typeId, currency: normalizedCurrency, ownerMemberId: ownerMemberId, responsibleMemberId: responsibleMemberId, initialAmount: initialAmount)
        case .edit(let account):
            store.updateAccount(account, name: name, direction: direction, typeId: typeId, currency: normalizedCurrency, ownerMemberId: ownerMemberId, responsibleMemberId: responsibleMemberId)
        }
        dismiss()
    }

    private func currencyTitle(_ code: String) -> String {
        switch code {
        case "CNY":
            return "人民币 CNY"
        case "USD":
            return "美元 USD"
        case "HKD":
            return "港币 HKD"
        case "EUR":
            return "欧元 EUR"
        case "JPY":
            return "日元 JPY"
        case "GBP":
            return "英镑 GBP"
        case "SGD":
            return "新加坡元 SGD"
        case "AUD":
            return "澳元 AUD"
        case "CAD":
            return "加元 CAD"
        default:
            return code
        }
    }
}
