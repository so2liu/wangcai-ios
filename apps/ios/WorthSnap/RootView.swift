import SwiftUI
import WorthSnapShared

struct RootView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        TabView(selection: $store.selectedTab) {
            OverviewView()
                .tabItem { Label("总览", systemImage: "chart.pie.fill") }
                .tag(AppTab.overview)
            SnapshotView()
                .tabItem { Label("快照", systemImage: "checklist") }
                .tag(AppTab.snapshot)
            TrendView()
                .tabItem { Label("趋势", systemImage: "chart.xyaxis.line") }
                .tag(AppTab.trend)
            AccountsView()
                .tabItem { Label("账户", systemImage: "list.bullet.rectangle") }
                .tag(AppTab.accounts)
        }
        .tint(.teal)
    }
}
