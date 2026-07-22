#if canImport(FoundationModels)
import Foundation
import FoundationModels

@Generable(description: "One grading category found in a course syllabus")
struct ModelSyllabusCategory {
    @Guide(description: "Short category name such as Homework, Quizzes, Midterms, or Final")
    var name: String
    @Guide(description: "Category weight as a number from 0 through 100, or nil when the syllabus uses only points", .range(0...100))
    var weight: Double?
    @Guide(description: "Total possible points for this category, or nil when not stated", .range(0...100000))
    var possiblePoints: Double?
    @Guide(description: "Number of lowest items dropped, normally zero", .range(0...20))
    var dropLowestCount: Int
}

@Generable(description: "Structured candidates extracted from syllabus text. These are unconfirmed suggestions.")
struct ModelSyllabusDraft {
    var categories: [ModelSyllabusCategory]
    @Guide(description: "Grade-scale lines in a compact format such as A: 93")
    var gradeBoundaries: [String]
    @Guide(description: "Complex, ambiguous, replacement, curve, extra-credit, or section-specific rules needing human review")
    var complexRules: [String]
}

nonisolated enum OnDeviceModelAvailability: Equatable, Sendable {
    case available
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unsupportedLocale
    case frameworkUnavailable

    var message: String {
        switch self {
        case .available: "On-device model is available."
        case .deviceNotEligible: "Apple Intelligence is not supported on this device."
        case .appleIntelligenceNotEnabled: "Apple Intelligence is not enabled."
        case .modelNotReady: "The on-device language model is not ready."
        case .unsupportedLocale: "The current language is not supported by the on-device model."
        case .frameworkUnavailable: "Foundation Models is unavailable on this system."
        }
    }
}

enum OnDeviceSyllabusParser {
    static func availability(locale: Locale = .current) -> OnDeviceModelAvailability {
        guard #available(iOS 26.0, *) else { return .frameworkUnavailable }
        let model = SystemLanguageModel.default
        guard model.supportsLocale(locale) else { return .unsupportedLocale }
        switch model.availability {
        case .available: return .available
        case .unavailable(.deviceNotEligible): return .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled): return .appleIntelligenceNotEnabled
        case .unavailable(.modelNotReady): return .modelNotReady
        @unknown default: return .modelNotReady
        }
    }

    static func parse(_ text: String) async throws -> SyllabusParseResult {
        guard availability() == .available else { throw ParserError.unavailable(availability()) }
        let session = LanguageModelSession(
            model: SystemLanguageModel.default,
            instructions: """
            Extract only grading-rule candidates explicitly present in the supplied syllabus text.
            Do not infer unstated weights, points, grade boundaries, or policies.
            Put replacement rules, curves, multiple schemes, ambiguous drop rules, and extra credit in complexRules.
            This runs on device. The result will be checked by deterministic code and reviewed by the user.
            """
        )
        let response = try await session.respond(
            to: "Extract grading candidates from this syllabus text:\n\n\(text)",
            generating: ModelSyllabusDraft.self
        )
        return validated(response.content, originalText: text)
    }

    static func validated(_ draft: ModelSyllabusDraft, originalText: String) -> SyllabusParseResult {
        var canonicalLines: [String] = []
        for category in draft.categories {
            if let weight = category.weight {
                canonicalLines.append("\(category.name): \(weight)%")
            } else if let points = category.possiblePoints {
                canonicalLines.append("\(category.name) \(points) points")
            }
            if category.dropLowestCount > 0 {
                canonicalLines.append("Drop lowest \(category.dropLowestCount) \(category.name)")
            }
        }
        canonicalLines += draft.gradeBoundaries
        var result = SyllabusRuleParser.parse(canonicalLines.joined(separator: "\n"))
        result.sourceText = originalText
        result.manualReviewReasons += draft.complexRules.map { "On-device model flagged: \($0)" }
        result.manualReviewReasons = Array(Set(result.manualReviewReasons)).sorted()
        result.confidence = min(result.confidence, 0.85)
        return result
    }

    enum ParserError: LocalizedError {
        case unavailable(OnDeviceModelAvailability)
        var errorDescription: String? {
            switch self { case .unavailable(let status): status.message }
        }
    }
}
#else
import Foundation

nonisolated enum OnDeviceModelAvailability: Equatable, Sendable {
    case frameworkUnavailable
    var message: String { "Foundation Models is unavailable on this system." }
}

enum OnDeviceSyllabusParser {
    static func availability(locale: Locale = .current) -> OnDeviceModelAvailability { .frameworkUnavailable }
}
#endif
