import XCTest
@testable import AggieGPA

@MainActor
final class SyllabusRuleParserTests: XCTestCase {
    func testRecognizesCommonPercentageFormats() {
        let result = SyllabusRuleParser.parse("""
        Homework: 20%
        Quizzes (10%)
        Labs — 20 percent
        Two Midterms, 15% each
        Final: 20%
        """)
        XCTAssertEqual(result.categories.count, 5)
        XCTAssertEqual(result.categories.first { $0.categoryType == .homework }?.weight, 20)
        XCTAssertEqual(result.categories.first { $0.categoryType == .midterm }?.weight, 30)
        XCTAssertFalse(result.requiresManualReview)
    }

    func testRecognizesTotalAndPointFormats() {
        let percentage = SyllabusRuleParser.parse("Midterm Exams: 30% total\nFinal: 70%")
        XCTAssertEqual(percentage.categories.first?.weight, 30)

        let points = SyllabusRuleParser.parse("Labs 200 points\nAssignments 150/1000 points")
        XCTAssertEqual(points.suggestedMethod, .totalPoints)
        XCTAssertEqual(points.categories.first { $0.categoryType == .lab }?.possiblePoints, 200)
        XCTAssertEqual(points.categories.first { $0.categoryType == .homework }?.possiblePoints, 1000)
    }

    func testDropLowestIsSuggested() {
        let result = SyllabusRuleParser.parse("Quizzes: 100%\nThe lowest quiz will be dropped")
        XCTAssertEqual(result.dropLowestCategoryNames, ["Quiz"])
    }

    func testReplacementAndWeightConflictRequireReview() {
        let result = SyllabusRuleParser.parse("Homework: 20%\nFinal: 25%\nFinal replaces lowest midterm")
        XCTAssertTrue(result.requiresManualReview)
        XCTAssertTrue(result.manualReviewReasons.contains { $0.contains("replacement") })
        XCTAssertTrue(result.manualReviewReasons.contains { $0.contains("not 100") })
    }

    func testMixedPointsAndWeightsRequiresReview() {
        let result = SyllabusRuleParser.parse("Homework: 20%\nLabs 200 points")
        XCTAssertEqual(result.suggestedMethod, .hybrid)
        XCTAssertTrue(result.manualReviewReasons.contains { $0.contains("mixes") })
    }

    func testLowOCRConfidenceRequiresReview() {
        let result = SyllabusRuleParser.parse("Homework: 100%", extractionConfidence: 0.6)
        XCTAssertTrue(result.manualReviewReasons.contains { $0.contains("confidence") })
    }

    func testManualFallbackNamesAdvancedPoliciesWithoutInventingValues() {
        let result = SyllabusRuleParser.parse("""
        Best 5 of 6 quizzes count.
        Late homework loses 10%.
        Attendance is required.
        Students must earn at least 50% on the final exam.
        Extra credit is available.
        """)

        XCTAssertTrue(result.manualReviewReasons.contains { $0.contains("best-N-of-M") })
        XCTAssertTrue(result.manualReviewReasons.contains { $0.contains("late-work") })
        XCTAssertTrue(result.manualReviewReasons.contains { $0.contains("attendance") })
        XCTAssertTrue(result.manualReviewReasons.contains { $0.contains("minimum-exam") })
        XCTAssertTrue(result.manualReviewReasons.contains { $0.contains("bonus") })
    }

    func testParsesGradeScaleBoundaries() {
        let result = SyllabusRuleParser.parse("Homework: 100%\nA >= 93\nA-: 90\nB+: 87")
        XCTAssertEqual(result.gradeBoundaries.map(\.letter), [.a, .aMinus, .bPlus])
    }

    func testOnDeviceDraftStillUsesDeterministicValidation() {
        let analysis = GradingAnalysis(
            gradingMode: .weightedCategories,
            categories: [
                .init(name: "Homework", type: .homework, weightPercent: 20, totalPoints: nil, dropLowestCount: 1, bestCount: nil, totalCount: nil, isExtraCredit: false, confidence: 0.9, evidence: []),
                .init(name: "Final", type: .finalExam, weightPercent: 25, totalPoints: nil, dropLowestCount: nil, bestCount: nil, totalCount: nil, isExtraCredit: false, confidence: 0.9, evidence: [])
            ],
            assignments: [],
            exams: [],
            gradingScale: [.init(letter: .a, minimumPercent: 93, confidence: 0.9, evidence: [])],
            totalWeight: 45,
            rules: [.init(kind: .replacementExam, description: "Final replaces a midterm", categoryName: "Midterm", count: nil, totalCount: nil, confidence: 0.8, evidence: [])],
            warnings: [],
            confidence: 0.9,
            evidence: []
        )
        let validated = GradingAnalysisValidator.validate(analysis)
        XCTAssertTrue(validated.warnings.contains { $0.code == "validator.weightTotal" })
        XCTAssertEqual(validated.totalWeight, 45)
        XCTAssertEqual(validated.rules.first?.kind, .replacementExam)
    }

    func testOpenSourceModelAvailabilityAlwaysExplainsNextStep() {
        XCTAssertFalse(OnDeviceSyllabusParser.availability().message(locale: Locale(identifier: "en")).isEmpty)
    }

