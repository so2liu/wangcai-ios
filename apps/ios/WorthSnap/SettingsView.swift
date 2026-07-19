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
            Section {
                if purchases.isPremium {
                    Label("已永久解锁", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(WCTheme.up)
                } else if store.cloud.isParticipant {
                    Label("已通过家庭共享解锁", systemImage: "person.2.fill")
                        .foregroundStyle(WCTheme.up)
                } else {
                    Button {
                        purchases.showPaywall = true
                    } label: {
                        HStack {
                            Label("永久解锁完整功能", systemImage: "sparkles")
                            Spacer()
                            Text(purchases.displayPrice).foregroundStyle(.secondary)
                        }
                    }
                }
                Button("恢复购买") {
                    Task { await purchases.restorePurchases() }
                }
            } header: {
                Text("永久版")
            } footer: {
                Text("免费版支持 5 个账户和 2 个月度快照。永久版为一次性购买，不是订阅。")
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
            familySection
            Section("存储") {
                Label("数据保存在本机", systemImage: "internaldrive")
                    .foregroundStyle(WCTheme.ink)
            }
            .wcRow()
            Section("导出") {
                if purchases.isPremium || store.cloud.isParticipant {
                    ShareLink(item: WorthSnapExporter.summaryCSV(data: store.data), preview: SharePreview("snapshot-summary.csv")) {
                        Label("导出月度汇总（CSV）", systemImage: "square.and.arrow.up")
                    }
                    ShareLink(item: WorthSnapExporter.entriesCSV(data: store.data), preview: SharePreview("snapshot-details.csv")) {
                        Label("导出月度明细（CSV）", systemImage: "square.and.arrow.up")
                    }
                    ShareLink(item: WorthSnapExporter.accountsCSV(data: store.data), preview: SharePreview("accounts.csv")) {
                        Label("导出账户列表（CSV）", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Button("解锁 CSV 导出") { purchases.showPaywall = true }
                }
                if let json = try? WorthSnapStore.encode(store.data), let text = String(data: json, encoding: .utf8) {
                    ShareLink(item: text, preview: SharePreview("worthsnap-backup.json")) {
                        Label("导出完整备份（JSON）", systemImage: "shippingbox")
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
                        Label("导出加入家庭前的备份", systemImage: "person.2.badge.gearshape")
                    }
                }
            }
            .wcRow()
            Section("隐私与支持") {
                NavigationLink("隐私与数据") { PrivacyAndDataView() }
                NavigationLink("使用帮助") { HelpView() }
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
        .listStyle(.insetGrouped)
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

    private var familySection: some View {
        Section {
            NavigationLink {
                MembersView()
            } label: {
                HStack {
                    Label("家庭成员", systemImage: "person.2")
                    Spacer()
                    Text("\(store.activeMembers.count) 人")
                        .foregroundStyle(.secondary)
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
                Label("iCloud 家庭同步", systemImage: "icloud")
            }
            HStack {
                Text("同步状态")
                Spacer()
                Text(syncStatusText).foregroundStyle(.secondary)
            }
            if let lastSyncDate = store.cloud.lastSyncDate {
                HStack {
                    Text("上次同步")
                    Spacer()
                    Text(lastSyncDate, style: .relative).foregroundStyle(.secondary)
                }
            }
            Button("立即同步") {
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
                    Label(store.cloud.isParticipant ? "仅家庭创建者可以邀请成员" : "邀请或管理家庭", systemImage: "person.crop.circle.badge.plus")
                    Spacer()
                    if preparingShare { ProgressView() }
                }
            }
            .disabled(preparingShare || store.cloud.isParticipant)
        } header: {
            Text("家庭")
        } footer: {
            Text("家庭成员可以查看共享账本。账户所有者管理账户信息，指定成员负责确认月度余额。数据保存在家庭创建者的私人 iCloud 数据库中。")
        }
        .wcRow()
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return String(format: String(localized: "版本 %@（%@）"), version, build)
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
            Section("你的财务数据") {
                Label("旺财不会连接银行、券商或支付账户。", systemImage: "hand.raised")
                Label("账本默认只保存在本机。", systemImage: "internaldrive")
                Label("开发者无法看到你的余额和账户名称。", systemImage: "eye.slash")
            }
            Section("iCloud") {
                Text("开启 iCloud 家庭同步后，账本会保存在家庭创建者的私人 iCloud 数据库中，并且只与明确邀请的成员共享。")
            }
            Section("分享备份前") {
                Text("CSV 和 JSON 文件包含敏感财务信息，请谨慎保存和分享。")
            }
            Section("重要说明") {
                Text("旺财是个人记录工具，不提供投资、税务、法律或财务建议。")
            }
        }
        .navigationTitle("隐私与数据")
    }
}

private struct HelpView: View {
    var body: some View {
        List {
            Section("使用方式") {
                Text("添加需要盘点的账户，每月填写并确认一次当前余额，旺财会持续记录净资产变化。")
                Text("信用卡等负债账户，请将当前欠款填写为正数。")
            }
            Section("免费版") {
                Text("可以免费使用 5 个账户并创建 2 个月度快照。达到限制后，已有数据仍然可以查看。")
            }
            Section("购买") {
                Text("永久版是 App Store 非消耗型购买。更换设备或重新安装后，可使用“恢复购买”。")
            }
            Section("需要帮助？") {
                Text("正式发布前需要补充公开的支持网址和联系邮箱。")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("使用帮助")
    }
}
