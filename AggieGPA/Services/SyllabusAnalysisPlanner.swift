import Foundation

nonisolated enum SyllabusAnalysisComplexity: String, Codable, Sendable {
    case simple
    case complex
}

nonisolated enum SyllabusAnalysisPass: String, Codable, CaseIterable, Sendable {
    case complete
    case gradingStructure
    case rulesAndExceptions
    case conflictReconciliation

    var instruction: String {
        switch self {
        case .complete:
            "Extract every explicit grading category, item, weight, point total, scale boundary, rule, warning, and evidence in this excerpt."
        case .gradingStructure:
            "Prioritize grading structure: categories, individual assignments/exams, percentage weights, possible points, drop counts, and best-N-of-M counts. Still return the complete JSON object and use empty arrays for fields not explicit in this excerpt."
        case .rulesAndExceptions:
            "Prioritize policies and exceptions: drop-lowest, best-N-of-M, replacement exams, extra credit, dropped work, attendance, late work, and conflicts. Still return the complete JSON object and use empty arrays for fields not explicit in this excerpt."
        case .conflictReconciliation:
            "Reconcile the preliminary structure and rule findings supplied with this pass. Preserve only values supported by the source, flag conflicting weights, points, grade-scale boundaries, or exception rules, and keep source evidence for every retained value. Still return the complete JSON object; use null or empty arrays when the source does not resolve a value."
        }
    }
}

nonisolated struct SyllabusAnalysisPlan: Equatable, Sendable {
    let complexity: SyllabusAnalysisComplexity
    let chunks: [SyllabusAnalysisChunk]
    let passes: [SyllabusAnalysisPass]

    /// Complex analysis performs two chunk-local passes and one final
    /// reconciliation pass over their bounded results. Keeping this explicit
    /// prevents the UI from claiming that a per-chunk scale pass reconciled
    /// conflicts that it never saw.
    var operationCount: Int {
        if passes.contains(.conflictReconciliation) {
            return chunks.count * max(0, passes.count - 1) + 1
        }
        return chunks.count * passes.count
    }
}

nonisolated enum SyllabusAnalysisPlanner {
    static func plan(for document: SyllabusTextExtractor.Document) -> SyllabusAnalysisPlan {
        let chunks = SyllabusAnalysisPipeline.chunks(from: document)
        let allText = chunks.map(\.text).joined(separator: "\n\n").lowercased()
        let sections = SyllabusAnalysisPipeline.sections(from: document)
        let exceptionSignals = [
            "drop lowest", "best of", "best n", "replacement", "extra credit", "bonus",
            "late work", "incomplete", "conflict", "最低分", "替代考试", "加分", "迟交"
        ]
        let hasException = exceptionSignals.contains { allText.contains($0) }
        let isComplex = chunks.count > 1
            || sections.count >= 5
            || allText.count > 14_000
            || hasException
            || Set(sections.map(\.kind)).count >= 3
        return SyllabusAnalysisPlan(
            complexity: isComplex ? .complex : .simple,
            chunks: chunks,
            passes: isComplex ? [.gradingStructure, .rulesAndExceptions, .conflictReconciliation] : [.complete]
        )
    }
}
