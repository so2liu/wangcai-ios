# 月余 iOS

打开 `WorthSnap.xcodeproj`，选择 `WorthSnap` scheme，在 Signing & Capabilities 中选择你的 Apple Developer Team，然后连接 iPhone 运行。

当前测试版实现：

- 总览、快照、趋势、账户、设置 5 个核心界面。
- 本地 JSON 持久化。
- 月度快照创建、复制上月金额、逐项确认与完成状态。
- 账户新增、归档、恢复。
- 金额输入支持小数与 `万`。
- CSV/JSON 分享导出。

iCloud 私有同步已预留产品入口和服务边界，正式接入需要完整 Xcode、Apple Developer Team、CloudKit Container 与真机验证。
