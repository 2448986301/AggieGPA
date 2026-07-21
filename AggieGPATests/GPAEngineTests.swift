import XCTest
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

    private func assertExcluded(_ grade: CourseGrade) {
        let result = GPAService.cumulative([input("TEST", 4, grade)])
        XCTAssertNil(result.gpa)
        XCTAssertEqual(result.attemptedUnits, 0)
    }

    private func input(_ code: String, _ units: Decimal, _ grade: CourseGrade) -> CourseCalculationInput {
        CourseCalculationInput(courseCode: code, units: units, grade: grade)
    }
}

