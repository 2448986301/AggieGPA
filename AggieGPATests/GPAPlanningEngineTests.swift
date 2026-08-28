import XCTest
@testable import AggieGPA

@MainActor
final class GPAPlanningEngineTests: XCTestCase {
    func testAllNGWithCurrentGradesProducesCurrentGPA() {
        let first = input("CHE 002A", .noGrade, current: .bPlus)
        let second = input("MAT 021A", .noGrade, current: .aMinus)
        let snapshot = GPAPlanningEngine.resolve(
            inputs: [first, second],
            scenario: GPAPlanningScenarioInput(targetGPA: 3.5)
        )

        XCTAssertEqual(snapshot.current.gpa, Decimal(string: "3.5"))
        XCTAssertNil(snapshot.final)
        XCTAssertEqual(snapshot.eligibleFinalGradeCount, 0)
        XCTAssertEqual(snapshot.eligibleCourseCount, 2)
        XCTAssertTrue(snapshot.hasPendingFinalGrades)
        XCTAssertEqual(snapshot.courses.first(where: { $0.courseCode == "CHE 002A" })?.stage, .current)
    }

    func testAllNGWithForecastsProducesProjectedGPA() {
        let first = input("CHE 002A", .noGrade, current: .bPlus, forecast: .a)
        let second = input("MAT 021A", .noGrade, current: .aMinus, forecast: .bPlus)
        let snapshot = GPAPlanningEngine.resolve(
            inputs: [first, second],
            scenario: GPAPlanningScenarioInput(targetGPA: 3.6)
        )

        XCTAssertEqual(snapshot.projected.gpa, Decimal(string: "3.65"))
        XCTAssertNil(snapshot.final)
        XCTAssertEqual(snapshot.eligibleFinalGradeCount, 0)
        XCTAssertEqual(snapshot.eligibleCourseCount, 2)
        XCTAssertEqual(snapshot.courses.filter { $0.stage == .projected }.count, 2)
    }

    func testFinalGPAOnlyAppearsWhenAllEligibleCoursesAreFinal() {
        let finalized = input("BIO 001", .a)
        let pending = input("CHE 002A", .noGrade, current: .b)
        let mixed = GPAPlanningEngine.resolve(
            inputs: [finalized, pending],
            scenario: GPAPlanningScenarioInput(targetGPA: 3.5)
        )
        XCTAssertNil(mixed.final)
        XCTAssertEqual(mixed.eligibleFinalGradeCount, 1)
        XCTAssertEqual(mixed.eligibleCourseCount, 2)
        XCTAssertEqual(mixed.courses.first(where: { $0.courseCode == "BIO 001" })?.stage, .final)
        XCTAssertEqual(mixed.courses.first(where: { $0.courseCode == "CHE 002A" })?.stage, .current)

        let completed = GPAPlanningEngine.resolve(
            inputs: [finalized, input("CHE 002A", .b)],
            scenario: GPAPlanningScenarioInput(targetGPA: 3.5)
        )
        XCTAssertEqual(completed.final?.gpa, Decimal(string: "3.5"))
        XCTAssertEqual(completed.eligibleFinalGradeCount, 2)
        XCTAssertEqual(completed.eligibleCourseCount, 2)
        XCTAssertTrue(completed.allEligibleCoursesFinalized)
    }

    func testFinalGradeReplacesOnlyThatCourseAndNGKeepsCurrentAndProjectedValues() {
        let finalized = input("BIO 001", .a, current: .c)
        let pending = input("CHE 002A", .noGrade, current: .bPlus, forecast: .aMinus)
        let mixed = GPAPlanningEngine.resolve(
            inputs: [finalized, pending],
            scenario: GPAPlanningScenarioInput(targetGPA: 3.8)
        )

        XCTAssertEqual(mixed.current.gpa, Decimal(string: "3.65"))
        XCTAssertEqual(mixed.projected.gpa, Decimal(string: "3.85"))
        XCTAssertNil(mixed.final)
        XCTAssertEqual(mixed.courses.first(where: { $0.courseCode == "BIO 001" })?.finalGrade, .a)
        XCTAssertEqual(mixed.courses.first(where: { $0.courseCode == "BIO 001" })?.stage, .final)
        XCTAssertEqual(mixed.courses.first(where: { $0.courseCode == "CHE 002A" })?.currentGrade, .bPlus)
        XCTAssertEqual(mixed.courses.first(where: { $0.courseCode == "CHE 002A" })?.projectedGrade, .aMinus)
        XCTAssertEqual(mixed.courses.first(where: { $0.courseCode == "CHE 002A" })?.stage, .projected)

        let allFinal = GPAPlanningEngine.resolve(
            inputs: [finalized, input("CHE 002A", .aMinus)],
            scenario: GPAPlanningScenarioInput(targetGPA: 3.8)
        )
        XCTAssertEqual(allFinal.final?.gpa, Decimal(string: "3.85"))
    }

