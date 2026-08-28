import XCTest
@testable import AggieGPA

@MainActor
final class RepeatEngineTests: XCTestCase {
    func testRepeatReplacementExcludesOriginal() {
        let group = UUID()
        let first = repeated("CHE 002A", units: 5, grade: .f, group: group, order: 1, mode: .originalAttempt)
        let second = repeated("CHE 002A", units: 5, grade: .b, group: group, order: 2, mode: .secondAttempt)
        let evaluation = RepeatCourseEngine.evaluate([first, second])
        XCTAssertTrue(evaluation.excludedIDs.contains(first.id))
        XCTAssertTrue(evaluation.includedIDs.contains(second.id))
        XCTAssertEqual(evaluation.repeatUnitsUsed, 5)
    }

    func testRepeatBeyondSixteenUnitsIncludesBothAttempts() {
        var courses: [CourseCalculationInput] = []
        for index in 0..<4 {
            let group = UUID()
            courses.append(repeated("R\(index)", units: 4, grade: .f, group: group, order: 1, mode: .originalAttempt, sequence: Double(index * 10 + 1)))
            courses.append(repeated("R\(index)", units: 4, grade: .b, group: group, order: 2, mode: .secondAttempt, sequence: Double(index * 10 + 2)))
        }
        let overflow = UUID()
        let old = repeated("OVER", units: 4, grade: .f, group: overflow, order: 1, mode: .originalAttempt, sequence: 100)
        let latest = repeated("OVER", units: 4, grade: .a, group: overflow, order: 2, mode: .secondAttempt, sequence: 101)
        let evaluation = RepeatCourseEngine.evaluate(courses + [old, latest])
        XCTAssertTrue(evaluation.includedAfterLimit.contains(old.id))
        XCTAssertTrue(evaluation.includedAfterLimit.contains(latest.id))
        XCTAssertEqual(evaluation.repeatUnitsUsed, 16)
    }

    func testMultipleRepeatTriggersManualReview() {
        let group = UUID()
        let attempts = (1...3).map { repeated("BIS 002B", units: 5, grade: .f, group: group, order: $0, mode: .originalAttempt) }
        XCTAssertTrue(RepeatCourseEngine.evaluate(attempts).manualReviewGroupIDs.contains(group))
    }

    func testMismatchedUnitsTriggersManualReview() {
        let group = UUID()
        let one = repeated("UWP 007", units: 4, grade: .f, group: group, order: 1, mode: .originalAttempt)
        let two = repeated("UWP 007", units: 5, grade: .a, group: group, order: 2, mode: .secondAttempt)
        XCTAssertTrue(RepeatCourseEngine.evaluate([one, two]).manualReviewGroupIDs.contains(group))
    }

    private func repeated(_ code: String, units: Decimal, grade: CourseGrade, group: UUID,
                          order: Int, mode: RepeatHandlingMode, sequence: TimeInterval? = nil) -> CourseCalculationInput {
        CourseCalculationInput(courseCode: code, units: units, grade: grade,
                               repeatGroupID: group, repeatAttemptOrder: order, repeatHandlingMode: mode,
                               attemptedAt: Date(timeIntervalSince1970: sequence ?? Double(order)))
    }
}
