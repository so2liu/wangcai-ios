import SwiftUI
import WorthSnapShared

/// 家庭成员管理：新增、改名、移除（归档）。
/// 移除遵循「人走数据留」——归档成员不删除其归属/负责的账户与历史，负责账户转交本人。
/// 多人共享由设置页的 iCloud 家庭同步提供。
struct MembersView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingAdd = false
    @State private var newName = ""
    @State private var renaming: Member?
    @State private var renameText = ""
    @State private var pendingArchive: Member?

    var body: some View {
        List {
            Section {
                ForEach(store.activeMembers) { member in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color(hex: member.colorHex))
                            .frame(width: 10, height: 10)
                        Text(member.name)
                            .font(.headline)
                            .foregroundStyle(WCTheme.ink)
                        if member.id == store.data.currentMemberId {
                            Text("我")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(WCTheme.goldText)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(WCTheme.gold.opacity(0.14), in: Capsule())
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        renameText = member.name
                        renaming = member
                    }
                    .wcRow()
                    .swipeActions {
                        if member.id != store.data.currentMemberId {
                            Button("移除") { pendingArchive = member }
                                .tint(WCTheme.down)
                        }
                    }
                }
            } footer: {
                Text("移除成员不会删除其录入的账户和历史（人走数据留）；其负责的账户会转交给你。")
            }
            .wcRow()
        }
        .wcScreen()
        .navigationTitle("家庭成员")
        .toolbar {
            Button {
                newName = ""
                showingAdd = true
            } label: {
                Image(systemName: "plus")
            }
        }
        .alert("添加成员", isPresented: $showingAdd) {
            TextField("成员名称", text: $newName)
            Button("取消", role: .cancel) {}
            Button("添加") { store.addMember(name: newName) }
        } message: {
            Text("这里添加的是账本中的成员资料；跨设备共享需在设置页开启 iCloud 家庭同步并发送邀请。")
        }
        .alert("重命名成员", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )) {
            TextField("成员名称", text: $renameText)
            Button("取消", role: .cancel) { renaming = nil }
            Button("保存") {
                if let member = renaming { store.renameMember(member, to: renameText) }
                renaming = nil
            }
        }
        .alert("移除成员？", isPresented: Binding(
            get: { pendingArchive != nil },
            set: { if !$0 { pendingArchive = nil } }
        )) {
            Button("取消", role: .cancel) { pendingArchive = nil }
            Button("移除", role: .destructive) {
                if let member = pendingArchive { store.archiveMember(member) }
                pendingArchive = nil
            }
        } message: {
            Text("\(pendingArchive?.name ?? "该成员")名下的账户和历史会保留，其负责的账户转交给你。")
        }
    }
}

private extension Color {
    /// 从 "RRGGBB" 十六进制字符串构造颜色；非法值回退到品牌金。
    init(hex: String) {
        var value: UInt64 = 0
        guard Scanner(string: hex).scanHexInt64(&value), hex.count == 6 else {
            self = WCTheme.gold
            return
        }
        self = Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
