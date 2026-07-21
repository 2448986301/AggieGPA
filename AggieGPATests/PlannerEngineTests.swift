import XCTest
@testable import AggieGPA

@MainActor
final class PlannerEngineTests: XCTestCase {
    func testTargetGPAFormula() {
        let result = TargetGPAService.calculate(currentGPA: Decimal(35) / 10, currentUnits: 90,
                                                targetGPA: Decimal(36) / 10, futureUnits: 30)
        XCTAssertEqual(result?.requiredFutureGPA, Decimal(string: "3.9"))
        XCTAssertEqual(result?.isReachable, true)
    }

    func testUnreachableTargetIsFlagged() {
        let result = TargetGPAService.calculate(currentGPA: 3, currentUnits: 100,
                                                targetGPA: Decimal(39) / 10, futureUnits: 10)
        XCTAssertEqual(result?.isReachable, false)
    }

    func testMaximumReachableGPA() {
        let result = TargetGPAService.calculate(currentGPA: 3, currentUnits: 100, targetGPA: 4, futureUnits: 20)
        XCTAssertEqual(result?.maximumFinalGPA, Decimal(380) / Decimal(120))
    }

    func testFinalGradeWeightedCalculation() {
        let categories = [
            GradeCategoryInput(name: "Homework", weight: 40, earnedPoints: 90, possiblePoints: 100),
            GradeCategoryInput(name: "Midterm", weight: 30, earnedPoints: 80, possiblePoints: 100)
        ]
        let result = FinalGradeService.calculate(categories: categories, targetPercentage: 85, finalExamWeight: 30)
        XCTAssertEqual(result?.completedWeight, 70)
        XCTAssertEqual(result?.currentPercentage, Decimal(60) / Decimal(70) * 100)
    }

    func testFinalExamNeededScore() {
        let categories = [GradeCategoryInput(name: "Work", weight: 75, earnedPoints: 90, possiblePoints: 100)]
        let result = FinalGradeService.calculate(categories: categories, targetPercentage: 90, finalExamWeight: 25)
        XCTAssertEqual(result?.finalExamNeeded, 90)
    }

    func testImpossibleCourseTarget() {
        let categories = [GradeCategoryInput(name: "Work", weight: 90, earnedPoints: 50, possiblePoints: 100)]
        let result = FinalGradeService.calculate(categories: categories, targetPercentage: 90, finalExamWeight: 10)
        XCTAssertEqual(result?.targetIsReachable, false)
    }

    func testInvalidUnitsRejected() {
        XCTAssertFalse(InputValidator.validUnits(-1))
        XCTAssertFalse(InputValidator.validUnits(51))
    }

    func testInvalidGPARejected() {
        XCTAssertFalse(InputValidator.validGPA(Decimal(401) / 100))
        XCTAssertFalse(InputValidator.validGPA(-1))
    }

    func testInvalidWeightRejected() {
        XCTAssertFalse(InputValidator.validWeight(101))
        XCTAssertFalse(InputValidator.validWeight(-1))
    }
}
