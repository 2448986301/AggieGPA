import Foundation

nonisolated enum OnDeviceModelAvailability: Equatable, Sendable {
    case available
    case downloadRequired
    case runtimeUnavailable

    func message(locale: Locale) -> String {
        switch self {
        case .available:
            AppLocalization.string("Runs On Device", locale: locale)
        case .downloadRequired:
            String(
                format: AppLocalization.string("Download %@ to analyze syllabi on this device.", locale: locale),
                OnDeviceAIModelLibrary.recommendedDescriptor.storageLabel
            )
        case .runtimeUnavailable:
            AppLocalization.string("The open-source local model runtime is not linked in this build.", locale: locale)
        }
    }
}

enum OnDeviceSyllabusParser {
    static func availability(locale: Locale = .current) -> OnDeviceModelAvailability {
#if canImport(llama)
        AIModelStore.quickAvailability() ? .available : .downloadRequired
#else
        .runtimeUnavailable
#endif
    }

    static func prepareModel(
        progress: @escaping @Sendable (ModelDownloadProgress) -> Void = { _ in }
    ) async throws {
        _ = try await OnDeviceAIModelLibrary.prepareRecommended(progress: progress)
    }

    static func extract(
        document: SyllabusTextExtractor.Document,
        mode: SyllabusAnalysisMode,
        progress: @escaping @Sendable (SyllabusAnalysisPhase) -> Void
    ) async throws -> SyllabusImportDraft {
        let provider = AIProviderFactory.make(mode: mode)
        let result = try await provider.analyze(document: document) { phase in
            switch phase {
            case .downloadingModel(let download): progress(.downloadingModel(download))
            case .loadingModel: progress(.loadingModel)
            case .modelFallback(let from, let to, let reason):
                progress(.modelFallback(from: from, to: to, reason: reason))
            case .analyzingPage(let current, let total): progress(.analyzingPage(current: current, total: total))
            case .repairingStructuredOutput: progress(.repairingStructuredOutput)
            case .retryingRelevantSection: progress(.retryingRelevantSection)
            case .usingPartialResult: progress(.usingPartialResult)
            case .validating: progress(.validating)
            }
        }
        var draft = importDraft(from: result.analysis, source: document.source)
        draft.runtimeMetrics = result.metrics
        draft.providerName = result.providerName
        draft.modelName = result.modelName
        progress(draft.requiresReview ? .needsReview : .complete)
        return draft
    }

    static func importDraft(from analysis: GradingAnalysis, source: SyllabusImportSource) -> SyllabusImportDraft {
        let validated = GradingAnalysisValidator.validate(analysis)
        var draft = SyllabusImportDraft()
        draft.source = source
        draft.gradingMode = validated.gradingMode
        draft.overallConfidence = validated.confidence
        draft.rules = validated.rules
        draft.analysisWarnings = validated.warnings
        draft.categories = validated.categories.map { category in
            SyllabusCategoryDraft(
                name: category.name,
                normalizedType: category.type,
                weightPercent: category.weightPercent,
                totalPoints: category.totalPoints,
                parentCategory: nil,
                dropLowestCount: max(0, category.dropLowestCount ?? 0),
                isExtraCredit: category.isExtraCredit,
                evidence: category.evidence.first.map {
                    .init(page: $0.sourcePage ?? 1, excerpt: $0.sourceText, confidence: $0.confidence)
                },
                confidence: category.confidence
            )
        }
        draft.assessments = (validated.assignments + validated.exams)
            .filter { !$0.isDropped }
            .map { item in
                SyllabusAssessmentDraft(
                    title: item.name,
                    type: item.type,
                    category: item.categoryName,
                    dueDate: nil,
                    possiblePoints: item.possiblePoints,
                    weightPercent: item.weightPercent,
                    evidence: item.evidence.first.map {
                        .init(page: $0.sourcePage ?? 1, excerpt: $0.sourceText, confidence: $0.confidence)
                    },
                    confidence: item.confidence
                )
            }
        draft.gradeScale = validated.gradingScale.map {
            .init(letterGrade: $0.letter, minimumPercent: $0.minimumPercent, maximumPercent: nil, plusMinusPolicy: nil)
        }
        draft.issues = validated.warnings.map {
            .init(field: "Grading", reason: $0.message, possibleValues: [], sourcePage: $0.sourcePage, requiresUserReview: $0.requiresReview)
        }
        return draft
    }
}
