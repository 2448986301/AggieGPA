import XCTest
@testable import AggieGPA

final class CourseGradeCalculationEngineTests: XCTestCase {
    func testWeightedCategoriesSeparatesGradedAverageAndEarnedCredit() {
        let homework = category("Homework", type: .homework, weight: 40, items: [
            item("Homework 1", earned: 18, possible: 20, status: .graded)
        ])
        let final = category("Final", type: .finalExam, weight: 60, items: [
            item("Final Exam", type: .finalExam, possible: 100)
        ])

        let result = calculate(.weightedCategories, categories: [homework, final])

        XCTAssertEqual(result.gradedWorkAverage, 90)
        XCTAssertEqual(result.gradedWeight, 40)
        XCTAssertEqual(result.remainingWeight, 60)
        XCTAssertEqual(result.earnedCourseCredit, 36)
        XCTAssertEqual(result.currentLetterGrade, .aMinus)
    }

    func testTotalPointsExcludesUngradedFromAverageButTracksRemaining() {
        let result = calculate(.totalPoints, categories: [category("All", weight: 100, items: [
            item("Quiz", earned: 18, possible: 20, status: .graded),
            item("Final", type: .finalExam, possible: 80)
        ])])

        XCTAssertEqual(result.gradedWorkAverage, 90)
        XCTAssertEqual(result.earnedCourseCredit, 18)
        XCTAssertEqual(result.gradedWeight, 20)
        XCTAssertEqual(result.remainingWeight, 80)
    }

    func testHybridCombinesWeightedAndDirectPointPortions() {
        let weighted = category("Projects", weight: 60, items: [
            item("Project", earned: 90, possible: 100, status: .graded)
        ])
        let direct = item("Direct Final", type: .finalExam, earned: 20, possible: 40, status: .graded)
        let result = calculate(.hybrid, categories: [weighted], unassigned: [direct])

        XCTAssertEqual(result.gradedWeight, 100)
        XCTAssertEqual(result.earnedCourseCredit, 74)
        XCTAssertEqual(result.gradedWorkAverage, 74)
    }

    func testEqualItemsDoesNotLetLargePointItemDominate() {
        let quizzes = category("Quizzes", weight: 100, mode: .equalItems, items: [
            item("Quiz 1", earned: 9, possible: 10, status: .graded),
            item("Quiz 2", earned: 50, possible: 100, status: .graded)
        ])
        let result = calculate(.weightedCategories, categories: [quizzes])
        XCTAssertEqual(result.gradedWorkAverage, 70)
    }

    func testSubmittedButUngradedIsNeverZero() {
        let submitted = item("Essay", possible: 20, status: .submitted)
        let result = calculate(.totalPoints, categories: [category("All", weight: 100, items: [submitted])])
        XCTAssertNil(result.gradedWorkAverage)
        XCTAssertEqual(result.earnedCourseCredit, 0)
        XCTAssertEqual(result.remainingWeight, 100)
    }

    func testStudentCoreFlowUpdatesCurrentGradeAndExcludesUngradedHomework() {
        let homework = category("Homework", type: .homework, weight: 20, items: [
            item("Homework 1", type: .homework, earned: 18, possible: 20, status: .graded),
            item("Homework 2", type: .homework, earned: 19, possible: 20, status: .graded),
            item("Homework 3", type: .homework, possible: 20, status: .upcoming)
        ])
        let labs = category("Labs", type: .lab, weight: 20, items: [
            item("Lab 1", type: .lab, earned: 45, possible: 50, status: .graded)
        ])
        let midterms = category("Midterms", type: .midterm, weight: 30, items: [
            item("Midterm 1", type: .midterm, earned: 84, possible: 100, status: .graded)
        ])
        let final = category("Final Exam", type: .finalExam, weight: 30, items: [
            item("Final Exam", type: .finalExam, possible: 100, status: .upcoming)
        ])

        let before = calculate(.weightedCategories, categories: [homework, labs, midterms, final])
        XCTAssertEqual(before.categoryBreakdown.first?.average, Decimal(string: "92.5"))
        XCTAssertEqual(before.calculatedCurrentPercentage, Decimal(string: "87.684210526315789473684210526315789473"))
        // Homework 3 reduces completion progress, but it is excluded from the 92.5% homework average.
        XCTAssertEqual(before.gradedWeight, Decimal(string: "63.333333333333333333333333333333333333"))

        let changedHomework = category("Homework", type: .homework, weight: 20, items: [
            item("Homework 1", type: .homework, earned: 20, possible: 20, status: .graded),
            item("Homework 2", type: .homework, earned: 19, possible: 20, status: .graded),
            item("Homework 3", type: .homework, possible: 20, status: .upcoming)
        ])
        let after = calculate(.weightedCategories, categories: [changedHomework, labs, midterms, final])
        XCTAssertGreaterThan(after.calculatedCurrentPercentage ?? 0, before.calculatedCurrentPercentage ?? 0)
        XCTAssertEqual(after.gradedWeight, Decimal(string: "63.333333333333333333333333333333333333"))
    }

