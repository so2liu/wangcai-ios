# WorthSnap / 旺财视觉系统

## 品牌原则

- 温暖但不幼稚：奶油底色与金棕强调，避免传统金融产品的冷蓝和高压红绿。
- 清晰而不炫技：数据优先，装饰不应干扰金额、完成状态和家庭责任。
- 全球与性别中立：不使用人民币/美元符号作为品牌图形，不用男女剪影、粉蓝二分或婚姻称谓。
- 不暗示收益：品牌图标和营销素材不使用持续上涨曲线、火箭或“财富暴增”意象。

## 图标

- 新图标源文件：`docs/design/AppIcon-v2-source.png`，1254×1254。
- 概念：账本/快照容器 + 两个相交的圆表示个人与共同资产 + 确认标记。
- 颜色与 App 内 `WCTheme` 一致。
- 上架前在 Mac 上使用以下命令导出精确 1024×1024 文件，再替换资产目录中的 `AppIcon.png`：

```bash
sips -z 1024 1024 docs/design/AppIcon-v2-source.png \
  --out apps/ios/WorthSnap/Assets.xcassets/AppIcon.appiconset/AppIcon.png
```

- 替换后必须确认：RGB、无透明通道、无外层预制圆角、1024×1024，并在浅色/深色主屏幕与 32px 小尺寸下检查辨识度。

生成方式：内置图像生成工具。最终生成提示核心约束为：暖色奶油金棕、抽象家庭资产快照、无文字、无币种、无人物、无硬币/存钱罐、无上涨图表、完整方形画布。

## 字体层级

统一使用 Apple 系统字体，避免额外字体授权和中英文缺字：

- Hero：34pt、Bold、Rounded，用于首次引导和首页品牌标题。
- Large Number：40pt、Heavy、Rounded，用于净资产核心数字。
- Title：24pt、Bold、Rounded，用于页面主任务。
- Headline：17pt、Semibold、Rounded，用于卡片标题和主按钮。
- Body：16pt、Regular、Rounded，用于说明文字。
- Caption：12pt、Regular、Rounded，用于状态和辅助信息。

代码定义位于 `Theme.swift` 的 `WCTypography`。金额应继续启用等宽数字，支持系统动态字体和 VoiceOver。

## 颜色

- Background：`#FFFDF8`
- Ink：`#2B2118`
- Secondary Ink：`#5C5246`
- Gold：`#C2862F`
- Deep Gold：`#B07A1E`
- Positive / Asset：`#4F7D55`
- Warning / Liability：`#BB5C44`

颜色不能单独承担含义；确认、错误、资产与负债都必须同时有文字或图标。

## 组件

- 主按钮统一使用 `WCPrimaryButtonStyle`：金棕渐变、胶囊形、14pt 垂直内边距。
- 次按钮统一使用 `WCSecondaryButtonStyle`：浅色面、金色细描边。
- 数据卡统一使用 `wcCard`：20pt 连续圆角、细描边、低强度阴影。
- List/Form 统一使用 `wcScreen` 与 `wcRow`，避免系统灰底与品牌首页割裂。
- 破坏性操作必须使用系统 destructive 角色、说明影响并二次确认。

## 家庭共享表达

- 使用“本人 / 其他成员 / 共同”或成员真实姓名，不使用“男方 / 女方”“老公 / 老婆”。
- “归属”只代表账本中的统计归类，不代表法律上的财产权。
- “每月由谁更新”是操作责任，不改变谁能查看家庭账本。
- 只读状态必须同时展示锁图标和文字。
