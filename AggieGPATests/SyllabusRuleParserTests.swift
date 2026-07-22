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

    func testParsesGradeScaleBoundaries() {
        let result = SyllabusRuleParser.parse("Homework: 100%\nA >= 93\nA-: 90\nB+: 87")
        XCTAssertEqual(result.gradeBoundaries.map(\.letter), [.a, .aMinus, .bPlus])
    }

    func testOnDeviceDraftStillUsesDeterministicValidation() {
        let draft = ModelSyllabusDraft(
            categories: [
                ModelSyllabusCategory(name: "Homework", weight: 20, possiblePoints: nil, dropLowestCount: 1),
                ModelSyllabusCategory(name: "Final", weight: 25, possiblePoints: nil, dropLowestCount: 0)
            ],
            gradeBoundaries: ["A: 93"],
            complexRules: ["Final replaces a midterm"]
        )
        let result = OnDeviceSyllabusParser.validated(draft, originalText: "private original syllabus text")
        XCTAssertTrue(result.requiresManualReview)
        XCTAssertTrue(result.manualReviewReasons.contains { $0.contains("not 100") })
        XCTAssertTrue(result.manualReviewReasons.contains { $0.contains("On-device model flagged") })
        XCTAssertEqual(result.sourceText, "private original syllabus text")
    }

    func testFoundationModelAvailabilityAlwaysExplainsFallback() {
        XCTAssertFalse(OnDeviceSyllabusParser.availability().message.isEmpty)
    }
}