    func testMissingCountsZeroOnlyAfterPolicyConfirmation() {
        let missing = item("Quiz", possible: 10, status: .missing)
        let category = category("Quizzes", weight: 100, items: [missing])
        let unconfirmed = calculate(.weightedCategories, categories: [category],
                                    missingPolicy: .countMissingAsZero, missingConfirmed: false)
        XCTAssertNil(unconfirmed.gradedWorkAverage)
        XCTAssertTrue(unconfirmed.issues.contains(.missingPolicyNeedsConfirmation))

        let confirmed = calculate(.weightedCategories, categories: [category],
                                  missingPolicy: .countMissingAsZero, missingConfirmed: true)
        XCTAssertEqual(confirmed.gradedWorkAverage, 0)
        XCTAssertEqual(confirmed.gradedWeight, 100)
    }

    func testExcusedAndDroppedItemsDoNotCount() {
        let active = item("Active", earned: 8, possible: 10, status: .graded)
        let excused = item("Excused", possible: 100, status: .excused)
        let dropped = item("Dropped", earned: 0, possible: 100, status: .dropped)
        let result = calculate(.totalPoints, categories: [category("All", weight: 100,
                                                                   items: [active, excused, dropped])])
        XCTAssertEqual(result.gradedWorkAverage, 80)
        XCTAssertEqual(result.gradedWeight, 100)
        XCTAssertEqual(result.categoryBreakdown.first?.droppedItems, 1)
    }

    func testDropLowestRemovesLowestScoredItem() {
        let quizzes = category("Quizzes", weight: 100, drop: 1, items: [
            item("Low", earned: 5, possible: 10, status: .graded),
            item("High", earned: 9, possible: 10, status: .graded)
        ])
        let result = calculate(.weightedCategories, categories: [quizzes])
        XCTAssertEqual(result.gradedWorkAverage, 90)
        XCTAssertEqual(result.categoryBreakdown.first?.droppedItems, 1)
    }

    func testExtraCreditRaisesAverageWithoutAddingDenominator() {
        let regular = item("Exam", earned: 90, possible: 100, status: .graded)
        let bonus = GradeItemCalculationInput(title: "Bonus", earnedPoints: 5, possiblePoints: 5,
                                              status: .graded, isExtraCredit: true)
        let result = calculate(.totalPoints, categories: [category("All", weight: 100,
                                                                   items: [regular, bonus])])
        XCTAssertEqual(result.gradedWorkAverage, 95)
        XCTAssertEqual(result.earnedCourseCredit, 95)
    }

    func testPercentageOverrideAndMultiplierAreApplied() {
        let override = GradeItemCalculationInput(title: "Lab", earnedPoints: nil, possiblePoints: 0,
                                                 percentageOverride: 80, status: .graded, multiplier: 2)
        let perfect = item("Quiz", earned: 10, possible: 10, status: .graded)
        let result = calculate(.weightedCategories, categories: [
            category("Equal", weight: 100, mode: .equalItems, items: [override, perfect])
        ])
        XCTAssertEqual(result.gradedWorkAverage, Decimal(string: "86.66666666666666666666666666666666666666"))
    }

    func testInvalidWeightsRequireManualReviewAndSuppressForecast() {
        let result = calculate(.weightedCategories, categories: [
            category("Homework", weight: 80, items: [item("HW", earned: 8, possible: 10, status: .graded)])
        ], forecast: CourseForecastInput(assumedRemainingPercentage: 90))
        XCTAssertTrue(result.requiresManualReview)
        XCTAssertNil(result.projectedFinalPercentage)
        XCTAssertTrue(result.issues.contains(.weightTotalBelow100(80)))
    }

    func testZeroPossiblePointsIsReportedWithoutDivisionByZero() {
        let result = calculate(.totalPoints, categories: [category("All", weight: 100, items: [
            item("Broken", earned: 5, possible: 0, status: .graded)
        ])])
        XCTAssertNil(result.gradedWorkAverage)
        XCTAssertTrue(result.issues.contains(.invalidPossiblePoints("Broken")))
    }

    func testScoreAboveMaximumIsPreserved() {
        let result = calculate(.totalPoints, categories: [category("All", weight: 100, items: [
            item("Bonus Exam", earned: 110, possible: 100, status: .graded)
        ])])
        XCTAssertEqual(result.gradedWorkAverage, 110)
        XCTAssertEqual(result.currentLetterGrade, .a)
    }

    func testForecastAndFinalNeededWhenFinalIsOnlyRemainingItem() {
        let midterm = category("Completed", weight: 50, items: [
            item("Midterm", earned: 90, possible: 100, status: .graded)
        ])
        let final = category("Final", type: .finalExam, weight: 50, items: [
            item("Final Exam", type: .finalExam, possible: 100)
        ])
        let result = calculate(.weightedCategories, categories: [midterm, final], target: 90,
                               forecast: CourseForecastInput(assumedRemainingPercentage: 80))
        XCTAssertEqual(result.projectedFinalPercentage, 85)
        XCTAssertEqual(result.requiredRemainingAverage, 90)
        XCTAssertEqual(result.finalExamNeeded, 90)
        XCTAssertEqual(result.targetFeasibility, .achievable)
    }

