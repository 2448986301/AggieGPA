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
        XCTAssertEqual(before.calculatedCurrentPercentage, Decimal(string: "88.14285714285714285714285714285714285714"))
        // Homework 3 is excluded from both the homework average and the current course grade.
        XCTAssertEqual(before.gradedWeight, 70)

        let changedHomework = category("Homework", type: .homework, weight: 20, items: [
            item("Homework 1", type: .homework, earned: 20, possible: 20, status: .graded),
            item("Homework 2", type: .homework, earned: 19, possible: 20, status: .graded),
            item("Homework 3", type: .homework, possible: 20, status: .upcoming)
        ])
        let after = calculate(.weightedCategories, categories: [changedHomework, labs, midterms, final])
        XCTAssertGreaterThan(after.calculatedCurrentPercentage ?? 0, before.calculatedCurrentPercentage ?? 0)
        XCTAssertEqual(after.gradedWeight, 70)
    }

    func testMissingCountsZeroOnlyAfterPolicyConfirmation() {
        let missing = item("Quiz", possible: 10, status: .missing)
        let category = category("Quizzes", weight: 100, items: [missing])
        let unconfirmed = calculate(.weightedCategories, categories: [category],
                                    missingPolicy: .countMissingAsZero, missingConfirmed: false,
                                    target: 90,
                                    forecast: CourseForecastInput(assumedRemainingPercentage: 80))
        XCTAssertNil(unconfirmed.gradedWorkAverage)
        XCTAssertTrue(unconfirmed.requiresManualReview)
        XCTAssertTrue(unconfirmed.issues.contains(.missingPolicyNeedsConfirmation))
        XCTAssertNil(unconfirmed.projectedFinalPercentage)
        XCTAssertEqual(unconfirmed.targetFeasibility, .manualReviewRequired)

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

    func testHybridNegativeCategoryWeightRequiresManualReviewAndSuppressesForecast() {
        let result = calculate(.hybrid, categories: [
            category("Projects", weight: 60, items: [
                item("Project", earned: 90, possible: 100, status: .graded)
            ]),
            category("Invalid", weight: -10, items: [
                item("Broken", earned: 10, possible: 10, status: .graded)
            ]),
        ], unassigned: [item("Direct Final", type: .finalExam, possible: 40)],
           forecast: CourseForecastInput(assumedRemainingPercentage: 90))

        XCTAssertTrue(result.requiresManualReview)
        XCTAssertNil(result.projectedFinalPercentage)
        XCTAssertNil(result.bestPossiblePercentage)
        XCTAssertTrue(result.issues.contains(.invalidCategoryWeight("Invalid")))
    }

    func testDropLowestThatRemovesEveryUpcomingItemRequiresManualReview() {
        let result = calculate(.weightedCategories, categories: [
            category("Quizzes", weight: 100, mode: .equalItems, drop: 1, items: [
                item("Quiz 1", possible: 10)
            ])
        ], target: 90, forecast: CourseForecastInput(assumedRemainingPercentage: 80))

        XCTAssertTrue(result.requiresManualReview)
        XCTAssertTrue(result.issues.contains(.dropCountRemovesAll("Quizzes")))
        XCTAssertNil(result.projectedFinalPercentage)
        XCTAssertNil(result.bestPossiblePercentage)
        XCTAssertNil(result.worstPossiblePercentage)
        XCTAssertNil(result.requiredRemainingAverage)
        XCTAssertEqual(result.targetFeasibility, .manualReviewRequired)
    }

    func testTotalPointsPreservesCategoryLevelExtraCredit() {
        let regular = category("Course", weight: 100, items: [
            item("Exam", earned: 90, possible: 100, status: .graded)
        ])
        let bonus = GradingCategoryCalculationInput(
            name: "Bonus", weight: 0, isExtraCredit: true, items: [
                item("Bonus Quiz", earned: 5, possible: 5, status: .graded)
            ]
        )

        let result = calculate(.totalPoints, categories: [regular, bonus])

        XCTAssertEqual(result.calculatedCurrentPercentage, 95)
        XCTAssertEqual(result.earnedCourseCredit, 95)
        XCTAssertEqual(result.gradedWeight, 100)
    }

    func testBreakdownContributionBasisMatchesPointsAndHybridMath() throws {
        let points = calculate(.totalPoints, categories: [
            category("Course", weight: 100, items: [
                item("Homework", earned: 18, possible: 20, status: .graded),
                item("Final", possible: 80),
            ])
        ])
        let pointsBreakdown = try XCTUnwrap(points.categoryBreakdown.first)
        XCTAssertEqual(pointsBreakdown.average, 90)
        XCTAssertEqual(pointsBreakdown.contributionBasis, 20)
        XCTAssertEqual(pointsBreakdown.contribution, 18)

        let hybrid = calculate(.hybrid, categories: [
            category("Projects", weight: 60, items: [
                item("Project 1", earned: 90, possible: 100, status: .graded),
                item("Project 2", possible: 100),
            ]),
            GradingCategoryCalculationInput(name: "Direct", weight: 0, items: [
                item("Quiz", earned: 20, possible: 40, status: .graded),
                item("Final", possible: 40),
            ]),
        ])
        let projects = try XCTUnwrap(hybrid.categoryBreakdown.first { $0.name == "Projects" })
        XCTAssertEqual(projects.average, 90)
        XCTAssertEqual(projects.contributionBasis, 30)
        XCTAssertEqual(projects.contribution, 27)
        let direct = try XCTUnwrap(hybrid.categoryBreakdown.first { $0.name == "Direct Points" })
        XCTAssertEqual(direct.average, 50)
        XCTAssertEqual(direct.contributionBasis, 20)
        XCTAssertEqual(direct.contribution, 10)
    }

    func testFutureCategoryExtraCreditChangesProjectionWithoutDilutingCurrent() throws {
        let bonusID = UUID(uuidString: "00000000-0000-0000-0000-000000000099")!
        let regular = category("Course", weight: 100, items: [
            item("Exam", earned: 90, possible: 100, status: .graded)
        ])
        let bonus = GradingCategoryCalculationInput(
            name: "Bonus", weight: 0, isExtraCredit: true, items: [
                GradeItemCalculationInput(id: bonusID, title: "Bonus Quiz", possiblePoints: 5)
            ]
        )
        let input = CourseGradeCalculationInput(
            gradingMethod: .totalPoints,
            categories: [regular, bonus],
            gradeScale: standardScale,
            forecast: CourseForecastInput(assumedRemainingPercentage: 100)
        )

        let result = CourseGradeCalculationEngine.calculate(input)
        XCTAssertEqual(result.calculatedCurrentPercentage, 90)
        XCTAssertEqual(result.earnedCourseCredit, 90)
        XCTAssertEqual(result.projectedFinalPercentage, 95)
        XCTAssertEqual(result.bestPossiblePercentage, 95)
        XCTAssertEqual(result.worstPossiblePercentage, 90)

        let opportunity = try XCTUnwrap(CourseGradeOpportunityEngine.biggestOpportunity(for: input))
        XCTAssertEqual(opportunity.itemID, bonusID)
        XCTAssertEqual(opportunity.courseImpact, 5)
    }

    func testWeightedCategoryExtraCreditAddsBonusWithoutDilutingBaseWeights() throws {
        let bonusID = UUID(uuidString: "00000000-0000-0000-0000-000000000098")!
        let input = CourseGradeCalculationInput(
            gradingMethod: .weightedCategories,
            categories: [
                category("Course", weight: 100, items: [
                    item("Exam", earned: 90, possible: 100, status: .graded)
                ]),
                GradingCategoryCalculationInput(
                    name: "Bonus", weight: 5, isExtraCredit: true, items: [
                        GradeItemCalculationInput(
                            id: bonusID,
                            title: "Bonus Project",
                            possiblePoints: 10
                        )
                    ]
                ),
            ],
            gradeScale: standardScale,
            forecast: CourseForecastInput(assumedRemainingPercentage: 100)
        )

        let result = CourseGradeCalculationEngine.calculate(input)
        XCTAssertEqual(result.calculatedCurrentPercentage, 90)
        XCTAssertEqual(result.earnedCourseCredit, 90)
        XCTAssertEqual(result.gradedWeight, 100)
        XCTAssertEqual(result.projectedFinalPercentage, 95)
        XCTAssertEqual(result.bestPossiblePercentage, 95)
        XCTAssertEqual(result.worstPossiblePercentage, 90)
        XCTAssertFalse(result.issues.contains(.weightTotalAbove100(105)))

        let opportunity = try XCTUnwrap(CourseGradeOpportunityEngine.biggestOpportunity(for: input))
        XCTAssertEqual(opportunity.itemID, bonusID)
        XCTAssertEqual(opportunity.courseImpact, 5)
    }

    func testHybridPreservesDirectCategoryLevelExtraCredit() {
        let weighted = category("Projects", weight: 60, items: [
            item("Project", earned: 90, possible: 100, status: .graded)
        ])
        let direct = GradingCategoryCalculationInput(name: "Direct", weight: 0, items: [
            item("Direct Final", earned: 20, possible: 40, status: .graded)
        ])
        let bonus = GradingCategoryCalculationInput(
            name: "Bonus", weight: 0, isExtraCredit: true, items: [
                item("Bonus Quiz", earned: 5, possible: 5, status: .graded)
            ]
        )

        let result = calculate(.hybrid, categories: [weighted, direct, bonus])

        XCTAssertEqual(result.calculatedCurrentPercentage, 79)
        XCTAssertEqual(result.earnedCourseCredit, 79)
    }

    func testGradedItemWithoutScoreSuppressesForecastAndOpportunity() {
        let result = calculate(.totalPoints, categories: [category("Course", weight: 100, items: [
            item("Exam", earned: 90, possible: 100, status: .graded),
            item("Final", type: .finalExam, possible: 100, status: .graded),
        ])], target: 90, forecast: CourseForecastInput(assumedRemainingPercentage: 80))

        XCTAssertEqual(result.calculatedCurrentPercentage, 90)
        XCTAssertTrue(result.requiresManualReview)
        XCTAssertTrue(result.issues.contains(.gradedItemMissingScore("Final")))
        XCTAssertNil(result.projectedFinalPercentage)
        XCTAssertNil(result.bestPossiblePercentage)
        XCTAssertNil(result.worstPossiblePercentage)
        XCTAssertNil(result.requiredRemainingAverage)
        XCTAssertNil(result.finalExamNeeded)
        XCTAssertEqual(result.targetFeasibility, .manualReviewRequired)
    }

    func testUnconfirmedImportedPolicySuppressesForecastButKeepsCurrent() {
        let work = category("Course", weight: 100, items: [
            item("Exam", earned: 90, possible: 100, status: .graded)
        ])
        let input = CourseGradeCalculationInput(
            gradingMethod: .weightedCategories,
            categories: [work],
            gradeScale: standardScale,
            forecast: CourseForecastInput(assumedRemainingPercentage: 90),
            policyRequiresManualReview: true
        )

        let result = CourseGradeCalculationEngine.calculate(input)

        XCTAssertEqual(result.calculatedCurrentPercentage, 90)
        XCTAssertTrue(result.requiresManualReview)
        XCTAssertTrue(result.issues.contains(.gradingPolicyNeedsConfirmation))
        XCTAssertNil(result.projectedFinalPercentage)
        XCTAssertNil(CourseGradeOpportunityEngine.biggestOpportunity(for: input))
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

    func testForecastUsesPerItemAssumptionsWithoutChangingCurrentGrade() {
        let projectID = UUID()
        let finalID = UUID()
        let graded = item("Midterm", earned: 50, possible: 100, status: .graded)
        let project = GradeItemCalculationInput(
            id: projectID,
            title: "Project",
            categoryType: .project,
            possiblePoints: 50,
            status: .upcoming
        )
        let final = GradeItemCalculationInput(
            id: finalID,
            title: "Final",
            categoryType: .finalExam,
            possiblePoints: 50,
            status: .upcoming
        )

        let result = calculate(
            .totalPoints,
            categories: [category("All", weight: 100, items: [graded, project, final])],
            forecast: CourseForecastInput(
                assumedRemainingPercentage: 80,
                itemPercentages: [projectID: 100, finalID: 40]
            )
        )

        XCTAssertEqual(result.calculatedCurrentPercentage, 50)
        XCTAssertEqual(result.projectedFinalPercentage, 60)
        XCTAssertEqual(result.gradedWeight, 50)
    }

    func testWeightedForecastRecalculatesPartiallyGradedCategoriesPerItem() {
        let homeworkID = UUID()
        let finalID = UUID()
        let homework = category("Homework", type: .homework, weight: 20, items: [
            item("Homework 1", type: .homework, earned: 18, possible: 20, status: .graded),
            GradeItemCalculationInput(
                id: homeworkID, title: "Homework 2", categoryType: .homework,
                possiblePoints: 20
            )
        ])
        let final = category("Final", type: .finalExam, weight: 80, items: [
            GradeItemCalculationInput(
                id: finalID, title: "Final Exam", categoryType: .finalExam,
                possiblePoints: 100
            )
        ])

        let result = calculate(
            .weightedCategories,
            categories: [homework, final],
            target: 90,
            forecast: CourseForecastInput(
                assumedRemainingPercentage: 0,
                itemPercentages: [homeworkID: 100, finalID: 0]
            )
        )

        // Current grade remains based only on the recorded homework score.
        XCTAssertEqual(result.calculatedCurrentPercentage, 90)
        XCTAssertEqual(result.gradedWeight, 20)
        // Projection evaluates each remaining item inside its own category:
        // Homework becomes 95% (19 course points), while the final contributes 0.
        XCTAssertEqual(result.projectedFinalPercentage, 19)
        XCTAssertEqual(result.bestPossiblePercentage, 99)
        XCTAssertEqual(result.worstPossiblePercentage, 9)
        XCTAssertEqual(decimalDouble(result.requiredRemainingAverage), 90, accuracy: 0.0001)
    }

    func testWeightedForecastRespectsDropLowestAndMultiplierRules() {
        let remainingID = UUID()
        let quizzes = GradingCategoryCalculationInput(
            name: "Quizzes",
            weight: 100,
            calculationMode: .equalItems,
            dropLowestCount: 1,
            items: [
                item("Quiz 1", earned: 6, possible: 10, status: .graded),
                GradeItemCalculationInput(
                    id: remainingID, title: "Quiz 2", possiblePoints: 10,
                    multiplier: 2
                )
            ]
        )

        let result = calculate(
            .weightedCategories,
            categories: [quizzes],
            forecast: CourseForecastInput(
                assumedRemainingPercentage: 0,
                itemPercentages: [remainingID: 100]
            )
        )

        XCTAssertEqual(result.calculatedCurrentPercentage, 60)
        XCTAssertEqual(result.projectedFinalPercentage, 100)
        XCTAssertEqual(result.bestPossiblePercentage, 100)
        XCTAssertEqual(result.worstPossiblePercentage, 60)
    }

    func testTargetLetterUsesCourseSpecificScaleAndExplicitPercentageWins() {
        let completed = category("Course", weight: 100, items: [
            item("Exam", earned: 91, possible: 100, status: .graded)
        ])
        let customScale = CourseGradeScaleInput(boundaries: [
            GradeScaleBoundary(letter: .aMinus, minimumPercentage: 92),
            GradeScaleBoundary(letter: .bPlus, minimumPercentage: 88),
            GradeScaleBoundary(letter: .f, minimumPercentage: 0)
        ])

        let letterTarget = CourseGradeCalculationEngine.calculate(CourseGradeCalculationInput(
            gradingMethod: .weightedCategories,
            categories: [completed],
            gradeScale: customScale,
            targetLetterGrade: .aMinus
        ))
        XCTAssertEqual(letterTarget.targetFeasibility, .impossible)

        let explicitTarget = CourseGradeCalculationEngine.calculate(CourseGradeCalculationInput(
            gradingMethod: .weightedCategories,
            categories: [completed],
            gradeScale: customScale,
            targetPercentage: 90,
            targetLetterGrade: .aMinus
        ))
        XCTAssertEqual(explicitTarget.targetFeasibility, .alreadyReached)
    }

    func testBiggestOpportunityUsesActualImpactAndKeepsOtherForecastsFixed() throws {
        let homeworkID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
        let finalID = UUID(uuidString: "00000000-0000-0000-0000-000000000020")!
        let homework = category("Homework", type: .homework, weight: 20, items: [
            item("Homework 1", type: .homework, earned: 18, possible: 20, status: .graded),
            item("Homework 2", type: .homework, earned: 19, possible: 20, status: .graded),
            GradeItemCalculationInput(
                id: homeworkID, title: "Homework 3", categoryType: .homework,
                possiblePoints: 20
            )
        ])
        let labs = category("Labs", type: .lab, weight: 20, items: [
            item("Lab 1", type: .lab, earned: 45, possible: 50, status: .graded)
        ])
        let midterms = category("Midterms", type: .midterm, weight: 30, items: [
            item("Midterm 1", type: .midterm, earned: 84, possible: 100, status: .graded)
        ])
        let final = category("Final Exam", type: .finalExam, weight: 30, items: [
            GradeItemCalculationInput(
                id: finalID, title: "Final Exam", categoryType: .finalExam,
                possiblePoints: 100
            )
        ])
        let input = CourseGradeCalculationInput(
            gradingMethod: .weightedCategories,
            categories: [homework, labs, midterms, final],
            gradeScale: standardScale,
            targetPercentage: 90,
            forecast: CourseForecastInput(
                assumedRemainingPercentage: 87,
                itemPercentages: [homeworkID: 87, finalID: 87]
            )
        )

        let opportunity = try XCTUnwrap(
            CourseGradeOpportunityEngine.biggestOpportunity(for: input)
        )
        XCTAssertEqual(opportunity.itemID, finalID)
        XCTAssertEqual(opportunity.itemTitle, "Final Exam")
        XCTAssertEqual(opportunity.categoryWeight, 30)
        XCTAssertEqual(opportunity.courseImpact, 30)
        XCTAssertEqual(decimalDouble(opportunity.baselineProjectedPercentage), 87.4333333333, accuracy: 0.0001)
        XCTAssertEqual(decimalDouble(opportunity.requiredScorePercentage), 95.5555555556, accuracy: 0.0001)
        XCTAssertEqual(decimalDouble(opportunity.projectedAtRequiredScore), 90, accuracy: 0.0001)
        XCTAssertEqual(decimalDouble(opportunity.maximumProjectedPercentage), 91.3333333333, accuracy: 0.0001)
        XCTAssertEqual(opportunity.targetFeasibility, .achievable)
    }

    func testBiggestOpportunityExcludesGradedItemsAndBreaksTiesStably() throws {
        let alphaID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let betaID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let completed = category("Completed", weight: 40, items: [
            item("Already Graded", earned: 0, possible: 100, status: .graded)
        ])
        let alpha = GradingCategoryCalculationInput(
            name: "Exams", weight: 30, items: [
                GradeItemCalculationInput(id: alphaID, title: "Alpha", possiblePoints: 100)
            ]
        )
        let beta = GradingCategoryCalculationInput(
            name: "Exams", weight: 30, items: [
                GradeItemCalculationInput(id: betaID, title: "Beta", possiblePoints: 100)
            ]
        )
        let input = CourseGradeCalculationInput(
            gradingMethod: .weightedCategories,
            categories: [completed, beta, alpha],
            gradeScale: standardScale,
            forecast: CourseForecastInput(assumedRemainingPercentage: 50)
        )

        let opportunity = try XCTUnwrap(
            CourseGradeOpportunityEngine.biggestOpportunity(for: input)
        )
        XCTAssertEqual(opportunity.itemID, alphaID)
        XCTAssertEqual(opportunity.itemTitle, "Alpha")
        XCTAssertEqual(opportunity.courseImpact, 30)
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

    func testTodayPriorityEngineSeparatesNextDueTodayHighImpactAndAttention() {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 1, day: 10, hour: 12))!
        let overdueDate = calendar.date(byAdding: .day, value: -1, to: now)!
        let todayDate = calendar.date(byAdding: .hour, value: 3, to: now)!
        let futureDate = calendar.date(byAdding: .day, value: 2, to: now)!
        let completedDate = calendar.date(byAdding: .hour, value: 1, to: now)!
        let overdueID = UUID()
        let todayID = UUID()
        let futureID = UUID()
        let completedID = UUID()

        let items = [
            TodayTaskSnapshot(
                id: overdueID, courseID: UUID(), courseCode: "CHE 002A", title: "Lab report",
                dueDate: overdueDate, categoryName: "Labs", categoryType: .lab,
                courseImpact: 5, status: .upcoming
            ),
            TodayTaskSnapshot(
                id: todayID, courseID: UUID(), courseCode: "PSC 001", title: "Midterm",
                dueDate: todayDate, categoryName: "Midterms", categoryType: .midterm,
                courseImpact: 12, status: .missing
            ),
            TodayTaskSnapshot(
                id: futureID, courseID: UUID(), courseCode: "CHE 002A", title: "Final Exam",
                dueDate: futureDate, categoryName: "Final Exam", categoryType: .finalExam,
                courseImpact: 30, status: .upcoming
            ),
            TodayTaskSnapshot(
                id: completedID, courseID: UUID(), courseCode: "BIS 002B", title: "Completed",
                dueDate: completedDate, categoryName: "Homework", categoryType: .homework,
                courseImpact: 50, status: .submitted
            ),
            TodayTaskSnapshot(
                id: UUID(), courseID: UUID(), courseCode: "UWP 007", title: "Dropped",
                dueDate: futureDate, categoryName: "Essays", categoryType: .project,
                courseImpact: 40, status: .dropped
            )
        ]

        let plan = TodayPriorityEngine.makePlan(items: items, now: now, calendar: calendar)

        XCTAssertEqual(plan.next?.id, overdueID)
        XCTAssertEqual(plan.dueToday.map(\.id), [todayID])
        XCTAssertEqual(plan.highImpact.first?.id, futureID)
        XCTAssertEqual(plan.needsAttention.first?.item?.id, overdueID)
        XCTAssertTrue(plan.needsAttention.contains { $0.item?.id == todayID && $0.reason == .missing })
        XCTAssertEqual(plan.timeline.map(\.id), [overdueID, completedID, todayID, futureID])
    }

    func testTodayPriorityEngineKeepsStableTieOrderAndCourseAlerts() {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1, hour: 9))!
        let due = calendar.date(byAdding: .day, value: 4, to: now)!
        let firstID = UUID()
        let secondID = UUID()
        let items = [
            TodayTaskSnapshot(
                id: secondID, courseID: UUID(), courseCode: "PSC 001", title: "Essay",
                dueDate: due, categoryName: "Essays", categoryType: .project,
                courseImpact: 10, status: .upcoming
            ),
            TodayTaskSnapshot(
                id: firstID, courseID: UUID(), courseCode: "CHE 002A", title: "Homework",
                dueDate: due, categoryName: "Homework", categoryType: .homework,
                courseImpact: 10, status: .upcoming
            )
        ]
        let courseID = UUID()
        let plan = TodayPriorityEngine.makePlan(
            items: items,
            courseAlerts: [TodayCourseAlertSnapshot(id: courseID, courseCode: "BIS 002B", reason: .gradingPolicyReview)],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(plan.next?.courseCode, "CHE 002A")
        XCTAssertEqual(plan.highImpact.map(\.courseCode), ["CHE 002A", "PSC 001"])
        XCTAssertEqual(plan.needsAttention.last?.courseID, courseID)
        XCTAssertEqual(plan.needsAttention.last?.reason, .gradingPolicyReview)
    }

    func testTodayPriorityEngineCourseImpactUsesCategoryAndItemWeight() {
        XCTAssertEqual(
            TodayPriorityEngine.courseImpact(
                categoryWeight: 30,
                itemPossiblePoints: 100,
                categoryPossiblePoints: 200
            ),
            15
        )
        XCTAssertEqual(
            TodayPriorityEngine.courseImpact(
                categoryWeight: 20,
                itemPossiblePoints: 20,
                categoryPossiblePoints: 100,
                percentageOverride: 80
            ),
            16
        )
        XCTAssertEqual(
            TodayPriorityEngine.courseImpact(
                categoryWeight: 0,
                itemPossiblePoints: 100,
                categoryPossiblePoints: 100
            ),
            0
        )
        XCTAssertEqual(
            TodayPriorityEngine.courseImpact(
                categoryWeight: 30,
                itemPossiblePoints: 1,
                categoryPossiblePoints: 300,
                calculationMode: .equalItems,
                categoryItemCount: 3
            ),
            10
        )
    }

    func testTodayPriorityEngineExcludesDroppedExcusedAndNotIncludedSnapshots() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let dueDate = now.addingTimeInterval(86_400)
        let dropped = TodayTaskSnapshot(
            id: UUID(), courseID: UUID(), courseCode: "CHE 002A", title: "Dropped",
            dueDate: dueDate, categoryName: "Homework", categoryType: .homework,
            courseImpact: 20, status: .upcoming, isDropped: true
        )
        let excused = TodayTaskSnapshot(
            id: UUID(), courseID: UUID(), courseCode: "CHE 002A", title: "Excused",
            dueDate: dueDate, categoryName: "Homework", categoryType: .homework,
            courseImpact: 20, status: .upcoming, isExcused: true
        )
        let excluded = TodayTaskSnapshot(
            id: UUID(), courseID: UUID(), courseCode: "CHE 002A", title: "Excluded",
            dueDate: dueDate, categoryName: "Homework", categoryType: .homework,
            courseImpact: 20, status: .upcoming, isIncluded: false
        )
        let recordedButUpcoming = TodayTaskSnapshot(
            id: UUID(), courseID: UUID(), courseCode: "CHE 002A", title: "Recorded",
            dueDate: dueDate, categoryName: "Homework", categoryType: .homework,
            courseImpact: 20, status: .upcoming, hasRecordedScore: true
        )

        let plan = TodayPriorityEngine.makePlan(
            items: [dropped, excused, excluded, recordedButUpcoming], now: now
        )

        XCTAssertEqual(plan, .empty)
    }

    func testPhase15TodayPriorityPerformance() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let items = (0..<500).map { index in
            TodayTaskSnapshot(
                id: UUID(),
                courseID: UUID(),
                courseCode: "PERF (index % 40)",
                title: "Assignment (index)",
                dueDate: now.addingTimeInterval(TimeInterval((index % 30) - 2) * 86_400),
                categoryName: "Homework",
                categoryType: .homework,
                courseImpact: Decimal((index % 30) + 1),
                status: index.isMultiple(of: 17) ? .missing : .upcoming
            )
        }
        let calendar = Calendar(identifier: .gregorian)

        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]) {
            let plan = TodayPriorityEngine.makePlan(
                items: items,
                now: now,
                calendar: calendar
            )
            XCTAssertEqual(plan.timeline.count, items.count)
            XCTAssertEqual(plan.highImpact.count, 3)
        }
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

    private func decimalDouble(_ value: Decimal?) -> Double {
        value.map { NSDecimalNumber(decimal: $0).doubleValue } ?? .nan
    }
}
