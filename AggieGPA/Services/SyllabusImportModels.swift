import Foundation

nonisolated enum SyllabusAnalysisMode: String, Sendable {
    case onDevice
    case localRules
}

nonisolated enum SyllabusAnalysisPhase: Equatable, Sendable {
    case idle
    case reading
    case downloadingModel(ModelDownloadProgress)
    case loadingModel
    case modelFallback(from: String, to: String, reason: String)
    case analyzingPage(current: Int, total: Int)
    case repairingStructuredOutput
    case retryingRelevantSection
    case usingPartialResult
    case analyzingGrading
    case organizingAssessments
    case usingLocalFallback
    case validating
    case needsReview
    case complete
    case unavailable(String)

    func displayText(locale: Locale) -> String {
        switch self {
        case .idle: ""
        case .reading: AppLocalization.string("Reading syllabus text", locale: locale)
        case .downloadingModel: AppLocalization.string("Downloading the local model", locale: locale)
        case .loadingModel: AppLocalization.string("Loading the local model", locale: locale)
        case .modelFallback(let from, let to, let reason):
            String(
                format: AppLocalization.string("Using %@ instead of %@. %@", locale: locale),
                to,
                from,
                AppLocalization.string(reason, locale: locale)
            )
        case .analyzingPage(let current, let total):
            String(
                format: AppLocalization.string("Analyzing section %lld of %lld", locale: locale),
                Int64(current),
                Int64(total)
            )
        case .repairingStructuredOutput:
            AppLocalization.string("Repairing the structured result", locale: locale)
        case .retryingRelevantSection:
            AppLocalization.string("Retrying the relevant syllabus section", locale: locale)
        case .usingPartialResult:
            AppLocalization.string("Using a partial result for manual review", locale: locale)
        case .analyzingGrading: AppLocalization.string("Analyzing the grading structure", locale: locale)
        case .organizingAssessments: AppLocalization.string("Organizing assignments and exams", locale: locale)
        case .usingLocalFallback: AppLocalization.string("Reviewing grading information locally.", locale: locale)
        case .validating: AppLocalization.string("Checking weights and grading rules", locale: locale)
        case .needsReview: AppLocalization.string("Some items need your review", locale: locale)
        case .complete: AppLocalization.string("Analysis complete", locale: locale)
        case .unavailable(let message): message
        }
    }
}

nonisolated struct SyllabusEvidence: Codable, Equatable, Sendable {
    var page: Int
    var excerpt: String
    var confidence: Double

    init(page: Int, excerpt: String, confidence: Double = 0.5) {
        self.page = page
        self.excerpt = excerpt
        self.confidence = confidence
    }
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
    var gradingMode: AnalyzedGradingMode = .unknown
    var rules: [AnalyzedGradingRule] = []
    var analysisWarnings: [GradingAnalysisWarning] = []
    var runtimeMetrics: OnDeviceAIRuntimeMetrics?
    var providerName: String?
    var modelName: String?
    var overallConfidence: Double = 0

    var weightTotal: Decimal { categories.compactMap(\.weightPercent).reduce(0, +) }
    var requiresReview: Bool {
        !issues.isEmpty || !analysisWarnings.isEmpty || categories.contains { $0.confidence < 0.75 }
            || assessments.contains { $0.confidence < 0.75 }
    }
}