    func testMultipleRemainingItemsUsesRequiredAverageNotFinalNeeded() {
        let completed = category("Completed", weight: 40, items: [
            item("Midterm", earned: 90, possible: 100, status: .graded)
        ])
        let remaining = category("Remaining", weight: 60, items: [
            item("Homework", type: .homework, possible: 20),
            item("Final", type: .finalExam, possible: 80)
        ])
        let result = calculate(.weightedCategories, categories: [completed, remaining], target: 90)
        XCTAssertEqual(result.requiredRemainingAverage, 90)
        XCTAssertNil(result.finalExamNeeded)
    }

    func testImpossibleAndAlreadyReachedTargets() {
        let course = category("Completed", weight: 100, items: [
            item("Exam", earned: 95, possible: 100, status: .graded)
        ])
        let reached = calculate(.weightedCategories, categories: [course], target: 90)
        XCTAssertEqual(reached.targetFeasibility, .alreadyReached)
        XCTAssertEqual(reached.requiredRemainingAverage, 0)

        let completed = category("Completed", weight: 90, items: [
            item("Work", earned: 50, possible: 100, status: .graded)
        ])
        let remaining = category("Final", type: .finalExam, weight: 10, items: [
            item("Final", type: .finalExam, possible: 100)
        ])
        let impossible = calculate(.weightedCategories, categories: [completed, remaining], target: 90)
        XCTAssertEqual(impossible.targetFeasibility, .impossible)
        XCTAssertGreaterThan(impossible.requiredRemainingAverage ?? 0, 100)
    }

    func testCourseSpecificGradeScalesCanDiffer() {
        let work = category("All", weight: 100, items: [
            item("Exam", earned: 92, possible: 100, status: .graded)
        ])
        let common = calculate(.weightedCategories, categories: [work])
        let strictScale = CourseGradeScaleInput(boundaries: [
            GradeScaleBoundary(letter: .a, minimumPercentage: 95),
            GradeScaleBoundary(letter: .aMinus, minimumPercentage: 93),
            GradeScaleBoundary(letter: .bPlus, minimumPercentage: 90),
            GradeScaleBoundary(letter: .f, minimumPercentage: 0)
        ])
        let strict = CourseGradeCalculationEngine.calculate(CourseGradeCalculationInput(
            gradingMethod: .weightedCategories, categories: [work], gradeScale: strictScale
        ))
        XCTAssertEqual(common.currentLetterGrade, .aMinus)
        XCTAssertEqual(strict.currentLetterGrade, .bPlus)
    }

    private func calculate(
        _ method: GradingMethod,
        categories: [GradingCategoryCalculationInput],
        unassigned: [GradeItemCalculationInput] = [],
        missingPolicy: MissingItemPolicy = .excludeUntilGraded,
        missingConfirmed: Bool = false,
        target: Decimal? = nil,
        forecast: CourseForecastInput? = nil
    ) -> CourseGradeCalculationResult {
        CourseGradeCalculationEngine.calculate(CourseGradeCalculationInput(
            gradingMethod: method, missingItemPolicy: missingPolicy,
            missingPolicyConfirmed: missingConfirmed, categories: categories,
            unassignedItems: unassigned, gradeScale: standardScale,
            targetPercentage: target, forecast: forecast
        ))
    }

    private var standardScale: CourseGradeScaleInput {
        CourseGradeScaleInput(boundaries: [
            GradeScaleBoundary(letter: .a, minimumPercentage: 93),
            GradeScaleBoundary(letter: .aMinus, minimumPercentage: 90),
            GradeScaleBoundary(letter: .bPlus, minimumPercentage: 87),
            GradeScaleBoundary(letter: .b, minimumPercentage: 83),
            GradeScaleBoundary(letter: .c, minimumPercentage: 70),
            GradeScaleBoundary(letter: .d, minimumPercentage: 60),
            GradeScaleBoundary(letter: .f, minimumPercentage: 0)
        ])
    }

    private func category(
        _ name: String, type: GradeCategoryType = .custom, weight: Decimal,
        mode: CategoryCalculationMode = .totalPoints, drop: Int = 0,
        items: [GradeItemCalculationInput]
    ) -> GradingCategoryCalculationInput {
        GradingCategoryCalculationInput(name: name, categoryType: type, weight: weight,
                                        calculationMode: mode, dropLowestCount: drop, items: items)
    }

    private func item(
        _ title: String, type: GradeCategoryType = .custom,
        earned: Decimal? = nil, possible: Decimal,
        status: GradeItemStatus = .upcoming
    ) -> GradeItemCalculationInput {
        GradeItemCalculationInput(title: title, categoryType: type, earnedPoints: earned,
                                  possiblePoints: possible, status: status)
    }
}
