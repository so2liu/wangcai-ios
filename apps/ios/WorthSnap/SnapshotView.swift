import SwiftUI
import WorthSnapShared

struct SnapshotView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var purchases: PurchaseManager
    @FocusState private var focusedEntryId: UUID?

    var body: some View {
        NavigationStack {
            if let snapshot = store.selectedSnapshot {
                snapshotForm(snapshot)
            } else {
                ProgressView("正在准备快照…")
                    .task { store.ensureSelectedSnapshot() }
            }
        }
    }

    private func snapshotForm(_ snapshot: Snapshot) -> some View {
        Form {
                Section("月份") {
                    Picker("月份", selection: $store.selectedMonth) {
                        ForEach(store.sortedValidSnapshots) { snapshot in
                            Text(snapshot.month).tag(snapshot.month)
                        }
                    }
                    .font(.body.monospacedDigit())

                    HStack {
                        Button {
                            openAdjacent(offset: -1)
                        } label: {
                            Label("上月", systemImage: "chevron.left")
                        }
                        Spacer()
                        Button {
                            openAdjacent(offset: 1)
                        } label: {
                            Label("下月", systemImage: "chevron.right")
                        }
                    }
                    .buttonStyle(.borderless)
                }
                .wcRow()
                if store.data.accounts.filter({ !$0.archived }).isEmpty {
                    Section {
                        ContentUnavailableView(
                            "还没有账户",
                            systemImage: "list.bullet.rectangle",
                            description: Text("先在账户页添加需要每月确认的资产或负债账户。")
                        )
                    }
                    .wcRow()
                } else {
                    ForEach(Direction.allCases) { direction in
                        let rows = store.entries(for: snapshot).filter { entry in
                            entry.accountDirection == direction
                        }
                        if !rows.isEmpty {
                            Section(direction.title) {
                                ForEach(rows) { entry in
                                    SnapshotEntryRow(entry: entry, focusedEntryId: $focusedEntryId)
                                }
                            }
                            .wcRow()
                        }
                    }
                }
                Section("整月备注") {
                    TextField("补充说明", text: Binding(
                        get: { snapshot.note },
                        set: { value in
                            if let index = store.data.snapshots.firstIndex(where: { $0.id == snapshot.id }) {
                                store.data.snapshots[index].note = value
                                // 必须 bump updatedAt：同步按 updatedAt 算增量，否则备注改动不会推给其他设备。
                                store.data.snapshots[index].updatedAt = Date()
                                store.save()
                            }
                        }
                    ), axis: .vertical)
                    .keyboardDismissToolbar()
                }
                .wcRow()
            }
            .wcScreen()
            .tint(WCTheme.goldDeep)
            .navigationTitle("月度盘点")
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SnapshotStatusLabel(completed: snapshot.completed)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") {
                        focusedEntryId = nil
                    }
                }
            }
    }

    private func openAdjacent(offset: Int) {
        let current = WorthSnapEngine.isValidMonth(store.selectedMonth) ? store.selectedMonth : WorthSnapEngine.currentMonth()
        let target = offset < 0 ? WorthSnapEngine.previousMonth(current) : WorthSnapEngine.nextMonth(current)
        let alreadyExists = target.map { month in store.data.snapshots.contains { $0.month == month } } ?? false
        if alreadyExists || purchases.isPremium || store.cloud.isParticipant || store.sortedValidSnapshots.count < PurchaseManager.freeSnapshotLimit {
            store.createAdjacentSnapshot(offset: offset)
        } else {
            purchases.showPaywall = true
        }
    }
}

private struct SnapshotStatusLabel: View {
    var completed: Bool

    var body: some View {
        Label(completed ? "已完成" : "盘点中", systemImage: completed ? "checkmark.circle" : "clock")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
}

private struct SnapshotEntryRow: View {
    @EnvironmentObject private var store: AppStore
    var entry: SnapshotEntry
    var focusedEntryId: FocusState<UUID?>.Binding
    @State private var amountText = ""
    @State private var rateText = ""
    @State private var validationMessage: String?

    private var previousEntry: SnapshotEntry? { store.previousEntry(for: entry) }
    private var canUpdate: Bool { store.canUpdate(entry) }

    var body: some View {
        if store.account(id: entry.accountId) != nil {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(entry.accountName)
                            .font(.body)
                            .foregroundStyle(WCTheme.ink)
                        Text("\(store.typeName(id: entry.accountTypeId)) · \(entry.currency)")
                            .font(.caption)
                            .foregroundStyle(WCTheme.inkTertiary)
                        if let previousEntry {
                            Text("上月 \(AppFormatters.symbolized(previousEntry.amount, currency: previousEntry.currency))")
                                .font(.caption)
                                .foregroundStyle(WCTheme.inkFaint)
                        }
                    }
                    Spacer()
                    Image(systemName: entry.confirmed ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(entry.confirmed ? WCTheme.up : WCTheme.inkFaint)
                }
                if !canUpdate {
                    Label("Updated by \(store.memberName(id: store.account(id: entry.accountId)?.responsibleMemberId ?? store.account(id: entry.accountId)?.ownerMemberId))", systemImage: "person.crop.circle")
                        .font(.caption)
                        .foregroundStyle(WCTheme.inkTertiary)
                }
                if entry.currency != store.data.ledger.baseCurrency {
                    HStack {
                        Text("1 \(entry.currency) =")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("输入兑 \(store.data.ledger.baseCurrency) 汇率", text: $rateText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Button("保存汇率") {
                            let raw = rateText.trimmingCharacters(in: .whitespacesAndNewlines)
                            if store.updateExchangeRate(for: entry, rawRate: raw) {
                                rateText = ""
                                validationMessage = nil
                            } else {
                                validationMessage = "请输入大于 0 的有效汇率"
                            }
                        }
                        .buttonStyle(.borderless)
                        .disabled(!canUpdate)
                    }
                    if entry.exchangeRate <= 0 {
                        Label("缺少汇率，该账户暂不计入汇总且不能确认", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Text("当前汇率：\(entry.exchangeRate.description)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    TextField(AppFormatters.inputPlaceholder(for: entry.amount, currency: entry.currency), text: $amountText)
                        .keyboardType(.decimalPad)
                        .font(.body.monospacedDigit())
                        .multilineTextAlignment(.trailing)
                        .focused(focusedEntryId, equals: entry.id)
                        .disabled(!canUpdate)
                    Button {
                        let rawAmount = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if store.updateEntry(entry, rawAmount: rawAmount.isEmpty ? entry.amount.description : rawAmount, confirmed: true) {
                            amountText = ""
                            validationMessage = nil
                            focusedEntryId.wrappedValue = nil
                        } else {
                            validationMessage = entry.exchangeRate <= 0 ? "请先设置汇率" : "请输入有效的非负金额"
                        }
                    } label: {
                        Label(amountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "金额没变，确认" : "保存并确认", systemImage: "checkmark")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!canUpdate)
                }
                if let validationMessage {
                    Text(validationMessage).font(.caption).foregroundStyle(.red)
                }
                Text("折算 \(AppFormatters.money(entry.convertedAmount))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 3)
        }
    }
}
