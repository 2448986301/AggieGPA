import Foundation

nonisolated enum AnalyzedGradingMode: String, Codable, CaseIterable, Sendable {
    case weightedCategories
    case pointsBased
    case mixed
    case unknown
}

nonisolated struct GradingEvidence: Codable, Equatable, Sendable {
    var sourceText: String
    var sourcePage: Int?
    var confidence: Double
}

nonisolated struct AnalyzedGradingCategory: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var type: GradeCategoryType
    var weightPercent: Decimal?
    var totalPoints: Decimal?
    var dropLowestCount: Int?
    var bestCount: Int?
    var totalCount: Int?
    var isExtraCredit: Bool
    var confidence: Double
    var evidence: [GradingEvidence]

    enum CodingKeys: String, CodingKey {
        case name, type, weightPercent, totalPoints, dropLowestCount, bestCount, totalCount
        case isExtraCredit, confidence, evidence
    }
}

nonisolated struct AnalyzedGradingItem: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var type: GradeCategoryType
    var categoryName: String?
    var possiblePoints: Decimal?
    var weightPercent: Decimal?
    var isDropped: Bool
    var isExtraCredit: Bool
    var confidence: Double
    var evidence: [GradingEvidence]

    enum CodingKeys: String, CodingKey {
        case name, type, categoryName, possiblePoints, weightPercent
        case isDropped, isExtraCredit, confidence, evidence
    }
}

nonisolated struct AnalyzedGradeBoundary: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var letter: GradeLetter
    var minimumPercent: Decimal
    var confidence: Double
    var evidence: [GradingEvidence]

    enum CodingKeys: String, CodingKey {
        case letter, minimumPercent, confidence, evidence
    }
}

nonisolated enum GradingRuleKind: String, Codable, CaseIterable, Sendable {
    case dropLowest
    case bestNOfM
    case replacementExam
    case extraCredit
    case droppedAssignment
    case attendance
    case custom
}

nonisolated struct AnalyzedGradingRule: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var kind: GradingRuleKind
    var description: String
    var categoryName: String?
    var count: Int?
    var totalCount: Int?
    var confidence: Double
    var evidence: [GradingEvidence]

    enum CodingKeys: String, CodingKey {
        case kind, description, categoryName, count, totalCount, confidence, evidence
    }
}

nonisolated struct GradingAnalysisWarning: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var code: String
    var message: String
    var sourcePage: Int?
    var requiresReview: Bool

    enum CodingKeys: String, CodingKey {
        case code, message, sourcePage, requiresReview
    }
}

nonisolated struct GradingAnalysis: Codable, Equatable, Sendable {
    var gradingMode: AnalyzedGradingMode
    var categories: [AnalyzedGradingCategory]
    var assignments: [AnalyzedGradingItem]
    var exams: [AnalyzedGradingItem]
    var gradingScale: [AnalyzedGradeBoundary]
    var totalWeight: Decimal?
    var rules: [AnalyzedGradingRule]
    var warnings: [GradingAnalysisWarning]
    var confidence: Double
    var evidence: [GradingEvidence]

    static let empty = GradingAnalysis(
        gradingMode: .unknown,
        categories: [],
        assignments: [],
        exams: [],
        gradingScale: [],
        totalWeight: nil,
        rules: [],
        warnings: [],
        confidence: 0,
        evidence: []
    )
}

