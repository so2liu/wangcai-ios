import SwiftUI
import WorthSnapShared
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var exportText = ""

    var body: some View {
        List {
            Section("账本") {
                TextField("账本名称", text: Binding(
                    get: { store.data.ledger.name },
                    set: {
                        store.data.ledger.name = $0
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
            Section("同步") {
                Label("本地优先已启用", systemImage: "internaldrive")
                Label("iCloud 私有同步预留", systemImage: "icloud")
                    .foregroundStyle(.secondary)
            }
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
                if let json = try? WorthSnapExporter.json(data: store.data), let text = String(data: json, encoding: .utf8) {
                    ShareLink(item: text, preview: SharePreview("完整备份.json")) {
                        Label("导出 JSON 备份", systemImage: "shippingbox")
                    }
                }
            }
            Section("隐私") {
                Text("月余不连接银行、券商或支付账户；资产数据保存在本机，未来通过用户自己的 iCloud 私有同步。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("关于") {
                Text("月余 WorthSnap")
                Text("V1.0 测试版")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("设置")
    }
}
