import Foundation

enum DecimalFormatters {
    static func string(_ value: Decimal?, precision: Int = 3) -> String {
        guard let value else { return "—" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = precision
        formatter.maximumFractionDigits = precision
        formatter.roundingMode = .halfUp
        formatter.locale = .current
        return formatter.string(from: value as NSDecimalNumber) ?? "—"
    }

    static func compact(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.locale = .current
        return formatter.string(from: value as NSDecimalNumber) ?? "0"
    }

    static func decimal(from text: String) -> Decimal? {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = .current
        formatter.generatesDecimalNumbers = true
        return formatter.number(from: text)?.decimalValue
    }
}

enum InputValidator {
    static func validUnits(_ value: Decimal) -> Bool { value >= 0 && value <= 50 }
    static func validGPA(_ value: Decimal) -> Bool { value >= 0 && value <= 4 }
    static func validWeight(_ value: Decimal) -> Bool { value >= 0 && value <= 100 }
    static func validPoints(_ value: Decimal) -> Bool { value >= 0 }
}
