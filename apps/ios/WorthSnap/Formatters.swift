import Foundation

enum AppFormatters {
    private static let compactNumber: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        formatter.roundingMode = .halfUp
        return formatter
    }()

    private static let plainNumber: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.roundingMode = .halfUp
        return formatter
    }()

    static func money(_ value: Decimal, currency: String = "CNY") -> String {
        "\(currency) \(readableAmount(value))"
    }

    static func readableAmount(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value).doubleValue
        let absolute = abs(number)
        let sign = number < 0 ? "-" : ""

        if absolute >= 100_000_000 {
            return sign + formatted(absolute / 100_000_000, using: compactNumber) + "亿"
        }
        if absolute >= 10_000 {
            return sign + formatted(absolute / 10_000, using: compactNumber) + "万"
        }
        return formatted(number, using: plainNumber)
    }

    static func inputPlaceholder(for value: Decimal, currency: String) -> String {
        if value == 0 {
            return "输入金额"
        }
        return "当前 \(money(value, currency: currency))"
    }

    static func percent(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value).doubleValue
        return String(format: "%.1f%%", number * 100)
    }

    static func snapshotRecordDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "M 月 d 日记录"
        return formatter.string(from: date)
    }

    private static func formatted(_ value: Double, using formatter: NumberFormatter) -> String {
        formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
    }
}
