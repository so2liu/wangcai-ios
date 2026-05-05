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
        .tint(.teal)
    }
}
