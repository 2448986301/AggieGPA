import Foundation

nonisolated struct SyllabusCategoryCandidate: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var categoryType: GradeCategoryType
    var weight: Decimal?
    var possiblePoints: Decimal?
    var calculationMode: CategoryCalculationMode
    var confidence: Double
    var sourceLine: String

    init(id: UUID = UUID(), name: String, categoryType: GradeCategoryType, weight: Decimal? = nil,
         possiblePoints: Decimal? = nil, calculationMode: CategoryCalculationMode = .totalPoints,
         confidence: Double, sourceLine: String) {
        self.id = id; self.name = name; self.categoryType = categoryType; self.weight = weight
        self.possiblePoints = possiblePoints; self.calculationMode = calculationMode
        self.confidence = confidence; self.sourceLine = sourceLine
    }
}

nonisolated struct SyllabusParseResult: Equatable, Sendable {
    var categories: [SyllabusCategoryCandidate]
    var gradeBoundaries: [GradeScaleBoundary]
    var dropLowestCategoryNames: [String]
    var manualReviewReasons: [String]
    var confidence: Double
    var sourceText: String

    var suggestedMethod: GradingMethod {
        let hasWeights = categories.contains { $0.weight != nil }
        let hasPoints = categories.contains { $0.possiblePoints != nil }
        if hasWeights && hasPoints { return .hybrid }
        return hasWeights ? .weightedCategories : .totalPoints
    }

    var requiresManualReview: Bool { !manualReviewReasons.isEmpty }
}

