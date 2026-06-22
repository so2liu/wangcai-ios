import SwiftUI

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

/// 旺财暖色（奶油 + 金棕）主题，对齐 `旺财 App.dc.html` 设计稿。
enum WCTheme {
    // 背景与卡面
    static let background = Color(hex: 0xFFFDF8)
    static let cardStroke = Color.white.opacity(0.55)

    // 文字层级
    static let ink = Color(hex: 0x2B2118)
    static let inkSecondary = Color(hex: 0x5C5246)
    static let inkTertiary = Color(hex: 0x94897A)
    static let inkFaint = Color(hex: 0xA89C8A)

    // 金棕强调
    static let gold = Color(hex: 0xC2862F)
    static let goldDeep = Color(hex: 0xB07A1E)
    static let goldText = Color(hex: 0x9A6614)

    // 涨跌
    static let up = Color(hex: 0x4F7D55)
    static let down = Color(hex: 0xBB5C44)

    // 渐变
    static let netCard = LinearGradient(
        colors: [Color(hex: 0xFFFDF8), Color(hex: 0xFBF2DE)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let creamCard = LinearGradient(
        colors: [Color(hex: 0xFBF2DE), Color(hex: 0xEFE6CE)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let goldFill = LinearGradient(
        stops: [
            .init(color: Color(hex: 0xE6B24A), location: 0),
            .init(color: Color(hex: 0xC2862F), location: 0.55),
            .init(color: Color(hex: 0xA66C1C), location: 1)
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

/// 暖色玻璃卡片：圆角 + 渐变填充 + 细描边 + 柔和金色投影。
struct WCCard: ViewModifier {
    var fill: LinearGradient = WCTheme.creamCard
    var radius: CGFloat = 20
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(WCTheme.cardStroke, lineWidth: 0.5)
            )
            .shadow(color: WCTheme.gold.opacity(0.10), radius: 14, y: 5)
    }
}

extension View {
    func wcCard(fill: LinearGradient = WCTheme.creamCard, radius: CGFloat = 20, padding: CGFloat = 16) -> some View {
        modifier(WCCard(fill: fill, radius: radius, padding: padding))
    }

    /// 给 List / Form 套上奶油背景（隐藏系统灰底），让全 App 色调统一。
    func wcScreen() -> some View {
        scrollContentBackground(.hidden)
            .background(WCTheme.background.ignoresSafeArea())
    }

    /// List / Form 行的统一米色背景。
    func wcRow() -> some View {
        listRowBackground(Color.white.opacity(0.5))
    }
}

extension AppFormatters {
    /// 币种符号：CNY → ¥、USD → $ 等，未知则回退到币种代码。
    static func symbol(for currency: String) -> String {
        switch currency.uppercased() {
        case "CNY", "RMB": return "¥"
        case "USD": return "$"
        case "EUR": return "€"
        case "JPY": return "¥"
        case "GBP": return "£"
        case "HKD": return "HK$"
        default: return currency.uppercased() + " "
        }
    }

    /// 带币种符号的金额，如「¥352.8万」。
    static func symbolized(_ value: Decimal, currency: String) -> String {
        symbol(for: currency) + readableAmount(value)
    }

    /// 把比例（0.153）格式化为带箭头与符号的涨跌文案，如「▲ 15.3%」。
    static func signedPercent(_ ratio: Double) -> String {
        let arrow = ratio > 0 ? "▲" : (ratio < 0 ? "▼" : "•")
        return String(format: "%@ %.1f%%", arrow, abs(ratio) * 100)
    }

    /// 涨跌配色。`inverted` 用于负债：负债**增加**是警示（红），减少是改善（绿），与资产相反。
    static func changeColor(_ ratio: Double, inverted: Bool = false) -> Color {
        let sentiment = inverted ? -ratio : ratio
        return sentiment > 0 ? WCTheme.up : (sentiment < 0 ? WCTheme.down : WCTheme.inkTertiary)
    }

    /// "2026-06" → "2026 年 6 月"
    static func monthTitle(_ month: String) -> String {
        let parts = month.split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]), let m = Int(parts[1]) else { return month }
        return "\(year) 年 \(m) 月"
    }

    /// "2026-06" → "6月"
    static func shortMonth(_ month: String) -> String {
        let parts = month.split(separator: "-")
        guard parts.count == 2, let m = Int(parts[1]) else { return month }
        return "\(m)月"
    }
}
