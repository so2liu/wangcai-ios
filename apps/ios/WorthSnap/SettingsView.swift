import SwiftUI
import CloudKit
import WorthSnapShared
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var purchases: PurchaseManager
    @State private var exportText = ""
    @State private var showImporter = false
    @State private var importError: String?
    @State private var pendingImport: WorthSnapData?
    @State private var familyShare: CKShare?
    @State private var familyContainer: CKContainer?
    @State private var preparingShare = false

    var body: some View {
        List {
            Section("WorthSnap Lifetime") {
                if purchases.isPremium {
                    Label("Lifetime access unlocked", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(WCTheme.up)
                } else if store.cloud.isParticipant {
                    Label("Full access through a shared family", systemImage: "person.2.fill")
                        .foregroundStyle(WCTheme.up)
                } else {
                    Button {
                        purchases.showPaywall = true
                    } label: {
                        HStack {
                            Label("Unlock the full app", systemImage: "sparkles")
                            Spacer()
                            Text(purchases.displayPrice).foregroundStyle(.secondary)
                        }
                    }
                }
                Button("Restore Purchase") {
                    Task { await purchases.restorePurchases() }
                }
            } footer: {
                Text("The free version includes up to 5 accounts and 2 monthly snapshots. Lifetime access is a one-time purchase, not a subscription.")
            }
            .wcRow()
            Section("账本") {
                TextField("账本名称", text: Binding(
                    get: { store.data.ledger.name },
                    set: {
                        store.data.ledger.name = $0
                        // 必须 bump updatedAt：同步按 updatedAt 算增量，否则账本改名永远不会推给其他设备。
                        store.data.ledger.updatedAt = Date()
                        store.save()
                    }
                ))
                .keyboardDismissToolbar()
                HStack {
                    Text("本位币")
                    Spacer()
                    Text(store.data.ledger.baseCurrency)
                        .foregroundStyle(.secondary)
                }
            }
            .wcRow()
            Section("家庭") {
                NavigationLink {
                    MembersView()
                } label: {
                    HStack {
                        Label("家庭成员", systemImage: "person.2")
                        Spacer()
                        Text("\(store.activeMembers.count) 人").foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: Binding(
                    get: { store.cloud.enabled },
                    set: { on in
                        guard purchases.isPremium || store.cloud.isParticipant else {
                            purchases.showPaywall = true
                            return
                        }
                        if on { Task { await store.cloud.enable() } }
                        else { store.cloud.disable() }
                    }
                )) {
                    Label("iCloud Family Sync", systemImage: "icloud")
                }
                HStack {
                    Text("Sync Status")
                    Spacer()
                    Text(syncStatusText).foregroundStyle(.secondary)
                }
                if let lastSyncDate = store.cloud.lastSyncDate {
                    HStack {
                        Text("Last Synced")
                        Spacer()
                        Text(lastSyncDate, style: .relative).foregroundStyle(.secondary)
                    }
                }
                Button("Sync Now") {
                    Task { await store.cloud.syncNow() }
                }
                .disabled(!store.cloud.enabled)
                Button {
                    guard purchases.isPremium else {
                        purchases.showPaywall = true
                        return
                    }
                    Task { await prepareShare() }
                } label: {
                    HStack {
                        Label(store.cloud.isParticipant ? "Only the family owner can invite members" : "Invite or Manage Family", systemImage: "person.crop.circle.badge.plus")
                        Spacer()
                        if preparingShare { ProgressView() }
                    }
                }
                .disabled(preparingShare || store.cloud.isParticipant)
            } footer: {
                Text("Family members can view the shared ledger. Account owners manage account details, while the assigned updater confirms the monthly balance. Data is stored in the family owner's private iCloud database.")
            }
            .wcRow()
            Section("存储") {
                Label("数据保存在本机", systemImage: "internaldrive")
                    .foregroundStyle(WCTheme.ink)
            }
            .wcRow()
            Section("导出") {
                if purchases.isPremium || store.cloud.isParticipant {
                    ShareLink(item: WorthSnapExporter.summaryCSV(data: store.data), preview: SharePreview("snapshot-summary.csv")) {
                        Label("Export snapshot summary (CSV)", systemImage: "square.and.arrow.up")
                    }
                    ShareLink(item: WorthSnapExporter.entriesCSV(data: store.data), preview: SharePreview("snapshot-details.csv")) {
                        Label("Export snapshot details (CSV)", systemImage: "square.and.arrow.up")
                    }
                    ShareLink(item: WorthSnapExporter.accountsCSV(data: store.data), preview: SharePreview("accounts.csv")) {
                        Label("Export accounts (CSV)", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Button("Unlock CSV export") { purchases.showPaywall = true }
                }
                if let json = try? WorthSnapStore.encode(store.data), let text = String(data: json, encoding: .utf8) {
                    ShareLink(item: text, preview: SharePreview("worthsnap-backup.json")) {
                        Label("Export complete backup (JSON)", systemImage: "shippingbox")
                    }
                }
            }
            .wcRow()
            Section("恢复") {
                Button {
                    showImporter = true
                } label: {
                    Label("从 JSON 备份恢复", systemImage: "square.and.arrow.down")
                }
                Text("导入会用备份覆盖当前全部数据，导入前会再次确认。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let familyBackup = store.familyJoinBackupURL {
                    ShareLink(item: familyBackup) {
                        Label("Export pre-family backup", systemImage: "person.2.badge.gearshape")
                    }
                }
            }
            .wcRow()
            Section("Privacy and Support") {
                NavigationLink("Privacy and Data") { PrivacyAndDataView() }
                NavigationLink("Help") { HelpView() }
            }
            .wcRow()
            Section("关于") {
                Text("WorthSnap · 旺财")
                Text(appVersion)
                    .foregroundStyle(.secondary)
            }
            .wcRow()
        }
        .wcScreen()
        .tint(WCTheme.goldDeep)
        .navigationTitle("设置")
        .sheet(isPresented: Binding(
            get: { familyShare != nil && familyContainer != nil },
            set: { if !$0 { familyShare = nil; familyContainer = nil } }
        )) {
            if let share = familyShare, let container = familyContainer {
                FamilyShareSheet(share: share, container: container)
                    .ignoresSafeArea()
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    let raw = try Data(contentsOf: url)
                    pendingImport = try WorthSnapStore.decode(raw)
                } catch {
                    importError = "无法读取该备份，文件可能损坏或不是旺财备份。"
                }
            case .failure(let error):
                importError = error.localizedDescription
            }
        }
        .alert("用备份覆盖当前数据？", isPresented: Binding(
            get: { pendingImport != nil },
            set: { if !$0 { pendingImport = nil } }
        )) {
            Button("取消", role: .cancel) { pendingImport = nil }
            Button("覆盖并恢复", role: .destructive) {
                if let data = pendingImport { store.replaceAll(with: data) }
                pendingImport = nil
            }
        } message: {
            Text("当前账本、账户与所有快照会被备份内容替换，且无法撤销。")
        }
        .alert("导入失败", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("好", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return String(format: String(localized: "Version %@ (%@)"), version, build)
    }

    private var syncStatusText: String {
        switch store.cloud.status {
        case .off: return "未开启"
        case .syncing: return "同步中…"
        case .idle: return "已同步"
        case .error(let message): return message
        }
    }

    /// 准备共享对象并弹出系统邀请界面。
    private func prepareShare() async {
        preparingShare = true
        defer { preparingShare = false }
        do {
            let (share, container) = try await store.cloud.makeShare()
            familyShare = share
            familyContainer = container
        } catch {
            importError = "创建共享失败：\(error.localizedDescription)"
        }
    }
}

private struct PrivacyAndDataView: View {
    var body: some View {
        List {
            Section("Your financial data") {
                Label("WorthSnap never connects to your bank, broker, or payment accounts.", systemImage: "hand.raised")
                Label("Your ledger is stored locally on this device by default.", systemImage: "internaldrive")
                Label("The developer cannot see your balances or account names.", systemImage: "eye.slash")
            }
            Section("iCloud") {
                Text("If you enable iCloud family sync, the ledger is stored in the family owner's private iCloud database and shared only with people the owner explicitly invites. Invited members can view the shared ledger; editing follows account ownership and monthly updater assignments.")
            }
            Section("Before sharing a backup") {
                Text("CSV and JSON exports contain sensitive financial information. Store and share them carefully.")
            }
            Section("Important") {
                Text("WorthSnap is a personal record-keeping tool. It does not provide investment, tax, legal, or financial advice.")
            }
        }
        .navigationTitle("Privacy and Data")
    }
}

private struct HelpView: View {
    var body: some View {
        List {
            Section("How it works") {
                Text("Add the accounts you want to review, enter each current balance, and confirm them once a month. WorthSnap tracks the resulting net worth over time.")
                Text("For liabilities such as credit cards, enter the amount currently owed as a positive number.")
            }
            Section("Free version") {
                Text("You can use up to 5 accounts and create 2 monthly snapshots for free. Your existing data remains readable if you reach the limit.")
            }
            Section("Purchases") {
                Text("Lifetime access is a non-consumable App Store purchase. Use Restore Purchase after changing devices or reinstalling the app.")
            }
            Section("Need assistance?") {
                Text("A public support URL and contact address must be added before the App Store release.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Help")
    }
}
