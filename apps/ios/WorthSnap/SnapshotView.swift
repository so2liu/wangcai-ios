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
        let entries = store.entries(for: snapshot)
        let confirmed = entries.filter(\.confirmed).count
        return ScrollView {
            VStack(alignment: .leading, spacing: WCSpacing.section) {
                if snapshot.month != WorthSnapEngine.currentMonth() {
                    currentMonthPrompt
                }
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("本月盘点")
                                .font(WCTypography.headline)
                                .foregroundStyle(WCTheme.ink)
                            Text(snapshot.completed ? "本月盘点已完成" : "逐个确认账户余额，生成本月结果")
                                .font(.subheadline)
                                .foregroundStyle(WCTheme.inkSecondary)
                        }
                        Spacer()
                        Text("\(confirmed)/\(entries.count)")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(snapshot.completed ? WCTheme.up : WCTheme.goldDeep)
                    }
                    ProgressView(value: entries.isEmpty ? 0 : Double(confirmed) / Double(entries.count))
                        .tint(snapshot.completed ? WCTheme.up : WCTheme.gold)
                    HStack {
                        Button {
                            openAdjacent(offset: -1)
                        } label: {
                            Image(systemName: "chevron.left")
                                .frame(width: 36, height: 32)
                        }
                        .accessibilityLabel("上月")

                        Spacer(minLength: 8)
                        Menu {
                            Picker("月份", selection: $store.selectedMonth) {
                                ForEach(store.sortedValidSnapshots) { item in
                                    Text(AppFormatters.monthTitle(item.month)).tag(item.month)
                                }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Text(AppFormatters.monthTitle(snapshot.month))
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                Image(systemName: "chevron.down")
                                    .font(.caption2.weight(.bold))
                            }
                            .foregroundStyle(WCTheme.ink)
                        }
                        .layoutPriority(1)

                        Spacer(minLength: 8)
                        Button {
                            openAdjacent(offset: 1)
                        } label: {
                            Image(systemName: "chevron.right")
                                .frame(width: 36, height: 32)
                        }
                        .accessibilityLabel("下月")
                    }
                    .buttonStyle(.borderless)
                }
                .wcCard(fill: WCTheme.netCard)

                if store.data.accounts.filter({ !$0.archived }).isEmpty {
                    ContentUnavailableView("还没有账户", systemImage: "list.bullet.rectangle", description: Text("先在账户页添加需要每月确认的资产或负债账户。"))
                        .padding(.vertical, 40)
                } else {
                    ForEach(Direction.allCases) { direction in
                        let rows = entries.filter { $0.accountDirection == direction }
                        if !rows.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                WCSectionHeader(direction == .asset ? "确认资产" : "确认负债", detail: LocalizedStringKey("\(rows.filter(\.confirmed).count)/\(rows.count) 已确认"))
                                VStack(spacing: 0) {
                                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, entry in
                                        SnapshotEntryRow(entry: entry, focusedEntryId: $focusedEntryId)
                                            .padding(16)
                                        if index < rows.count - 1 { Divider().padding(.leading, 16) }
                                    }
                                }
                                .wcCard(fill: LinearGradient(colors: [WCTheme.surface, WCTheme.surface], startPoint: .top, endPoint: .bottom), padding: 0)
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    WCSectionHeader("整月备注", detail: "可选")
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
                    .padding(14)
                    .background(WCTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(WCTheme.cardStroke, lineWidth: 1))
                }
            }
            .padding(WCSpacing.page)
        }
            .background(WCTheme.background.ignoresSafeArea())
            .tint(WCTheme.goldDeep)
            .navigationTitle("月度盘点")
            .navigationBarTitleDisplayMode(.inline)
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

    private var currentMonthPrompt: some View {
        let current = WorthSnapEngine.currentMonth()
        let canCreate = purchases.isPremium
            || store.cloud.isParticipant
            || store.sortedValidSnapshots.count < PurchaseManager.freeSnapshotLimit
        return Button {
            if canCreate {
                store.selectCurrentMonth(createIfMissing: true)
            } else {
                purchases.showPaywall = true
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "calendar.badge.plus")
                    .foregroundStyle(WCTheme.goldDeep)
                VStack(alignment: .leading, spacing: 2) {
                    Text("开始 \(AppFormatters.monthTitle(current)) 盘点")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WCTheme.ink)
                    Text(canCreate ? "创建当前月份并沿用上月余额" : "免费版已达到 2 个月记录上限")
                        .font(.caption)
                        .foregroundStyle(WCTheme.inkTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WCTheme.inkFaint)
            }
            .padding(14)
            .background(WCTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
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
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.accountName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(WCTheme.ink)
                            .lineLimit(1)
                        Text("\(store.typeName(id: entry.accountTypeId)) · \(entry.currency)" + previousAmountText)
                            .font(.caption)
                            .foregroundStyle(WCTheme.inkTertiary)
                    }
                    Spacer()
                    Image(systemName: entry.confirmed ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(entry.confirmed ? WCTheme.up : WCTheme.inkFaint)
                }
                if !canUpdate {
                    Label("由 \(store.memberName(id: store.account(id: entry.accountId)?.responsibleMemberId ?? store.account(id: entry.accountId)?.ownerMemberId)) 更新", systemImage: "person.crop.circle")
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
                        .font(.subheadline.monospacedDigit())
                        .multilineTextAlignment(.trailing)
                        .focused(focusedEntryId, equals: entry.id)
                        .disabled(!canUpdate)
                        .padding(.horizontal, 12)
                        .frame(height: 40)
                        .background(WCTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                        Image(systemName: "checkmark")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(WCTheme.goldFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(amountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "金额没变，确认" : "保存并确认")
                    .disabled(!canUpdate)
                }
                if let validationMessage {
                    Text(validationMessage).font(.caption).foregroundStyle(.red)
                }
                if entry.currency != store.data.ledger.baseCurrency {
                    Text("折算 \(AppFormatters.money(entry.convertedAmount))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 3)
        }
    }

    private var previousAmountText: String {
        guard let previousEntry else { return "" }
        return " · 上月 \(AppFormatters.symbolized(previousEntry.amount, currency: previousEntry.currency))"
    }
}
