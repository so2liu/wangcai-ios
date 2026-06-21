import SwiftUI
import WorthSnapShared

struct RootView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        TabView {
            OverviewView()
                .tabItem { Label("总览", systemImage: "chart.pie.fill") }
            SnapshotView()
                .tabItem { Label("快照", systemImage: "checklist") }
            TrendView()
                .tabItem { Label("趋势", systemImage: "chart.xyaxis.line") }
            AccountsView()
                .tabItem { Label("账户", systemImage: "list.bullet.rectangle") }
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
