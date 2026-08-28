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

    /// Localizes only the generated term name. Student-authored custom names
    /// remain verbatim so localization never changes personal data.
    static func termName(_ term: AcademicTerm, locale: Locale) -> String {
        guard isChinese(locale) else { return term.displayName }

        let year = (term.academicYear.components(separatedBy: CharacterSet(charactersIn: "–-"))).first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let generatedName = "\(term.termType.rawValue) \(year)"
        guard !year.isEmpty, term.displayName == generatedName else { return term.displayName }

        let localizedTerm = AppLocalization.string(term.termType.rawValue, locale: locale)
        return "\(year) \(localizedTerm)"
    }

    static func targetDelta(_ delta: Decimal, locale: Locale) -> String {
        if delta == 0 {
            return isChinese(locale) ? "已达到目标" : "At target"
        }

        if isChinese(locale) {
            let amount = DecimalFormatters.compact(abs(delta))
            return delta > 0 ? "高于目标 \(amount)" : "距离目标还差 \(amount)"
        }

        let prefix = delta > 0 ? "+" : ""
        return "\(prefix)\(DecimalFormatters.compact(delta)) to target"
    }

    static func points(_ points: Decimal, locale: Locale) -> String {
        let value = DecimalFormatters.compact(points)
        return isChinese(locale) ? "\(value) 点" : "\(value) points"
    }

    static func voiceEntryNote(locale: Locale) -> String {
        isChinese(locale)
            ? "此版本暂不使用麦克风。请输入你想说的内容，先预览再添加。"
            : "Microphone access is not available in this build. Type what you would say, then preview it before adding."
    }

    static func voiceEntryUnavailableTitle(locale: Locale) -> String {
        isChinese(locale) ? "语音输入暂不可用" : "Voice entry isn’t available yet"
    }

    static func voiceEntryUnavailableMessage(locale: Locale) -> String {
        isChinese(locale)
            ? "此版本暂不使用麦克风。你仍可以输入转写内容，检查后继续添加。"
            : "This build does not use the microphone yet. You can still enter a transcript, review it, and continue to Quick Add."
    }

    static func storeRecoveryMessage(
        preparationFailed: Bool,
        locale: Locale,
        detail: String? = nil
    ) -> String {
        if isChinese(locale) {
            if preparationFailed {
                return "无法安全准备本地 Siri 数据。你的原始数据没有被删除或替换。请关闭 App，并保留迁移备份后再试。"
            }
            return "无法安全打开或迁移本地数据。你的原始数据没有被删除或替换。请关闭 App，并保留迁移备份后再试。"
        }

        if preparationFailed {
            let suffix = detail.map { " \($0)" } ?? ""
            return "Aggie GPA could not safely prepare the local Siri data store. Your original data was not deleted or replaced.\(suffix)"
        }
        return "Aggie GPA could not safely open or migrate your local data. The original store was not deleted or replaced. Close the app and keep the migration backup before trying again."
    }
}
