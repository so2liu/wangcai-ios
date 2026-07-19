# WorthSnap / 旺财 App Store 发布清单

## 产品与付费

- 发布方式：免费下载。
- 免费范围：最多 5 个账户、2 个月度快照；达到限制后已有数据仍可读取和编辑。
- 完整版：非消耗型应用内购买，一次购买、永久解锁，不自动续费。JSON 数据备份与恢复不设付费墙，避免以用户数据安全强迫购买。
- StoreKit Product ID：`com.yueyu.WorthSnap.lifetime`。
- 在 App Store Connect 创建 Non-Consumable 产品，并为简体中文和英文分别填写显示名称、说明和审核截图。
- 必须用 Sandbox Apple Account 完成：购买成功、用户取消、待批准、断网、退款撤销、换机恢复购买测试。

## 个人开发者账户

- 在 App Store Connect 的 Business / Agreements 中签署 Paid Apps Agreement。
- 完成银行账户和税务信息；所有开发者都需要按 App Store Connect 提示完成适用的美国税务表格，所在地区可能还有额外表格。
- 若面向欧盟收费发行，需要自行判断 DSA trader 身份。收费和应用内购买通常是需要认真评估的商业活动信号。
- 个人开发者如申报为欧盟 trader，Apple 会要求验证并公开地址或邮政信箱、电话和邮箱。建议在上架前准备专用客服邮箱、电话和可验证的通信地址，避免直接公开日常私人联系方式。

## 中国大陆

- 在 App Store Connect 检查“中国大陆供应情况”，确认是否要求 App/ICP 备案号。
- 备案主体信息、App 中文名、Bundle ID、简体中文元数据需保持一致。
- 当前产品是个人资产记录工具，不应宣传成银行、证券交易、投资顾问、贷款或收益承诺服务。
- 如备案或个人主体资格在实际办理中受限，可先发布其他国家和地区；中国大陆待材料完成后单独开放，不应填写虚假备案信息。

## 隐私与合规

- 上架前必须将 `docs/privacy-policy.md` 发布到可公开访问的 HTTPS 网页，并把真实 URL 填入 App Store Connect。
- 必须提供真实 Support URL 和可联系的客服邮箱。
- App Privacy 应按实际版本填写。当前设计下，资产数据只在设备和用户自己的 iCloud 中处理；不得因为“本地优先”而忽略新增的分析或崩溃 SDK。
- 不接入广告、跨 App 跟踪或会读取资产金额的第三方分析 SDK。
- CSV/JSON 导出含敏感财务信息，App 内已提示用户谨慎保存和分享。
- App 只使用 Apple 系统提供的加密能力，工程已声明 `ITSAppUsesNonExemptEncryption = NO`；提交前仍应根据当时 App Store Connect 问卷再次确认。
- 产品必须明确：仅作个人记录，不提供投资、税务、法律或财务建议。

## 多语言与市场

- App 二进制首发支持：简体中文、英文。
- App Store 商品页也要分别建立简体中文和英文元数据、关键词与截图；App 内翻译不会自动生成商品页翻译。
- 英文建议作为 App Store Connect Primary Language，简体中文作为完整本地化；没有匹配语言的市场会回退到英文。
- 新用户的本位币按设备地区初始化，并可在首次建账前修改。
- 金额、月份和 StoreKit 价格必须使用系统地区格式，不手写固定人民币价格。

## 构建与审核

- 用 macOS 最新稳定版 Xcode 打开 `apps/ios/WorthSnap.xcodeproj`。
- 确认 Bundle ID、iCloud Container 和开发者账户属于同一 Apple Developer Team。
- 家庭共享是首发核心能力；Release 前必须完成 `docs/cloudkit-sharing-testing.md` 的两台真机、两个 iCloud 账号全量验收。
- 发起者需要永久版才能创建共享家庭；受邀成员加入家庭后获得该家庭内完整使用权限，不重复收费。
- 加入家庭前会自动生成个人账本 JSON 备份；必须验证备份可导出、可恢复。
- 上传 Archive 前确认 Distribution Profile 中 `aps-environment` 为 `production`，不要把开发推送权限带入发布包。
- 在真机测试中英文、小屏和大屏、浅色对比度、大字体、VoiceOver、离线模式及数据恢复。
- 先通过 TestFlight 内部测试，再邀请外部测试用户。
- App Review Notes 说明：无需登录；首次启动可直接完成免费体验；永久版购买入口位于设置和免费限制页；审核员可使用 Sandbox 测试内购。

## 发布前仍需由开发者提供

- 最终中文名与英文名的商标/重名确认。
- 公开隐私政策 URL。
- Support URL、客服邮箱和必要的联系电话。
- 个人收款银行资料和税务资料。
- 中国大陆备案结果（如 App Store Connect 对该 App 要求）。
- 欧盟 DSA trader 自评与公开联系信息。
- 永久版实际价格及各地区可售范围。