nonisolated enum GradingAnalysisValidator {
    static func validate(_ input: GradingAnalysis) -> GradingAnalysis {
        var analysis = input
        analysis.warnings.removeAll { $0.code.hasPrefix("validator.") }
        let groupedInputCategories = Dictionary(grouping: input.categories) { normalized($0.name) }
        for values in groupedInputCategories.values where values.count > 1 {
            appendWarning(&analysis, code: "validator.duplicateCategory", message: String(localized: "Duplicate grading categories were combined for review."), page: values.first?.evidence.first?.sourcePage)
            let weights = Set(values.compactMap(\.weightPercent).map { NSDecimalNumber(decimal: $0).stringValue })
            let points = Set(values.compactMap(\.totalPoints).map { NSDecimalNumber(decimal: $0).stringValue })
            if weights.count > 1 || points.count > 1 {
                appendWarning(&analysis, code: "validator.categoryConflict", message: String(localized: "A grading category has conflicting values in the syllabus."), page: values.first?.evidence.first?.sourcePage)
            }
        }
        analysis.categories = deduplicatedCategories(input.categories)
        analysis.assignments = deduplicatedItems(input.assignments)
        analysis.exams = deduplicatedItems(input.exams)

        let weights = analysis.categories.compactMap(\.weightPercent)
        analysis.totalWeight = weights.isEmpty ? nil : weights.reduce(0, +)
        let hasPoints = analysis.categories.contains { $0.totalPoints != nil }
            || (analysis.assignments + analysis.exams).contains { $0.possiblePoints != nil }
        let hasWeights = !weights.isEmpty || (analysis.assignments + analysis.exams).contains { $0.weightPercent != nil }

        if hasWeights && hasPoints {
            analysis.gradingMode = .mixed
            appendWarning(&analysis, code: "validator.mixed", message: String(localized: "The syllabus mixes percentage weights and points. Confirm how the course calculates grades."))
        } else if hasWeights {
            analysis.gradingMode = .weightedCategories
        } else if hasPoints {
            analysis.gradingMode = .pointsBased
        } else {
            analysis.gradingMode = .unknown
            appendWarning(&analysis, code: "validator.missingMode", message: String(localized: "A complete grading method was not found."))
        }

        if let total = analysis.totalWeight, total != 100 {
            appendWarning(
                &analysis,
                code: "validator.weightTotal",
                message: String(localized: "Recognized category weights total \(decimalText(total))%, not 100%. No missing weight was added.")
            )
        }

        for category in analysis.categories {
            if category.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                appendWarning(&analysis, code: "validator.emptyName", message: String(localized: "A grading category needs a name."), page: category.evidence.first?.sourcePage)
            }
            if let weight = category.weightPercent, weight < 0 || weight > 100 {
                appendWarning(&analysis, code: "validator.invalidWeight", message: String(localized: "A category has a percentage outside 0–100%."), page: category.evidence.first?.sourcePage)
            }
            if analysis.gradingMode == .weightedCategories && category.weightPercent == nil && !category.isExtraCredit {
                appendWarning(&analysis, code: "validator.missingWeight", message: String(localized: "\(category.name) does not have an explicit weight."), page: category.evidence.first?.sourcePage)
            }
            if let drop = category.dropLowestCount, drop < 0 {
                appendWarning(&analysis, code: "validator.impossibleDrop", message: String(localized: "A drop-lowest count cannot be negative."), page: category.evidence.first?.sourcePage)
            }
            if let points = category.totalPoints, points < 0 {
                appendWarning(&analysis, code: "validator.invalidPoints", message: String(localized: "A point total cannot be negative."), page: category.evidence.first?.sourcePage)
            }
            if let best = category.bestCount, let total = category.totalCount, (best < 0 || total < 0 || best > total) {
                appendWarning(&analysis, code: "validator.impossibleBest", message: String(localized: "A best-N-of-M rule contains impossible values."), page: category.evidence.first?.sourcePage)
            }
        }

        if analysis.categories.isEmpty {
            appendWarning(&analysis, code: "validator.noCategories", message: String(localized: "No explicit grading categories were found."))
        }

        for item in analysis.assignments + analysis.exams {
            if let weight = item.weightPercent, weight < 0 || weight > 100 {
                appendWarning(&analysis, code: "validator.invalidItemWeight", message: String(localized: "An assignment or exam has a percentage outside 0–100%."), page: item.evidence.first?.sourcePage)
            }
            if let points = item.possiblePoints, points < 0 {
                appendWarning(&analysis, code: "validator.invalidItemPoints", message: String(localized: "An assignment or exam cannot have negative points."), page: item.evidence.first?.sourcePage)
            }
        }

        for boundary in analysis.gradingScale where boundary.minimumPercent < 0 || boundary.minimumPercent > 100 {
            appendWarning(&analysis, code: "validator.invalidScale", message: String(localized: "A grade-scale boundary is outside 0–100%."), page: boundary.evidence.first?.sourcePage)
        }

        let replacementRules = analysis.rules.filter { $0.kind == .replacementExam }
        if Set(replacementRules.map { normalized($0.description) }).count > 1 {
            appendWarning(&analysis, code: "validator.conflictingReplacement", message: String(localized: "More than one replacement-exam rule was found. Confirm which rule applies."), page: replacementRules.first?.evidence.first?.sourcePage)
        }
        let groupedRules = Dictionary(grouping: analysis.rules) {
            "\($0.kind.rawValue)|\(normalized($0.categoryName ?? ""))"
        }
        for values in groupedRules.values where values.count > 1 {
            let descriptions = Set(values.map { normalized($0.description) })
            let counts = Set(values.compactMap(\.count))
            let totals = Set(values.compactMap(\.totalCount))
            if descriptions.count > 1 || counts.count > 1 || totals.count > 1 {
                appendWarning(
                    &analysis,
                    code: "validator.conflictingRule",
                    message: String(localized: "The syllabus contains conflicting grading rules. Confirm which rule applies."),
                    page: values.first?.evidence.first?.sourcePage
                )
            }
        }

        analysis.confidence = min(1, max(0, input.confidence))
        if analysis.confidence < 0.75 {
            appendWarning(&analysis, code: "validator.lowConfidence", message: String(localized: "Some grading details need confirmation because the analysis confidence is low."))
        }
        return analysis
    }

    static func merged(_ analyses: [GradingAnalysis]) -> GradingAnalysis {
        guard !analyses.isEmpty else { return validate(.empty) }
        var result = GradingAnalysis.empty
        result.categories = analyses.flatMap(\.categories)
        result.assignments = analyses.flatMap(\.assignments)
        result.exams = analyses.flatMap(\.exams)
        result.gradingScale = deduplicatedBoundaries(analyses.flatMap(\.gradingScale))
        result.rules = deduplicatedRules(analyses.flatMap(\.rules))
        result.warnings = analyses.flatMap(\.warnings)
        result.evidence = analyses.flatMap(\.evidence)
        result.confidence = analyses.map(\.confidence).reduce(0, +) / Double(analyses.count)
        return validate(result)
    }

    /// Applies the explicit reconciliation pass ahead of the chunk-local
    /// findings, while retaining every source-backed finding as evidence. A
    /// reconciler is allowed to choose a value, but it is not allowed to make
    /// an unresolved conflict disappear; the validator warning remains part
    /// of the editable review draft.
    static func reconciled(_ preliminary: [GradingAnalysis], with final: GradingAnalysis) -> GradingAnalysis {
        let base = merged(preliminary)
        var result = final
        if result.categories.isEmpty { result.categories = base.categories }
        if result.assignments.isEmpty { result.assignments = base.assignments }
        if result.exams.isEmpty { result.exams = base.exams }
        if result.gradingScale.isEmpty { result.gradingScale = base.gradingScale }
        if result.rules.isEmpty { result.rules = base.rules }
        if result.totalWeight == nil { result.totalWeight = base.totalWeight }
        result.warnings = uniqueWarnings(result.warnings + base.warnings)
        result.evidence = uniqueEvidence(result.evidence + base.evidence)
        result.confidence = max(result.confidence, base.confidence)

        for finalCategory in final.categories {
            guard let baseCategory = base.categories.first(where: { normalized($0.name) == normalized(finalCategory.name) }) else { continue }
            if finalCategory.weightPercent != nil,
               baseCategory.weightPercent != nil,
               finalCategory.weightPercent != baseCategory.weightPercent {
                appendWarning(
                    &result,
                    code: "reconciliation.categoryConflict",
                    message: String(localized: "A reconciliation pass found conflicting category weights. Confirm the source before importing."),
                    page: finalCategory.evidence.first?.sourcePage ?? baseCategory.evidence.first?.sourcePage
                )
            }
            if finalCategory.totalPoints != nil,
               baseCategory.totalPoints != nil,
               finalCategory.totalPoints != baseCategory.totalPoints {
                appendWarning(
                    &result,
                    code: "reconciliation.pointsConflict",
                    message: String(localized: "A reconciliation pass found conflicting category point totals. Confirm the source before importing."),
                    page: finalCategory.evidence.first?.sourcePage ?? baseCategory.evidence.first?.sourcePage
                )
            }
        }
        return validate(result)
    }

    private static func deduplicatedCategories(_ values: [AnalyzedGradingCategory]) -> [AnalyzedGradingCategory] {
        var result: [AnalyzedGradingCategory] = []
        for value in values {
            let key = normalized(value.name)
            if let index = result.firstIndex(where: { normalized($0.name) == key }) {
                var existing = result[index]
                if existing.weightPercent == nil { existing.weightPercent = value.weightPercent }
                if existing.totalPoints == nil { existing.totalPoints = value.totalPoints }
                if existing.dropLowestCount == nil { existing.dropLowestCount = value.dropLowestCount }
                if existing.bestCount == nil { existing.bestCount = value.bestCount }
                if existing.totalCount == nil { existing.totalCount = value.totalCount }
                existing.evidence = uniqueEvidence(existing.evidence + value.evidence)
                existing.confidence = max(existing.confidence, value.confidence)
                result[index] = existing
            } else {
                result.append(value)
            }
        }
        return result
    }

    private static func deduplicatedItems(_ values: [AnalyzedGradingItem]) -> [AnalyzedGradingItem] {
        var seen = Set<String>()
        return values.filter { seen.insert(normalized($0.name) + "|" + normalized($0.categoryName ?? "")).inserted }
    }

    private static func deduplicatedBoundaries(_ values: [AnalyzedGradeBoundary]) -> [AnalyzedGradeBoundary] {
        var seen = Set<GradeLetter>()
        return values.filter { seen.insert($0.letter).inserted }.sorted { $0.minimumPercent > $1.minimumPercent }
    }

    private static func deduplicatedRules(_ values: [AnalyzedGradingRule]) -> [AnalyzedGradingRule] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.kind.rawValue + "|" + normalized($0.description)).inserted }
    }

    private static func uniqueEvidence(_ values: [GradingEvidence]) -> [GradingEvidence] {
        var seen = Set<String>()
        return values.filter { seen.insert("\($0.sourcePage ?? 0)|\($0.sourceText)").inserted }
    }

    private static func uniqueWarnings(_ values: [GradingAnalysisWarning]) -> [GradingAnalysisWarning] {
        var seen = Set<String>()
        return values.filter { seen.insert("\($0.code)|\($0.sourcePage ?? 0)|\($0.message)").inserted }
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func appendWarning(_ analysis: inout GradingAnalysis, code: String, message: String, page: Int? = nil) {
        guard !analysis.warnings.contains(where: { $0.code == code && $0.sourcePage == page }) else { return }
        analysis.warnings.append(.init(code: code, message: message, sourcePage: page, requiresReview: true))
    }

    private static func decimalText(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }
}
