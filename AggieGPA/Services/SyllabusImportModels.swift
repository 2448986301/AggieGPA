import Foundation

nonisolated enum SyllabusAnalysisMode: String, Sendable {
    case onDevice
}

nonisolated enum SyllabusAnalysisPhase: Equatable, Sendable {
    case idle, reading, analyzingGrading, organizingAssessments, usingLocalFallback, needsReview, complete, unavailable(String)

    var localizationKey: String {
        switch self {
        case .idle: ""
        case .reading: "Analyzing on this device"
        case .analyzingGrading: "Analyzing the grading structure"
        case .organizingAssessments: "Organizing assignments and exams"
        case .usingLocalFallback: "AI analysis was unavailable. Using local rule recognition instead."
        case .needsReview: "Some items need your review"
        case .complete: "Analysis complete"
        case .unavailable(let message): message
        }
    }
}

nonisolated struct SyllabusEvidence: Codable, Equatable, Sendable {
    var page: Int
    var excerpt: String
}

nonisolated struct SyllabusCourseInformation: Codable, Equatable, Sendable {
    var courseCode: String?
    var courseTitle: String?
    var instructor: String?
    var term: String?
    var units: Decimal?
}

nonisolated struct SyllabusCategoryDraft: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var normalizedType: GradeCategoryType
    var weightPercent: Decimal?
    var totalPoints: Decimal?
    var parentCategory: String?
    var dropLowestCount: Int
    var isExtraCredit: Bool
    var evidence: SyllabusEvidence?
    var confidence: Double
}

nonisolated struct SyllabusAssessmentDraft: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var title: String
    var type: GradeCategoryType
    var category: String?
    var dueDate: Date?
    var possiblePoints: Decimal?
    var weightPercent: Decimal?
    var evidence: SyllabusEvidence?
    var confidence: Double
}

nonisolated struct SyllabusGradeScaleDraft: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var letterGrade: GradeLetter
    var minimumPercent: Decimal
    var maximumPercent: Decimal?
    var plusMinusPolicy: String?
}

nonisolated struct SyllabusPoliciesDraft: Codable, Equatable, Sendable {
    var lateWorkPolicy: String?
    var missingWorkPolicy: String?
    var droppedScorePolicy: String?
    var attendancePolicy: String?
    var extraCreditPolicy: String?
    var curvedGradingPolicy: String?
}

nonisolated struct SyllabusExtractionIssue: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var field: String
    var reason: String
    var possibleValues: [String]
    var sourcePage: Int?
    var requiresUserReview: Bool
}

nonisolated struct SyllabusImportDraft: Codable, Equatable, Sendable {
    var courseInformation = SyllabusCourseInformation()
    var categories: [SyllabusCategoryDraft] = []
    var assessments: [SyllabusAssessmentDraft] = []
    var gradeScale: [SyllabusGradeScaleDraft] = []
    var policies = SyllabusPoliciesDraft()
    var issues: [SyllabusExtractionIssue] = []
    var source: SyllabusImportSource = .none

    var weightTotal: Decimal { categories.compactMap(\.weightPercent).reduce(0, +) }
    var requiresReview: Bool { !issues.isEmpty || categories.contains { $0.confidence < 0.75 } || assessments.contains { $0.confidence < 0.75 } }
}