    func testPinnedModelDownloadUsesOfficialRevisionWithoutAlternateXetQuery() {
        let url = LocalModelResourceManager.downloadURL
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "huggingface.co")
        XCTAssertTrue(url.path.contains(LocalModelResourceManager.pinnedRevision))
        XCTAssertNil(url.query, "The alternate download query previously redirected iOS to a failing TLS path.")
    }

    func testModelDownloadProgressIsBoundedAndDeterministic() {
        XCTAssertEqual(ModelDownloadProgress(receivedBytes: 245_700_016, expectedBytes: 491_400_032).fraction, 0.5)
        XCTAssertEqual(ModelDownloadProgress(receivedBytes: 600, expectedBytes: 500).fraction, 1)
        XCTAssertNil(ModelDownloadProgress(receivedBytes: 10, expectedBytes: -1).fraction)
    }

    func testValidatorDoesNotInventMissingWeight() {
        let analysis = GradingAnalysis(
            gradingMode: .weightedCategories,
            categories: [
                .init(name: "Homework", type: .homework, weightPercent: 20, totalPoints: nil, dropLowestCount: nil, bestCount: nil, totalCount: nil, isExtraCredit: false, confidence: 0.9, evidence: []),
                .init(name: "Final", type: .finalExam, weightPercent: nil, totalPoints: nil, dropLowestCount: nil, bestCount: nil, totalCount: nil, isExtraCredit: false, confidence: 0.7, evidence: [])
            ],
            assignments: [], exams: [], gradingScale: [], totalWeight: nil,
            rules: [], warnings: [], confidence: 0.8, evidence: []
        )
        let validated = GradingAnalysisValidator.validate(analysis)
        XCTAssertNil(validated.categories[1].weightPercent)
        XCTAssertEqual(validated.totalWeight, 20)
        XCTAssertTrue(validated.warnings.contains { $0.code == "validator.missingWeight" })
    }

    func testValidatorDeduplicatesCategoriesWithoutDiscardingEvidence() {
        let firstEvidence = GradingEvidence(sourceText: "Homework 20%", sourcePage: 2, confidence: 0.9)
        let secondEvidence = GradingEvidence(sourceText: "Homework includes ten sets", sourcePage: 4, confidence: 0.8)
        let categories = [
            AnalyzedGradingCategory(name: "Homework", type: .homework, weightPercent: 20, totalPoints: nil, dropLowestCount: nil, bestCount: nil, totalCount: nil, isExtraCredit: false, confidence: 0.9, evidence: [firstEvidence]),
            AnalyzedGradingCategory(name: " homework ", type: .homework, weightPercent: nil, totalPoints: 100, dropLowestCount: 1, bestCount: nil, totalCount: nil, isExtraCredit: false, confidence: 0.8, evidence: [secondEvidence])
        ]
        let validated = GradingAnalysisValidator.validate(.init(gradingMode: .mixed, categories: categories, assignments: [], exams: [], gradingScale: [], totalWeight: nil, rules: [], warnings: [], confidence: 0.85, evidence: []))
        XCTAssertEqual(validated.categories.count, 1)
        XCTAssertEqual(validated.categories[0].evidence.count, 2)
        XCTAssertEqual(validated.categories[0].dropLowestCount, 1)
        XCTAssertTrue(validated.warnings.contains { $0.code == "validator.duplicateCategory" })
    }

    func testImpossibleBestNOfMRequiresReview() {
        let category = AnalyzedGradingCategory(name: "Quizzes", type: .quiz, weightPercent: 100, totalPoints: nil, dropLowestCount: nil, bestCount: 6, totalCount: 5, isExtraCredit: false, confidence: 0.8, evidence: [])
        let validated = GradingAnalysisValidator.validate(.init(gradingMode: .weightedCategories, categories: [category], assignments: [], exams: [], gradingScale: [], totalWeight: 100, rules: [], warnings: [], confidence: 0.8, evidence: []))
        XCTAssertTrue(validated.warnings.contains { $0.code == "validator.impossibleBest" })
    }

    func testReconciliationPreservesConflictWarningInsteadOfSilentlyAveraging() {
        let preliminary = GradingAnalysis(
            gradingMode: .weightedCategories,
            categories: [.init(name: "Homework", type: .homework, weightPercent: 20, totalPoints: nil, dropLowestCount: nil, bestCount: nil, totalCount: nil, isExtraCredit: false, confidence: 0.8, evidence: [.init(sourceText: "Homework 20%", sourcePage: 2, confidence: 0.8)])],
            assignments: [], exams: [], gradingScale: [], totalWeight: 20, rules: [], warnings: [], confidence: 0.8, evidence: []
        )
        let reconciled = GradingAnalysis(
            gradingMode: .weightedCategories,
            categories: [.init(name: "Homework", type: .homework, weightPercent: 25, totalPoints: nil, dropLowestCount: nil, bestCount: nil, totalCount: nil, isExtraCredit: false, confidence: 0.8, evidence: [.init(sourceText: "Homework 25%", sourcePage: 5, confidence: 0.8)])],
            assignments: [], exams: [], gradingScale: [], totalWeight: 25, rules: [], warnings: [], confidence: 0.8, evidence: []
        )

        let result = GradingAnalysisValidator.reconciled([preliminary], with: reconciled)
        XCTAssertEqual(result.categories.first?.weightPercent, 25)
        XCTAssertTrue(result.warnings.contains { $0.code == "reconciliation.categoryConflict" })
    }

    func testNoAIProviderProducesReviewOnlyDraft() async throws {
        let document = SyllabusTextExtractor.Document(
            pages: [.init(number: 3, text: "Homework: 25%\nFinal: 75%", image: nil)],
            source: .pastedText
        )
        let result = try await NoAIProvider().analyze(document: document) { _ in }
        XCTAssertEqual(result.analysis.categories.count, 2)
        XCTAssertTrue(result.analysis.warnings.contains { $0.code == "localRules.reviewOnly" })
        XCTAssertEqual(result.analysis.categories.first?.evidence.first?.sourcePage, 3)
    }
}
