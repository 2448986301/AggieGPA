import XCTest
import SwiftData
@testable import AggieGPA

@MainActor
final class GPAEngineTests: XCTestCase {
    func testAPlusEqualsFourNotFourPointThree() { XCTAssertEqual(CourseGrade.aPlus.gradePointValue, 4) }
    func testAEqualsFour() { XCTAssertEqual(CourseGrade.a.gradePointValue, 4) }
    func testAMinusEqualsThreePointSeven() { XCTAssertEqual(CourseGrade.aMinus.gradePointValue, Decimal(string: "3.7")) }
    func testBPlusEqualsThreePointThree() { XCTAssertEqual(CourseGrade.bPlus.gradePointValue, Decimal(string: "3.3")) }
    func testCMinusEqualsOnePointSeven() { XCTAssertEqual(CourseGrade.cMinus.gradePointValue, Decimal(string: "1.7")) }
    func testDPlusEqualsOnePointThree() { XCTAssertEqual(CourseGrade.dPlus.gradePointValue, Decimal(string: "1.3")) }
    func testDMinusEqualsPointSeven() { XCTAssertEqual(CourseGrade.dMinus.gradePointValue, Decimal(string: "0.7")) }
    func testFEqualsZero() { XCTAssertEqual(CourseGrade.f.gradePointValue, 0) }

    func testPassDoesNotEnterGPA() { assertExcluded(.pass) }
    func testNoPassDoesNotEnterGPA() { assertExcluded(.noPass) }
    func testIncompleteDoesNotEnterGPA() { assertExcluded(.incomplete) }
    func testInProgressDoesNotEnterGPA() { assertExcluded(.inProgress) }
    func testNoGradeDoesNotEnterGPA() { assertExcluded(.noGrade) }

    func testWeightedGPAUsesUnits() {
        let courses = [input("A", 5, .a), input("B", 3, .b)]
        let result = GPAService.cumulative(courses)
        XCTAssertEqual(result.gradePoints, 29)
        XCTAssertEqual(result.attemptedUnits, 8)
        XCTAssertEqual(result.gpa, Decimal(29) / Decimal(8))
    }

    func testEmptyCourseListIsSafe() { XCTAssertEqual(GPAService.cumulative([]), .empty) }

    func testZeroGPAUnitsDoesNotDivideByZero() {
        let result = GPAService.cumulative([input("ZERO", 0, .a)])
        XCTAssertNil(result.gpa)
        XCTAssertEqual(result.attemptedUnits, 0)
    }

    func testDisplayRoundingDoesNotChangeInternalValue() {
        let exact = GPAService.cumulative([input("A", 1, .a), input("B", 2, .b)]).gpa
        XCTAssertEqual(exact, Decimal(10) / Decimal(3))
        XCTAssertEqual(DecimalFormatters.string(exact, precision: 3), "3.333")
    }

    func testWhatIfValueCopyDoesNotModifyOfficialInput() {
        let official = [input("CHE 002A", 5, .b)]
        var whatIf = official
        whatIf[0].grade = .a
        XCTAssertEqual(official[0].grade, .b)
        XCTAssertEqual(GPAService.cumulative(whatIf).gpa, 4)
    }

    func testWhatIfSavedInputCreatesCorrectOfficialResult() {
        let saved = CourseCalculationInput(courseCode: "CHE 002A", units: 5, grade: .aMinus)
        XCTAssertEqual(GPAService.cumulative([saved]).gpa, Decimal(string: "3.7"))
    }

    func testLiveGPAUsesCurrentEstimateWhenAllOfficialGradesAreNG() {
        let first = input("CHE", 4, .noGrade)
        let second = input("MAT", 4, .noGrade)
        let result = GPAService.live(
            [first, second],
            currentGrades: [first.id: .bPlus, second.id: .aMinus]
        )

        XCTAssertEqual(result.gpa, Decimal(string: "3.5"))
        XCTAssertEqual(result.attemptedUnits, 8)
        XCTAssertEqual(result.includedCourseCount, 2)
        XCTAssertNil(GPAService.cumulative([first, second]).gpa)
    }

    func testLiveGPAIsUnaffectedByChangingOfficialGradeToNG() {
        let inProgress = input("CHE", 4, .inProgress)
        let noGrade = CourseCalculationInput(
            id: inProgress.id,
            courseCode: inProgress.courseCode,
            units: inProgress.units,
            grade: .noGrade
        )
        let current = [inProgress.id: CourseGrade.b]

        XCTAssertEqual(GPAService.live([inProgress], currentGrades: current).gpa, 3)
        XCTAssertEqual(GPAService.live([noGrade], currentGrades: current).gpa, 3)
    }

