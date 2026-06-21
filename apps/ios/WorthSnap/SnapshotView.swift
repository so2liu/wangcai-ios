import SwiftUI
import WorthSnapShared

struct SnapshotView: View {
    @EnvironmentObject private var store: AppStore
    @FocusState private var focusedEntryId: UUID?

    var body: some View {
        NavigationStack {
            let snapshot = store.snapshot()
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
                            store.createAdjacentSnapshot(offset: -1)
                        } label: {
                            Label("上月", systemImage: "chevron.left")
                        }
                        Spacer()
                        Button {
                            store.createAdjacentSnapshot(offset: 1)
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
                            store.account(id: entry.accountId)?.direction == direction
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
            .navigationTitle("快照")
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

    var body: some View {
        if let account = store.account(id: entry.accountId) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(account.name)
                            .font(.body)
                            .foregroundStyle(WCTheme.ink)
                        Text("\(store.typeName(id: account.typeId)) · \(entry.currency)")
                            .font(.caption)
                            .foregroundStyle(WCTheme.inkTertiary)
                    }
                    Spacer()
                    Image(systemName: entry.confirmed ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(entry.confirmed ? WCTheme.up : WCTheme.inkFaint)
                }
                HStack {
                    TextField(AppFormatters.inputPlaceholder(for: entry.amount, currency: entry.currency), text: $amountText)
                        .keyboardType(.decimalPad)
                        .font(.body.monospacedDigit())
                        .multilineTextAlignment(.trailing)
                        .focused(focusedEntryId, equals: entry.id)
                    Button {
                        let rawAmount = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
                        store.updateEntry(entry, rawAmount: rawAmount.isEmpty ? entry.amount.description : rawAmount, confirmed: true)
                        amountText = ""
                        focusedEntryId.wrappedValue = nil
                    } label: {
                        Label("确认", systemImage: "checkmark")
                    }
                    .buttonStyle(.borderless)
                }
                Text("折算 \(AppFormatters.money(entry.convertedAmount))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 3)
        }
    }
}
