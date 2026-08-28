import Foundation

nonisolated enum NaturalLanguageQuickAddSource: String, Codable, Sendable {
    case localModel
    case deterministicFallback
}

nonisolated struct NaturalLanguageQuickAddDraft: Codable, Equatable, Sendable, Identifiable {
    var courseCode: String
    var title: String
    var type: GradeCategoryType
    var dueDate: Date?
    var possiblePoints: Decimal?
    var categoryName: String?
    var reminderLeadTimeHours: Int?
    var confidence: Double
    var source: NaturalLanguageQuickAddSource
    var warnings: [String]

    var id: String {
        [courseCode, title, dueDate?.description ?? "", possiblePoints.map(String.init) ?? ""].joined(separator: "|")
    }

    var isReadyForConfirmation: Bool {
        !courseCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && dueDate != nil
            && possiblePoints != nil
    }
}

nonisolated struct NaturalLanguageQuickAddPayload: Codable, Equatable, Sendable {
    var courseCode: String
    var title: String
    var type: String
    var dueDate: String?
    var dueTime: String?
    var points: Decimal?
    var category: String?
    var reminderLeadTimeHours: Int?
    var confidence: Double
}

/// The manual parser is intentionally small and predictable. It handles the
/// two documented English/Simplified Chinese examples and leaves missing
/// fields visible in the preview instead of guessing them.
nonisolated enum NaturalLanguageQuickAddParser {
    static func parse(
        _ input: String,
        referenceDate: Date = .now,
        availableCourseCodes: [String] = []
    ) -> NaturalLanguageQuickAddDraft {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let courseCode = matchedCourseCode(in: trimmed, availableCourseCodes: availableCourseCodes)
        let type = inferType(from: trimmed)
        let dueDate = dueDate(in: trimmed, referenceDate: referenceDate)
        let dueTime = dueTime(in: trimmed)
        let combinedDueDate = combine(date: dueDate, time: dueTime, calendar: .autoupdatingCurrent)
        let points = decimalMatch(in: trimmed, pattern: #"(?i)(\d+(?:\.\d+)?)\s*(?:points?|pts?|分|分数)"#)
        let reminder = reminderHours(in: trimmed)
        let title = title(in: trimmed, courseCode: courseCode, type: type)
        var warnings: [String] = []
        if courseCode == nil { warnings.append("Course was not identified.") }
        if title.isEmpty { warnings.append("Assignment title is missing.") }
        if combinedDueDate == nil { warnings.append("A weekday or calendar date is required.") }
        if points == nil { warnings.append("Possible points are missing.") }
        if reminder == nil { warnings.append("Reminder timing is not set.") }

        return NaturalLanguageQuickAddDraft(
            courseCode: courseCode ?? "",
            title: title,
            type: type,
            dueDate: combinedDueDate,
            possiblePoints: points,
            categoryName: defaultCategory(for: type),
            reminderLeadTimeHours: reminder,
            confidence: confidence(warnings: warnings, title: title),
            source: .deterministicFallback,
            warnings: warnings
        )
    }

    static func fromModelPayload(
        _ payload: NaturalLanguageQuickAddPayload,
        referenceDate: Date,
        availableCourseCodes: [String]
    ) throws -> NaturalLanguageQuickAddDraft {
        let courseCode = matchedCourseCode(in: payload.courseCode, availableCourseCodes: availableCourseCodes)
            ?? payload.courseCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = payload.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !courseCode.isEmpty, !title.isEmpty else { throw QuickAddError.invalidModelPayload }
        let type = type(from: payload.type, fallbackText: title)
        let date = parseDate(payload.dueDate, referenceDate: referenceDate)
        let time = parseTime(payload.dueTime)
        let combined = combine(date: date, time: time, calendar: .autoupdatingCurrent)
        var warnings: [String] = []
        if combined == nil { warnings.append("A weekday or calendar date is required.") }
        if payload.points == nil { warnings.append("Possible points are missing.") }
        if payload.reminderLeadTimeHours == nil { warnings.append("Reminder timing is not set.") }
        return NaturalLanguageQuickAddDraft(
            courseCode: courseCode,
            title: title,
            type: type,
            dueDate: combined,
            possiblePoints: payload.points,
            categoryName: {
                let value = payload.category?.trimmingCharacters(in: .whitespacesAndNewlines)
                return value?.isEmpty == false ? value : defaultCategory(for: type)
            }(),
            reminderLeadTimeHours: payload.reminderLeadTimeHours,
            confidence: min(1, max(0, payload.confidence)),
            source: .localModel,
            warnings: warnings
        )
    }

    static func defaultCategory(for type: GradeCategoryType) -> String {
        switch type {
        case .homework: "Homework"
        case .quiz: "Quizzes"
        case .lab: "Labs"
        case .midterm: "Midterms"
        case .finalExam: "Final Exam"
        case .project: "Projects"
        default: "Homework"
        }
    }

    private static func matchedCourseCode(in input: String, availableCourseCodes: [String]) -> String? {
        let upper = input.uppercased()
        if let exact = availableCourseCodes.first(where: { containsWholeCode($0, in: upper) }) { return exact }
        if let prefix = availableCourseCodes.first(where: { code in
            let token = code.split(separator: " ").first.map(String.init) ?? code
            return containsWholeCode(token, in: upper)
        }) { return prefix }
        let pattern = #"\b[A-Z]{2,5}(?:\s+\d{2,4}[A-Z]?)?\b"#
        return firstMatch(in: upper, pattern: pattern)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func containsWholeCode(_ code: String, in input: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: code.uppercased().trimmingCharacters(in: .whitespacesAndNewlines))
        return input.range(of: "(?<![A-Z0-9])\(escaped)(?![A-Z0-9])", options: .regularExpression) != nil
    }

    private static func title(in input: String, courseCode: String?, type: GradeCategoryType) -> String {
        var working = input
        if let courseCode, let range = working.range(of: courseCode, options: [.caseInsensitive, .diacriticInsensitive]) {
            working.removeSubrange(range)
        } else {
            let prefix = courseCode?.split(separator: " ").first.map(String.init)
                ?? working.split(whereSeparator: { $0 == " " || $0 == "\u{3000}" }).first.map(String.init)
            if let prefix, working.lowercased().hasPrefix(prefix.lowercased()) {
                working = String(working.dropFirst(prefix.count))
            }
        }
        let markers = [
            #"(?i)\b(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday|today|tomorrow)\b"#,
            #"(?:周[一二三四五六日天]|今天|明天)"#,
            #"\b20\d{2}[-/]\d{1,2}[-/]\d{1,2}\b"#,
            #"(?i)\b(?:at\s+)?\d{1,2}:\d{2}\s*(?:am|pm)?\b"#,
            #"\d{1,2}:\d{2}"#,
            #"(?i)\b\d+(?:\.\d+)?\s*(?:points?|pts?)\b"#,
            #"\d+(?:\.\d+)?\s*(?:分|分数)"#,
            #"(?i)\bremind\b|提前"#
        ]
        if let earliest = markers.compactMap({ firstMatchRange(in: working, pattern: $0) }).min(by: { $0.lowerBound < $1.lowerBound }) {
            working = String(working[..<earliest.lowerBound])
        }
        let cleaned = working
            .replacingOccurrences(of: #"^[\s,，:：、-]+|[\s,，:：、-]+$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.isEmpty { return cleaned }
        return switch type {
        case .lab: "Lab"
        case .quiz: "Quiz"
        case .midterm: "Midterm"
        case .finalExam: "Final Exam"
        default: "Assignment"
        }
    }

    private static func inferType(from input: String) -> GradeCategoryType {
        type(from: nil, fallbackText: input)
    }

    private static func type(from raw: String?, fallbackText: String) -> GradeCategoryType {
        let value = (raw ?? fallbackText).lowercased()
        if value.contains("lab") || value.contains("实验") { return .lab }
        if value.contains("quiz") || value.contains("小测") { return .quiz }
        if value.contains("final") || value.contains("期末") { return .finalExam }
        if value.contains("midterm") || value.contains("期中") { return .midterm }
        if value.contains("project") || value.contains("项目") { return .project }
        if value.contains("exam") || value.contains("考试") { return .midterm }
        return .homework
    }

    private static func dueDate(in input: String, referenceDate: Date) -> Date? {
        if let explicit = firstMatch(in: input, pattern: #"\b(20\d{2})[-/](\d{1,2})[-/](\d{1,2})\b"#),
           let date = parseDate(explicit.replacingOccurrences(of: "/", with: "-"), referenceDate: referenceDate) {
            return date
        }
        let lower = input.lowercased()
        if lower.contains("today") || input.contains("今天") { return Calendar.autoupdatingCurrent.startOfDay(for: referenceDate) }
        if lower.contains("tomorrow") || input.contains("明天") {
            return Calendar.autoupdatingCurrent.date(byAdding: .day, value: 1, to: Calendar.autoupdatingCurrent.startOfDay(for: referenceDate))
        }
        let weekdays: [(patterns: [String], value: Int)] = [
            (["sunday", "sun", "周日", "周天"], 1), (["monday", "mon", "周一"], 2),
            (["tuesday", "tue", "周二"], 3), (["wednesday", "wed", "周三"], 4),
            (["thursday", "thu", "周四"], 5), (["friday", "fri", "周五"], 6),
            (["saturday", "sat", "周六"], 7)
        ]
        guard let target = weekdays.first(where: { $0.patterns.contains(where: { lower.contains($0) }) })?.value else { return nil }
        var calendar = Calendar.autoupdatingCurrent
        calendar.timeZone = .autoupdatingCurrent
        let current = calendar.component(.weekday, from: referenceDate)
        let delta = (target - current + 7) % 7
        return calendar.date(byAdding: .day, value: delta == 0 ? 7 : delta, to: calendar.startOfDay(for: referenceDate))
    }

    private static func dueTime(in input: String) -> DateComponents? {
        let english = firstMatch(in: input, pattern: #"(?i)(?:at\s+)?(\d{1,2}):(\d{2})\s*(am|pm)?"#)
        let chinese = firstMatch(in: input, pattern: #"(?:晚上|下午|上午)?\s*(\d{1,2}):(\d{2})"#)
        guard let raw = english ?? chinese else { return nil }
        guard var components = parseTime(raw) else { return nil }
        if (input.contains("晚上") || input.contains("下午")), let hour = components.hour, hour < 12 {
            components.hour = hour + 12
        }
        return components
    }

    private static func parseTime(_ value: String?) -> DateComponents? {
        guard let value else { return nil }
        let pattern = #"(?i)(\d{1,2}):(\d{2})\s*(am|pm)?"#
        guard let match = firstMatchGroups(in: value, pattern: pattern),
              let hourRaw = group(match, at: 1), let minuteRaw = group(match, at: 2),
              var hour = Int(hourRaw), let minute = Int(minuteRaw), minute < 60 else { return nil }
        if group(match, at: 3)?.lowercased() == "pm", hour < 12 { hour += 12 }
        if group(match, at: 3)?.lowercased() == "am", hour == 12 { hour = 0 }
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        return components
    }

    private static func parseDate(_ value: String?, referenceDate: Date) -> Date? {
        guard let value else { return nil }
        let cleaned = value.replacingOccurrences(of: "/", with: "-")
        let components = cleaned.split(separator: "-").compactMap { Int($0) }
        guard components.count == 3 else { return nil }
        var date = DateComponents()
        date.year = components[0]; date.month = components[1]; date.day = components[2]
        return Calendar.autoupdatingCurrent.date(from: date)
    }

    private static func combine(date: Date?, time: DateComponents?, calendar: Calendar) -> Date? {
        guard let date else { return nil }
        guard let time else { return calendar.startOfDay(for: date) }
        return calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: date)
    }

    private static func reminderHours(in input: String) -> Int? {
        if input.contains("提前一天") || input.localizedCaseInsensitiveContains("one day") || input.localizedCaseInsensitiveContains("24 hours") { return 24 }
        if let match = firstMatchGroups(in: input, pattern: #"(?i)(?:remind me|提前)\s*(\d+)\s*(?:days?|天|hours?|小时)"#),
           let amount = group(match, at: 1).flatMap(Int.init) {
            let isHours = input.localizedCaseInsensitiveContains("hour") || input.contains("小时")
            return isHours ? amount : amount * 24
        }
        return nil
    }

    private static func decimalMatch(in input: String, pattern: String) -> Decimal? {
        guard let raw = firstMatchGroups(in: input, pattern: pattern).flatMap({ group($0, at: 1) }) else { return nil }
        return NSDecimalNumber(string: raw).decimalValue
    }

    private static func confidence(warnings: [String], title: String) -> Double {
        guard !title.isEmpty else { return 0.25 }
        return max(0.35, 1 - Double(warnings.count) * 0.12)
    }

    private static func firstMatch(in value: String, pattern: String) -> String? {
        firstMatchGroups(in: value, pattern: pattern).flatMap { group($0, at: 0) }
    }

    private static func group(_ groups: [String], at index: Int) -> String? {
        guard groups.indices.contains(index), !groups[index].isEmpty else { return nil }
        return groups[index]
    }

    private static func firstMatchRange(in value: String, pattern: String) -> Range<String.Index>? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, range: nsRange), let range = Range(match.range, in: value) else { return nil }
        return range
    }

    private static func firstMatchGroups(in value: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, range: nsRange) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            let range = match.range(at: index)
            guard range.location != NSNotFound, let swiftRange = Range(range, in: value) else { return "" }
            return String(value[swiftRange])
        }
    }
}

nonisolated enum QuickAddError: LocalizedError, Sendable {
    case invalidModelPayload

    var errorDescription: String? { String(localized: "The local model returned an incomplete Quick Add draft.") }
}
