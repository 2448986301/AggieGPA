import Foundation

/// The failure order is part of the syllabus feature contract. It is kept as
/// data so tests and the review surface can prove that a malformed local
/// response does not jump straight to a dead-end error.
nonisolated enum SyllabusRecoveryStep: String, CaseIterable, Codable, Sendable {
    case structuredRepair
    case relevantSectionRetry
    case smallerContextRetry
    case partialExtraction
    case manualReview
}

nonisolated enum SyllabusAnalysisRecovery {
    static let orderedSteps: [SyllabusRecoveryStep] = [
        .structuredRepair,
        .relevantSectionRetry,
        .smallerContextRetry,
        .partialExtraction,
        .manualReview
    ]
}