nonisolated enum SyllabusRuleParser {
    static func parse(_ text: String, extractionConfidence: Double = 1) -> SyllabusParseResult {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var candidates: [SyllabusCategoryCandidate] = []
        var dropNames: [String] = []
        var reasons: [String] = []

        for line in lines {
            if let each = match(line, pattern: #"(?i)^\s*(two|2)\s+(.+?)[,:]?\s*(\d+(?:\.\d+)?)\s*%\s*each\b"#),
               let value = decimal(each[3]) {
                let name = cleanName(each[2])
                candidates.append(candidate(name: name, weight: value * 2, confidence: 0.97 * extractionConfidence, line: line))
                continue
            }
            if let total = match(line, pattern: #"(?i)^\s*(.+?)[,:]?\s*(\d+(?:\.\d+)?)\s*%\s*total\b"#),
               let value = decimal(total[2]) {
                let name = cleanName(total[1])
                candidates.append(candidate(name: name, weight: value, confidence: 0.96 * extractionConfidence, line: line))
                continue
            }
            if let percentage = match(line, pattern: #"(?i)^\s*(.+?)(?:\s*[:\-—]\s*|\s*\(\s*|\s+)(\d+(?:\.\d+)?)\s*(?:%|percent)\s*\)?\s*$"#),
               let value = decimal(percentage[2]) {
                let name = cleanName(percentage[1])
                candidates.append(candidate(name: name, weight: value, confidence: 0.94 * extractionConfidence, line: line))
                continue
            }
            if let fraction = match(line, pattern: #"(?i)^\s*(.+?)[,:]?\s*(\d+(?:\.\d+)?)\s*/\s*(\d+(?:\.\d+)?)\s*points?\s*$"#),
               let possible = decimal(fraction[3]) {
                let name = cleanName(fraction[1])
                candidates.append(candidate(name: name, possible: possible, confidence: 0.92 * extractionConfidence, line: line))
                continue
            }
            if let points = match(line, pattern: #"(?i)^\s*(.+?)[,:]?\s*(\d+(?:\.\d+)?)\s*points?\s*$"#),
               let possible = decimal(points[2]) {
                let name = cleanName(points[1])
                candidates.append(candidate(name: name, possible: possible, confidence: 0.88 * extractionConfidence, line: line))
            }
        }

        for line in lines {
            let lower = line.lowercased()
            if lower.contains("lowest") && lower.contains("drop") {
                dropNames.append(inferredDropCategory(from: lower))
            }
            if lower.contains("final") && lower.contains("replace") && lower.contains("midterm") {
                reasons.append("Final-exam replacement rule requires manual review.")
            }
            if lower.contains("curve") { reasons.append("A curve is mentioned.") }
            if lower.contains("section") && lower.contains("grading") { reasons.append("A section-specific grading policy may apply.") }
            if (lower.contains("extra credit") || lower.contains("extra-credit")) && !lower.contains("up to") {
                reasons.append("The extra-credit rule is ambiguous.")
            }
        }

        candidates = deduplicated(candidates)
        let hasWeights = candidates.contains { $0.weight != nil }
        let hasPoints = candidates.contains { $0.possiblePoints != nil }
        let weightTotal = candidates.compactMap(\.weight).reduce(Decimal.zero, +)
        if hasWeights, weightTotal != 100 { reasons.append("Recognized category weights total \(weightTotal)%, not 100%.") }
        if hasWeights && hasPoints { reasons.append("The policy mixes percentages and points.") }
        if extractionConfidence < 0.75 { reasons.append("Text extraction confidence is low.") }
        if candidates.isEmpty { reasons.append("No grading categories were recognized.") }

        let gradeBoundaries = parseGradeBoundaries(lines)
        let candidateConfidence = candidates.isEmpty ? 0 : candidates.map(\.confidence).reduce(0, +) / Double(candidates.count)
        return SyllabusParseResult(
            categories: candidates, gradeBoundaries: gradeBoundaries,
            dropLowestCategoryNames: Array(Set(dropNames)),
            manualReviewReasons: Array(Set(reasons)).sorted(),
            confidence: min(extractionConfidence, candidateConfidence), sourceText: text
        )
    }

    private static func candidate(name: String, weight: Decimal? = nil, possible: Decimal? = nil,
                                  confidence: Double, line: String) -> SyllabusCategoryCandidate {
        SyllabusCategoryCandidate(name: name, categoryType: categoryType(for: name), weight: weight,
                                  possiblePoints: possible, calculationMode: .totalPoints,
                                  confidence: confidence, sourceLine: line)
    }

    private static func parseGradeBoundaries(_ lines: [String]) -> [GradeScaleBoundary] {
        var boundaries: [GradeScaleBoundary] = []
        for line in lines {
            guard let groups = match(line, pattern: #"(?i)^\s*(A\+|A-|A|B\+|B-|B|C\+|C-|C|D\+|D-|D|F)\s*[:>=-]+\s*(\d+(?:\.\d+)?)\s*%?"#),
                  let letter = GradeLetter(rawValue: groups[1].uppercased()), let value = decimal(groups[2]) else { continue }
            boundaries.append(GradeScaleBoundary(letter: letter, minimumPercentage: value))
        }
        return boundaries.sorted { $0.minimumPercentage > $1.minimumPercentage }
    }

    private static func inferredDropCategory(from lower: String) -> String {
        if lower.contains("quiz") { return "Quiz" }
        if lower.contains("assignment") { return "Assignment" }
        if lower.contains("homework") { return "Homework" }
        if lower.contains("midterm") { return "Midterm" }
        return ""
    }

    private static func deduplicated(_ candidates: [SyllabusCategoryCandidate]) -> [SyllabusCategoryCandidate] {
        var seen = Set<String>()
        return candidates.filter { seen.insert($0.name.lowercased()).inserted }
    }

    private static func categoryType(for name: String) -> GradeCategoryType {
        let value = name.lowercased()
        if value.contains("homework") || value.contains("assignment") { return .homework }
        if value.contains("quiz") { return .quiz }
        if value.contains("lab") { return .lab }
        if value.contains("discussion") { return .discussion }
        if value.contains("participation") { return .participation }
        if value.contains("attendance") { return .attendance }
        if value.contains("project") { return .project }
        if value.contains("presentation") { return .presentation }
        if value.contains("midterm") { return .midterm }
        if value.contains("final") { return .finalExam }
        if value.contains("extra") { return .extraCredit }
        return .custom
    }

    private static func cleanName(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: " :,-—()"))
            .replacingOccurrences(of: #"(?i)^grading\s+"#, with: "", options: .regularExpression)
    }

    private static func decimal(_ value: String) -> Decimal? { Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) }

    private static func match(_ value: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let result = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { return nil }
        return (0..<result.numberOfRanges).map { index in
            let range = result.range(at: index)
            return Range(range, in: value).map { String(value[$0]) } ?? ""
        }
    }
}
