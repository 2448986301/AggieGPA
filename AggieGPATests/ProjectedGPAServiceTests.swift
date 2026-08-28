import XCTest
@testable import AggieGPA

@MainActor
final class ProjectedGPAServiceTests: XCTestCase {
    func testProjectedDoesNotChangeOfficialGPA() {
        let finished = CourseCalculationInput(courseCode: "MAT 021A", units: 4, grade: .a)
        let pending = CourseCalculationInput(courseCode: "CHE 002A", units: 5, grade: .inProgress)
        let result = ProjectedGPAService.calculate([finished, pending], projectedGrades: [pending.id: .b])
        XCTAssertEqual(result.official.gpa, 4)
        XCTAssertEqual(result.projected.gpa, Decimal(31) / 9)
        XCTAssertEqual(result.projectedCourseIDs, [pending.id])
    }

    func testOfficialGradeIsNeverOverriddenByProjection() {
        let course = CourseCalculationInput(courseCode: "CHE 002A", units: 5, grade: .c)
        let result = ProjectedGPAService.calculate([course], projectedGrades: [course.id: .a])
        XCTAssertEqual(result.official.gpa, 2)
        XCTAssertEqual(result.projected.gpa, 2)
        XCTAssertTrue(result.projectedCourseIDs.isEmpty)
    }

    func testProjectedQuarterScopesByTerm() {
        let fall = UUID(); let winter = UUID()
        let fallCourse = CourseCalculationInput(courseCode: "CHE", units: 4, grade: .inProgress, termID: fall)
        let winterCourse = CourseCalculationInput(courseCode: "MAT", units: 4, grade: .a, termID: winter)
        let result = ProjectedGPAService.calculate([fallCourse, winterCourse], projectedGrades: [fallCourse.id: .bPlus], termID: fall)
        XCTAssertEqual(result.official.gpa, nil)
        XCTAssertEqual(result.projected.gpa, Decimal(string: "3.3"))
    }

    func testProjectedGPAExistsForAllNGCoursesWhenForecastsExist() {
        let first = CourseCalculationInput(courseCode: "CHE", units: 4, grade: .noGrade)
        let second = CourseCalculationInput(courseCode: "MAT", units: 4, grade: .noGrade)
        let result = ProjectedGPAService.calculate(
            [first, second],
            projectedGrades: [first.id: .a, second.id: .bPlus]
        )

        XCTAssertEqual(result.projected.gpa, Decimal(string: "3.65"))
        XCTAssertEqual(result.projectedCourseIDs, [first.id, second.id])
        XCTAssertTrue(result.currentFallbackCourseIDs.isEmpty)
        XCTAssertNil(result.recorded.gpa)
    }

    func testProjectedGPAFallsBackToCurrentEstimateWithoutCallingItAProjection() {
        let pending = CourseCalculationInput(courseCode: "CHE", units: 4, grade: .noGrade)
        let result = ProjectedGPAService.calculate(
            [pending],
            projectedGrades: [:],
            currentGrades: [pending.id: .b]
        )

        XCTAssertEqual(result.projected.gpa, 3)
        XCTAssertTrue(result.projectedCourseIDs.isEmpty)
        XCTAssertEqual(result.currentFallbackCourseIDs, [pending.id])
        XCTAssertNil(result.recorded.gpa)
    }

    func testMixedFinalizedAndNGCoursesKeepProjectedAndRecordedSeparate() {
        let finalized = CourseCalculationInput(courseCode: "BIO", units: 4, grade: .a)
        let pending = CourseCalculationInput(courseCode: "CHE", units: 4, grade: .noGrade)
        let result = ProjectedGPAService.calculate(
            [finalized, pending],
            projectedGrades: [pending.id: .bPlus]
        )

        XCTAssertEqual(result.recorded.gpa, 4)
        XCTAssertEqual(result.projected.gpa, Decimal(string: "3.65"))
        XCTAssertEqual(result.projectedCourseIDs, [pending.id])
    }
}
