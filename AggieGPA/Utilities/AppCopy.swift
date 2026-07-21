import Foundation

enum AppCopy {
    static func isChinese(_ locale: Locale) -> Bool {
        locale.identifier.lowercased().hasPrefix("zh")
    }

    static func greeting(name: String, locale: Locale) -> String {
        guard !name.isEmpty else { return isChinese(locale) ? "首页" : "Dashboard" }
        return isChinese(locale) ? "你好，\(name)" : "Hi, \(name)"
    }

    static func units(_ units: Decimal, locale: Locale, gpa: Bool = false) -> String {
        let value = DecimalFormatters.compact(units)
        if isChinese(locale) { return gpa ? "\(value) GPA 学分" : "\(value) 学分" }
        return gpa ? "\(value) GPA units" : "\(value) units"
    }

    static func gradePoints(_ points: Decimal, locale: Locale) -> String {
        let value = DecimalFormatters.compact(points)
        return isChinese(locale) ? "\(value) 成绩点" : "\(value) grade points"
    }

    static func currentGPA(_ value: String, locale: Locale) -> String {
        isChinese(locale) ? "当前 \(value)" : "Current \(value)"
    }

    static func targetGPA(_ value: String, locale: Locale) -> String {
        isChinese(locale) ? "目标 \(value)" : "Target \(value)"
    }

    static func termSummary(units: Decimal, courseCount: Int, locale: Locale) -> String {
        let unitText = self.units(units, locale: locale, gpa: true)
        let courseText = isChinese(locale) ? "\(courseCount) 门课程" : "\(courseCount) courses"
        return "\(unitText) · \(courseText)"
    }

    static func points(_ points: Decimal, locale: Locale) -> String {
        let value = DecimalFormatters.compact(points)
        return isChinese(locale) ? "\(value) 点" : "\(value) points"
    }
}
