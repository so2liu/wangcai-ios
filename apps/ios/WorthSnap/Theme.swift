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
    static let background = Color(hex: 0xFAF8F4)
    static let surface = Color.white
    static let surfaceMuted = Color(hex: 0xF5F2EC)
    static let cardStroke = Color(hex: 0xE7E1D8)

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
        colors: [Color.white, Color(hex: 0xFCF7ED)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let creamCard = LinearGradient(
        colors: [Color.white, Color.white],
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

/// 使用系统字体保证中英文、数字和无障碍字号一致；标题采用圆角字形保持品牌温度。
enum WCTypography {
    static let hero = Font.system(size: 34, weight: .bold, design: .rounded)
    static let largeNumber = Font.system(size: 40, weight: .heavy, design: .rounded)
    static let title = Font.system(size: 24, weight: .bold, design: .rounded)
    static let headline = Font.system(size: 17, weight: .semibold, design: .rounded)
    static let body = Font.system(size: 16, weight: .regular, design: .rounded)
    static let caption = Font.system(size: 12, weight: .regular, design: .rounded)
}

enum WCSpacing {
    static let page: CGFloat = 20
    static let section: CGFloat = 24
    static let card: CGFloat = 16
    static let row: CGFloat = 12
}

struct WCPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(WCTypography.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(WCTheme.goldDeep, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct WCSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(WCTypography.headline)
            .foregroundStyle(WCTheme.goldDeep)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(WCTheme.surface.opacity(configuration.isPressed ? 0.72 : 1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(WCTheme.cardStroke, lineWidth: 1))
    }
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
                    .strokeBorder(WCTheme.cardStroke, lineWidth: 1)
            )
            .shadow(color: WCTheme.ink.opacity(0.035), radius: 6, y: 2)
    }
}

struct WCSectionHeader: View {
    let title: LocalizedStringKey
    var detail: LocalizedStringKey?

    init(_ title: LocalizedStringKey, detail: LocalizedStringKey? = nil) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(WCTypography.headline)
                .foregroundStyle(WCTheme.ink)
            Spacer()
            if let detail {
                Text(detail)
                    .font(WCTypography.caption)
                    .foregroundStyle(WCTheme.inkTertiary)
            }
        }
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
        listRowBackground(WCTheme.surface)
    }

    func wcTitle() -> some View {
        font(WCTypography.title).foregroundStyle(WCTheme.ink)
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
        guard parts.count == 2, let year = Int(parts[0]), let value = Int(parts[1]),
              let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: value, day: 1)) else { return month }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("yMMMM")
        return formatter.string(from: date)
    }

    /// "2026-06" → "6月"
    static func shortMonth(_ month: String) -> String {
        let parts = month.split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]), let value = Int(parts[1]),
              let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: value, day: 1)) else { return month }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        return formatter.string(from: date)
    }
}
