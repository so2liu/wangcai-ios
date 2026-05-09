import SwiftUI
import WorthSnapShared
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var exportText = ""
    @State private var notificationMessage: String?

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
            Section("快照提醒") {
                Toggle("每月提醒", isOn: Binding(
                    get: { store.data.monthlyReminder.isEnabled },
                    set: { enabled in
                        Task {
                            let scheduled = await store.setMonthlyReminderEnabled(enabled)
                            if enabled && !scheduled {
                                notificationMessage = "已保存配置，但因无通知权限不会触发提醒，可在系统设置中开启"
                            }
                        }
                    }
                ))

                Picker("日期", selection: Binding(
                    get: { store.data.monthlyReminder.day.rawStorageValue },
                    set: { value in
                        if value == "last" {
                            store.updateMonthlyReminderDay(.lastDay)
                        } else if let day = Int(value.replacingOccurrences(of: "day:", with: "")) {
                            store.updateMonthlyReminderDay(.day(day))
                        }
                    }
                )) {
                    ForEach(1...28, id: \.self) { day in
                        Text("\(day) 日").tag("day:\(day)")
                    }
                    Text("最后一天").tag("last")
                }

                DatePicker("时刻", selection: Binding(
                    get: { reminderTimeDate },
                    set: { date in
                        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
                        store.updateMonthlyReminderTime(hour: comps.hour ?? 20, minute: comps.minute ?? 0)
                    }
                ), displayedComponents: .hourAndMinute)

                Text("通知会根据当前完成状态只注册下一次提醒。")
                    .font(.footnote)
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
                Text("旺财不连接银行、券商或支付账户；资产数据保存在本机，未来通过用户自己的 iCloud 私有同步。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("关于") {
                Text("旺财")
                Text("V1.0 测试版")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("设置")
        .alert("通知权限未开启", isPresented: Binding(
            get: { notificationMessage != nil },
            set: { if !$0 { notificationMessage = nil } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(notificationMessage ?? "")
        }
    }

    private var reminderTimeDate: Date {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = store.data.monthlyReminder.hour
        comps.minute = store.data.monthlyReminder.minute
        return Calendar.current.date(from: comps) ?? Date()
    }
}