    func testMixedFinalizedAndNGCoursesKeepLiveGPA() {
        let finalized = input("BIO", 4, .a)
        let pending = input("CHE", 4, .noGrade)
        let result = GPAService.live([finalized, pending], currentGrades: [pending.id: .b])

        XCTAssertEqual(result.gpa, Decimal(string: "3.5"))
        XCTAssertEqual(result.attemptedUnits, 8)
    }

    func testPhase15PlanningResolutionPerformance() {
        let inputs = (0..<120).map { index in
            GPAPlanningCourseInput(
                id: UUID(),
                courseCode: "COURSE \(index)",
                courseTitle: "Performance Fixture \(index)",
                units: 4,
                termID: nil,
                isIncludedInGPA: true,
                gradingBasis: .letter,
                officialGrade: .noGrade,
                currentGrade: .b,
                currentPercentage: 82,
                forecastGrade: .aMinus,
                forecastPercentage: 90,
                hasForecast: true
            )
        }
        let scenario = GPAPlanningScenarioInput(
            targetGPA: 3.5,
            selectedCourseIDs: Set(inputs.map(\.id)),
            assumedGrades: Dictionary(uniqueKeysWithValues: inputs.map { ($0.id, .aMinus) })
        )

        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]) {
            let snapshot = GPAPlanningEngine.resolve(
                inputs: inputs,
                scenario: scenario,
                fallbackTargetUnits: 12
            )
            XCTAssertEqual(snapshot.courses.count, inputs.count)
        }
    }

    func testPhase15PlanningInputPreparationPerformance() throws {
        let container = PersistentStoreService.makeContainer(inMemory: true).container
        let context = ModelContext(container)
        var courses: [CourseRecord] = []
        var policies: [CourseGradingPolicy] = []
        var categories: [GradingCategory] = []
        var items: [GradeItem] = []
        var scales: [GradeScale] = []
        var forecasts: [ForecastScenario] = []

        for index in 0..<80 {
            let course = CourseRecord(
                courseCode: "PERF \(index)",
                units: 4,
                grade: .noGrade
            )
            context.insert(course)
            courses.append(course)

            let policy = CourseGradingPolicy(course: course, targetPercentage: 90)
            let scale = GradeScale(course: course)
            let forecast = ForecastScenario(
                course: course,
                name: "Performance",
                assumedRemainingPercentage: 87,
                isSelectedForGPAForecast: true
            )
            context.insert(policy)
            context.insert(scale)
            context.insert(forecast)
            policies.append(policy)
            scales.append(scale)
            forecasts.append(forecast)

            for categoryIndex in 0..<4 {
                let category = GradingCategory(
                    course: course,
                    name: "Category \(categoryIndex)",
                    categoryType: .custom,
                    weight: 25,
                    sortOrder: categoryIndex
                )
                context.insert(category)
                categories.append(category)

                for itemIndex in 0..<8 {
                    let item = GradeItem(
                        course: course,
                        category: category,
                        title: "Item \(itemIndex)",
                        earnedPoints: 8,
                        possiblePoints: 10,
                        status: .graded
                    )
                    context.insert(item)
                    items.append(item)
                }
            }
        }
        try context.save()

        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]) {
            let inputs = GPAPlanningEngine.makeInputs(
                courses: courses,
                policies: policies,
                categories: categories,
                items: items,
                scales: scales,
                forecasts: forecasts
            )
            let snapshot = GPAPlanningEngine.resolve(
                inputs: inputs,
                scenario: GPAPlanningScenarioInput(targetGPA: 3.5),
                fallbackTargetUnits: 12
            )
            XCTAssertEqual(snapshot.courses.count, courses.count)
        }
    }

    private func assertExcluded(_ grade: CourseGrade) {
        let result = GPAService.cumulative([input("TEST", 4, grade)])
        XCTAssertNil(result.gpa)
        XCTAssertEqual(result.attemptedUnits, 0)
    }

    private func input(_ code: String, _ units: Decimal, _ grade: CourseGrade) -> CourseCalculationInput {
        CourseCalculationInput(courseCode: code, units: units, grade: grade)
    }
}