    func testScenarioGradeChangesProjectedGPAWithoutChangingCurrent() {
        let course = input("UWP 007", .noGrade, current: .bPlus)
        let base = GPAPlanningEngine.resolve(
            inputs: [course],
            scenario: GPAPlanningScenarioInput(targetGPA: 3.8)
        )
        let planned = GPAPlanningEngine.resolve(
            inputs: [course],
            scenario: GPAPlanningScenarioInput(targetGPA: 3.8, assumedGrades: [course.id: .a])
        )

        XCTAssertEqual(base.current.gpa, planned.current.gpa)
        XCTAssertEqual(base.projected.gpa, Decimal(string: "3.3"))
        XCTAssertEqual(planned.projected.gpa, 4)
        XCTAssertNotEqual(base.projected.gpa, planned.projected.gpa)
    }

    func testLetterOnlyScenarioUsesScaleBoundaryForProjectedPercentage() {
        let course = GPAPlanningCourseInput(
            id: UUID(), courseCode: "BIS 002B", courseTitle: "", units: 5, termID: nil,
            isIncludedInGPA: true, gradingBasis: .letter, officialGrade: .noGrade,
            currentGrade: .c, currentPercentage: 73.93,
            forecastGrade: nil, forecastPercentage: nil, hasForecast: false,
            gradeScale: CourseGradeScaleInput(boundaries: [
                .init(letter: .a, minimumPercentage: 93),
                .init(letter: .bPlus, minimumPercentage: 87),
                .init(letter: .c, minimumPercentage: 70),
                .init(letter: .f, minimumPercentage: 0),
            ])
        )

        let state = GPAPlanningEngine.resolve(
            inputs: [course],
            scenario: GPAPlanningScenarioInput(targetGPA: 3.5, assumedGrades: [course.id: .a])
        ).courses[0]

        XCTAssertGreaterThan(state.currentPercentage ?? 0, 73.92)
        XCTAssertLessThan(state.currentPercentage ?? 0, 73.94)
        XCTAssertEqual(state.currentGrade, .c)
        XCTAssertEqual(state.projectedGrade, .a)
        XCTAssertEqual(state.projectedPercentage, 93)
        XCTAssertTrue(state.projectedPercentageIsBoundary)
    }

    func testForecastPercentageRemainsAnExactProjectedPercentage() {
        let course = GPAPlanningCourseInput(
            id: UUID(), courseCode: "CHE 002A", courseTitle: "", units: 5, termID: nil,
            isIncludedInGPA: true, gradingBasis: .letter, officialGrade: .noGrade,
            currentGrade: .bPlus, currentPercentage: 87.43,
            forecastGrade: .aMinus, forecastPercentage: 90.25, hasForecast: true,
            gradeScale: CourseGradeScaleInput(boundaries: [
                .init(letter: .aMinus, minimumPercentage: 90),
                .init(letter: .bPlus, minimumPercentage: 87),
            ])
        )

        let state = GPAPlanningEngine.resolve(
            inputs: [course],
            scenario: GPAPlanningScenarioInput(targetGPA: 3.5)
        ).courses[0]

        XCTAssertEqual(state.projectedGrade, .aMinus)
        XCTAssertEqual(state.projectedPercentage, Decimal(string: "90.25"))
        XCTAssertFalse(state.projectedPercentageIsBoundary)
    }

    func testTargetAndScopeAreStoredAsInputsNotAStaleResult() {
        let first = input("CHE", .noGrade, current: .bPlus)
        let second = input("MAT", .noGrade, current: .aMinus)
        let snapshot = GPAPlanningEngine.resolve(
            inputs: [first, second],
            scenario: GPAPlanningScenarioInput(targetGPA: 3.9, selectedCourseIDs: [first.id], assumedGrades: [first.id: .a])
        )

        XCTAssertEqual(snapshot.selectedCourseIDs, [first.id])
        XCTAssertEqual(snapshot.targetGPA, Decimal(string: "3.9"))
        XCTAssertEqual(snapshot.projected.gpa, 4)
        XCTAssertEqual(snapshot.courses.map(\.courseCode), ["CHE"])
    }

    private func input(
        _ code: String,
        _ official: CourseGrade,
        current: CourseGrade? = nil,
        forecast: CourseGrade? = nil
    ) -> GPAPlanningCourseInput {
        GPAPlanningCourseInput(
            id: UUID(), courseCode: code, courseTitle: "", units: 4, termID: nil,
            isIncludedInGPA: true, gradingBasis: .letter, officialGrade: official,
            currentGrade: current, currentPercentage: nil, forecastGrade: forecast,
            forecastPercentage: forecast == nil ? nil : 90, hasForecast: forecast != nil
        )
    }
}
