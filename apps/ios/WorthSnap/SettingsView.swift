import SwiftUI
import CloudKit
import WorthSnapShared
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var exportText = ""
    @State private var showImporter = false
    @State private var importError: String?
    @State private var pendingImport: WorthSnapData?
    @State private var familyShare: CKShare?
    @State private var familyContainer: CKContainer?
    @State private var preparingShare = false

    var body: some View {
        List {
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
            }
            .wcRow()
            Section("存储") {
                Label("数据保存在本机", systemImage: "internaldrive")
                    .foregroundStyle(WCTheme.ink)
            }
            .wcRow()
            Section {
                Toggle(isOn: Binding(
                    get: { store.cloud.enabled },
                    set: { on in
                        if on { Task { await store.cloud.enable() } }
                        else { store.cloud.disable() }
                    }
                )) {
                    Label("iCloud 同步", systemImage: "icloud")
                }
                HStack {
                    Text("状态")
                    Spacer()
                    Text(syncStatusText).foregroundStyle(.secondary)
                }
                Button {
                    Task { await prepareShare() }
                } label: {
                    HStack {
                        Label("邀请家人加入", systemImage: "person.crop.circle.badge.plus")
                        Spacer()
                        if preparingShare { ProgressView() }
                    }
                }
                .disabled(preparingShare)
            } header: {
                Text("家庭共享")
            } footer: {
                Text("开启后家庭账本通过你的 iCloud 私有库同步给受邀成员，数据不经第三方服务器。邀请通过 AirDrop / 信息 / 二维码发送。")
            }
            .wcRow()
            Section("导出") {
                ShareLink(item: WorthSnapExporter.summaryCSV(data: store.data), preview: SharePreview("快照汇总.csv")) {
                    Label("导出快照汇总 CSV", systemImage: "square.and.arrow.up")
                }
                ShareLink(item: WorthSnapExporter.entriesCSV(data: store.data), preview: SharePreview("快照明细.csv")) {
                    Label("导出快照明细 CSV", systemImage: "square.and.arrow.up")
                }
                ShareLink(item: WorthSnapExporter.accountsCSV(data: store.data), preview: SharePreview("账户列表.csv")) {
                    Label("导出账户 CSV", systemImage: "square.and.arrow.up")
                }
                if let json = try? WorthSnapStore.encode(store.data), let text = String(data: json, encoding: .utf8) {
                    ShareLink(item: text, preview: SharePreview("完整备份.json")) {
                        Label("导出 JSON 备份", systemImage: "shippingbox")
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
            }
            .wcRow()
            Section("隐私") {
                Text("旺财不连接银行、券商或支付账户；资产数据目前仅保存在本机。iCloud 私有同步为后续计划，启用前数据不会离开你的设备。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .wcRow()
            Section("关于") {
                Text("旺财")
                Text("版本 1.0")
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
