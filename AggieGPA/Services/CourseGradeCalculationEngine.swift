import Foundation

nonisolated struct GradeItemCalculationInput: Equatable, Sendable {
    let id: UUID
    let title: String
    let categoryType: GradeCategoryType
    let earnedPoints: Decimal?
    let possiblePoints: Decimal
    let percentageOverride: Decimal?
    let status: GradeItemStatus
    let isIncluded: Bool
    let isExtraCredit: Bool
    let isDropped: Bool
    let isExcused: Bool
    let multiplier: Decimal

    init(
        id: UUID = UUID(), title: String, categoryType: GradeCategoryType = .custom,
        earnedPoints: Decimal? = nil, possiblePoints: Decimal,
        percentageOverride: Decimal? = nil, status: GradeItemStatus = .upcoming,
        isIncluded: Bool = true, isExtraCredit: Bool = false,
        isDropped: Bool = false, isExcused: Bool = false, multiplier: Decimal = 1
    ) {
        self.id = id
        self.title = title
        self.categoryType = categoryType
        self.earnedPoints = earnedPoints
        self.possiblePoints = possiblePoints
        self.percentageOverride = percentageOverride
        self.status = status
        self.isIncluded = isIncluded
        self.isExtraCredit = isExtraCredit
        self.isDropped = isDropped
        self.isExcused = isExcused
        self.multiplier = multiplier
    }
}

nonisolated struct GradingCategoryCalculationInput: Equatable, Sendable {
    let id: UUID
    let name: String
    let categoryType: GradeCategoryType
    let weight: Decimal
    let calculationMode: CategoryCalculationMode
    let dropLowestCount: Int
    let isExtraCredit: Bool
    let isIncluded: Bool
    let items: [GradeItemCalculationInput]

    init(
        id: UUID = UUID(), name: String, categoryType: GradeCategoryType = .custom,
        weight: Decimal, calculationMode: CategoryCalculationMode = .totalPoints,
        dropLowestCount: Int = 0, isExtraCredit: Bool = false,
        isIncluded: Bool = true, items: [GradeItemCalculationInput] = []
    ) {
        self.id = id
        self.name = name
        self.categoryType = categoryType
        self.weight = weight
        self.calculationMode = calculationMode
        self.dropLowestCount = dropLowestCount
        self.isExtraCredit = isExtraCredit
        self.isIncluded = isIncluded
        self.items = items
    }
}

nonisolated struct CourseGradeScaleInput: Equatable, Sendable {
    let isEnabled: Bool
    let boundaries: [GradeScaleBoundary]

    init(isEnabled: Bool = true, boundaries: [GradeScaleBoundary]) {
        self.isEnabled = isEnabled
        self.boundaries = boundaries
    }

    func letter(for percentage: Decimal?) -> GradeLetter? {
        guard isEnabled, let percentage else { return nil }
        return boundaries
            .sorted { $0.minimumPercentage > $1.minimumPercentage }
            .first { percentage >= $0.minimumPercentage }?
            .letter
    }
}

nonisolated struct CourseForecastInput: Equatable, Sendable {
    let assumedRemainingPercentage: Decimal
    let itemPercentages: [UUID: Decimal]

    init(assumedRemainingPercentage: Decimal, itemPercentages: [UUID: Decimal] = [:]) {
        self.assumedRemainingPercentage = assumedRemainingPercentage
        self.itemPercentages = itemPercentages
    }
}

nonisolated struct CourseGradeCalculationInput: Equatable, Sendable {
    let gradingMethod: GradingMethod
    let normalizeCurrentGrade: Bool
    let missingItemPolicy: MissingItemPolicy
    let missingPolicyConfirmed: Bool
    let categories: [GradingCategoryCalculationInput]
    let unassignedItems: [GradeItemCalculationInput]
    let gradeScale: CourseGradeScaleInput?
    let targetPercentage: Decimal?
    let forecast: CourseForecastInput?

    init(
        gradingMethod: GradingMethod, normalizeCurrentGrade: Bool = true,
        missingItemPolicy: MissingItemPolicy = .excludeUntilGraded,
        missingPolicyConfirmed: Bool = false,
        categories: [GradingCategoryCalculationInput],
        unassignedItems: [GradeItemCalculationInput] = [],
        gradeScale: CourseGradeScaleInput? = nil,
        targetPercentage: Decimal? = nil,
        forecast: CourseForecastInput? = nil
    ) {
        self.gradingMethod = gradingMethod
        self.normalizeCurrentGrade = normalizeCurrentGrade
        self.missingItemPolicy = missingItemPolicy
        self.missingPolicyConfirmed = missingPolicyConfirmed
        self.categories = categories
        self.unassignedItems = unassignedItems
        self.gradeScale = gradeScale
        self.targetPercentage = targetPercentage
        self.forecast = forecast
    }
}

nonisolated enum GradeCalculationIssue: Equatable, Sendable {
    case emptyGradebook
    case noGradeScale
    case missingPolicyNeedsConfirmation
    case weightTotalBelow100(Decimal)
    case weightTotalAbove100(Decimal)
    case invalidCategoryWeight(String)
    case unsupportedCustomCategory(String)
    case invalidPossiblePoints(String)
    case invalidMultiplier(String)
    case gradedItemMissingScore(String)
    case dropCountRemovesAll(String)
    case unassignedItems
    case hybridNeedsDirectItems
}

nonisolated struct CategoryGradeBreakdown: Equatable, Sendable {
    let id: UUID
    let name: String
    let weight: Decimal
    let average: Decimal?
    let contribution: Decimal
    let gradedFraction: Decimal
    let gradedItems: Int
    let remainingItems: Int
    let missingItems: Int
    let droppedItems: Int
}

nonisolated enum TargetFeasibility: String, Equatable, Sendable {
    case noTarget
    case alreadyReached
    case achievable
    case impossible
    case manualReviewRequired
}

nonisolated struct CourseGradeCalculationResult: Equatable, Sendable {
    let gradedWorkAverage: Decimal?
    let calculatedCurrentPercentage: Decimal?
    let currentLetterGrade: GradeLetter?
    let gradedWeight: Decimal
    let remainingWeight: Decimal
    let earnedCourseCredit: Decimal
    let projectedFinalPercentage: Decimal?
    let projectedLetterGrade: GradeLetter?
    let bestPossiblePercentage: Decimal?
    let worstPossiblePercentage: Decimal?
    let requiredRemainingAverage: Decimal?
    let finalExamNeeded: Decimal?
    let targetFeasibility: TargetFeasibility
    let categoryBreakdown: [CategoryGradeBreakdown]
    let issues: [GradeCalculationIssue]

    var requiresManualReview: Bool {
        issues.contains { issue in
            switch issue {
            case .weightTotalBelow100, .weightTotalAbove100, .invalidCategoryWeight,
                 .unsupportedCustomCategory, .invalidPossiblePoints, .invalidMultiplier,
                 .dropCountRemovesAll, .unassignedItems, .hybridNeedsDirectItems:
                true
            default:
                false
            }
        }
    }
}

nonisolated enum CourseGradeCalculationEngine {
    static func calculate(_ input: CourseGradeCalculationInput) -> CourseGradeCalculationResult {
        var issues: [GradeCalculationIssue] = []
        if input.gradeScale == nil || input.gradeScale?.isEnabled == false {
            issues.append(.noGradeScale)
        }
        if input.missingItemPolicy == .countMissingAsZero, !input.missingPolicyConfirmed {
            issues.append(.missingPolicyNeedsConfirmation)
        }

        switch input.gradingMethod {
        case .weightedCategories:
            return weightedResult(input, issues: &issues)
        case .totalPoints:
            return totalPointsResult(input, issues: &issues)
        case .hybrid:
            return hybridResult(input, issues: &issues)
        case .manualLetterGradeOnly:
            return CourseGradeCalculationResult(
                gradedWorkAverage: nil, calculatedCurrentPercentage: nil, currentLetterGrade: nil,
                gradedWeight: 0, remainingWeight: 100, earnedCourseCredit: 0,
                projectedFinalPercentage: nil, projectedLetterGrade: nil,
                bestPossiblePercentage: nil, worstPossiblePercentage: nil,
                requiredRemainingAverage: nil, finalExamNeeded: nil,
                targetFeasibility: .manualReviewRequired, categoryBreakdown: [], issues: issues
            )
        }
    }

    private static func weightedResult(
        _ input: CourseGradeCalculationInput,
        issues: inout [GradeCalculationIssue]
    ) -> CourseGradeCalculationResult {
        let included = input.categories.filter(\.isIncluded)
        if included.isEmpty { issues.append(.emptyGradebook) }
        if !input.unassignedItems.isEmpty { issues.append(.unassignedItems) }

        let totalWeight = included.reduce(Decimal.zero) { $0 + $1.weight }
        validateWeight(totalWeight, issues: &issues)

        var breakdown: [CategoryGradeBreakdown] = []
        var earnedCredit: Decimal = 0
        var gradedWeight: Decimal = 0
        var remainingIDs: [UUID] = []
        var remainingTypes: [GradeCategoryType] = []

        for category in included {
            guard category.weight >= 0 else {
                issues.append(.invalidCategoryWeight(category.name))
                continue
            }
            let stats = categoryStats(category, input: input, forceMode: nil, issues: &issues)
            // A weighted category is represented by its graded average as soon
            // as it has scored work. Future items in that category are not
            // zeros and must not dilute the student's current course grade.
            let categoryGradedWeight = stats.average == nil ? 0 : category.weight
            let contribution = category.weight * (stats.average ?? 0)
            gradedWeight += categoryGradedWeight
            earnedCredit += contribution
            remainingIDs += stats.remainingItemIDs
            remainingTypes += stats.remainingItemTypes
            breakdown.append(
                CategoryGradeBreakdown(
                    id: category.id, name: category.name, weight: category.weight,
                    average: stats.average.map { $0 * 100 }, contribution: contribution,
                    gradedFraction: stats.gradedFraction, gradedItems: stats.gradedItems,
                    remainingItems: stats.remainingItems, missingItems: stats.missingItems,
                    droppedItems: stats.droppedItems
                )
            )
        }

        return finish(input, earnedCredit: earnedCredit, gradedWeight: gradedWeight,
                      totalCourseWeight: totalWeight, breakdown: breakdown,
                      remainingItemIDs: remainingIDs, remainingItemTypes: remainingTypes,
                      issues: issues)
    }

    private static func totalPointsResult(
        _ input: CourseGradeCalculationInput,
        issues: inout [GradeCalculationIssue]
    ) -> CourseGradeCalculationResult {
        var allItems = input.unassignedItems
        for category in input.categories where category.isIncluded {
            allItems += category.items
        }
        if allItems.isEmpty { issues.append(.emptyGradebook) }

        let synthetic = GradingCategoryCalculationInput(
            name: "Total Points", weight: 100, calculationMode: .totalPoints,
            items: allItems
        )
        let stats = categoryStats(synthetic, input: input, forceMode: .totalPoints, issues: &issues)
        let earnedCredit = stats.earnedAgainstAll * 100
        let gradedWeight = stats.gradedFraction * 100
        let breakdown = [
            CategoryGradeBreakdown(
                id: synthetic.id, name: synthetic.name, weight: 100,
                average: stats.average.map { $0 * 100 }, contribution: earnedCredit,
                gradedFraction: stats.gradedFraction, gradedItems: stats.gradedItems,
                remainingItems: stats.remainingItems, missingItems: stats.missingItems,
                droppedItems: stats.droppedItems
            )
        ]
        return finish(input, earnedCredit: earnedCredit, gradedWeight: gradedWeight,
                      totalCourseWeight: 100, breakdown: breakdown,
                      remainingItemIDs: stats.remainingItemIDs,
                      remainingItemTypes: stats.remainingItemTypes, issues: issues)
    }

    private static func hybridResult(
        _ input: CourseGradeCalculationInput,
        issues: inout [GradeCalculationIssue]
    ) -> CourseGradeCalculationResult {
        let weighted = input.categories.filter { $0.isIncluded && $0.weight > 0 }
        let directCategories = input.categories.filter { $0.isIncluded && $0.weight == 0 }
        let directItems = input.unassignedItems + directCategories.flatMap(\.items)
        let weightedTotal = weighted.reduce(Decimal.zero) { $0 + $1.weight }
        let directWeight = 100 - weightedTotal

        if directWeight < 0 { issues.append(.weightTotalAbove100(weightedTotal)) }
        if directWeight > 0, directItems.isEmpty { issues.append(.hybridNeedsDirectItems) }

        var earnedCredit: Decimal = 0
        var gradedWeight: Decimal = 0
        var breakdown: [CategoryGradeBreakdown] = []
        var remainingIDs: [UUID] = []
        var remainingTypes: [GradeCategoryType] = []

        for category in weighted {
            let stats = categoryStats(category, input: input, forceMode: nil, issues: &issues)
            let contribution = category.weight * stats.earnedAgainstAll
            earnedCredit += contribution
            gradedWeight += category.weight * stats.gradedFraction
            remainingIDs += stats.remainingItemIDs
            remainingTypes += stats.remainingItemTypes
            breakdown.append(CategoryGradeBreakdown(
                id: category.id, name: category.name, weight: category.weight,
                average: stats.average.map { $0 * 100 }, contribution: contribution,
                gradedFraction: stats.gradedFraction, gradedItems: stats.gradedItems,
                remainingItems: stats.remainingItems, missingItems: stats.missingItems,
                droppedItems: stats.droppedItems
            ))
        }

        if directWeight > 0, !directItems.isEmpty {
            let direct = GradingCategoryCalculationInput(
                name: "Direct Points", weight: directWeight,
                calculationMode: .totalPoints, items: directItems
            )
            let stats = categoryStats(direct, input: input, forceMode: .totalPoints, issues: &issues)
            let contribution = directWeight * stats.earnedAgainstAll
            earnedCredit += contribution
            gradedWeight += directWeight * stats.gradedFraction
            remainingIDs += stats.remainingItemIDs
            remainingTypes += stats.remainingItemTypes
            breakdown.append(CategoryGradeBreakdown(
                id: direct.id, name: direct.name, weight: directWeight,
                average: stats.average.map { $0 * 100 }, contribution: contribution,
                gradedFraction: stats.gradedFraction, gradedItems: stats.gradedItems,
                remainingItems: stats.remainingItems, missingItems: stats.missingItems,
                droppedItems: stats.droppedItems
            ))
        }

        return finish(input, earnedCredit: earnedCredit, gradedWeight: gradedWeight,
                      totalCourseWeight: 100, breakdown: breakdown,
                      remainingItemIDs: remainingIDs, remainingItemTypes: remainingTypes,
                      issues: issues)
    }

    private static func finish(
        _ input: CourseGradeCalculationInput,
        earnedCredit: Decimal,
        gradedWeight: Decimal,
        totalCourseWeight: Decimal,
        breakdown: [CategoryGradeBreakdown],
        remainingItemIDs: [UUID],
        remainingItemTypes: [GradeCategoryType],
        issues: [GradeCalculationIssue]
    ) -> CourseGradeCalculationResult {
        let boundedGradedWeight = max(0, gradedWeight)
        let remainingWeight = max(0, totalCourseWeight - boundedGradedWeight)
        let gradedAverage = boundedGradedWeight > 0 ? earnedCredit / boundedGradedWeight * 100 : nil
        let current = input.normalizeCurrentGrade ? gradedAverage : earnedCredit
        let severe = issues.contains { issue in
            switch issue {
            case .weightTotalBelow100, .weightTotalAbove100, .invalidCategoryWeight,
                 .unsupportedCustomCategory, .invalidPossiblePoints, .invalidMultiplier,
                 .dropCountRemovesAll, .unassignedItems, .hybridNeedsDirectItems:
                true
            default:
                false
            }
        }

        let projected: Decimal?
        if severe {
            projected = nil
        } else if let forecast = input.forecast {
            let defaultAssumption = forecast.assumedRemainingPercentage
            if remainingItemIDs.isEmpty {
                projected = earnedCredit
            } else if forecast.itemPercentages.isEmpty {
                projected = earnedCredit + remainingWeight * defaultAssumption / 100
            } else {
                let average = remainingItemIDs.reduce(Decimal.zero) {
                    $0 + (forecast.itemPercentages[$1] ?? defaultAssumption)
                } / Decimal(remainingItemIDs.count)
                projected = earnedCredit + remainingWeight * average / 100
            }
        } else {
            projected = nil
        }

        let best = severe ? nil : earnedCredit + remainingWeight
        let worst = severe ? nil : earnedCredit
        let target = input.targetPercentage
        let required: Decimal?
        let feasibility: TargetFeasibility
        if severe {
            required = nil
            feasibility = .manualReviewRequired
        } else if let target {
            if earnedCredit >= target {
                required = 0
                feasibility = .alreadyReached
            } else if remainingWeight == 0 {
                required = nil
                feasibility = .impossible
            } else {
                let value = (target - earnedCredit) / remainingWeight * 100
                required = value
                feasibility = value <= 100 ? .achievable : .impossible
            }
        } else {
            required = nil
            feasibility = .noTarget
        }

        let finalNeeded = remainingItemIDs.count == 1 && remainingItemTypes.first == .finalExam ? required : nil
        return CourseGradeCalculationResult(
            gradedWorkAverage: gradedAverage,
            calculatedCurrentPercentage: current,
            currentLetterGrade: input.gradeScale?.letter(for: current),
            gradedWeight: boundedGradedWeight,
            remainingWeight: remainingWeight,
            earnedCourseCredit: earnedCredit,
            projectedFinalPercentage: projected,
            projectedLetterGrade: input.gradeScale?.letter(for: projected),
            bestPossiblePercentage: best,
            worstPossiblePercentage: worst,
            requiredRemainingAverage: required,
            finalExamNeeded: finalNeeded,
            targetFeasibility: feasibility,
            categoryBreakdown: breakdown,
            issues: issues
        )
    }

    private nonisolated struct CategoryStats {
        var numerator: Decimal = 0
        var gradedDenominator: Decimal = 0
        var remainingDenominator: Decimal = 0
        var gradedItems = 0
        var remainingItems = 0
        var missingItems = 0
        var droppedItems = 0
        var remainingItemIDs: [UUID] = []
        var remainingItemTypes: [GradeCategoryType] = []

        var totalDenominator: Decimal { gradedDenominator + remainingDenominator }
        var average: Decimal? { gradedDenominator > 0 ? numerator / gradedDenominator : nil }
        var earnedAgainstAll: Decimal { totalDenominator > 0 ? numerator / totalDenominator : 0 }
        var gradedFraction: Decimal { totalDenominator > 0 ? gradedDenominator / totalDenominator : 0 }
    }

    private nonisolated struct ScoredItem {
        let input: GradeItemCalculationInput
        let numerator: Decimal
        let denominator: Decimal
        let ratio: Decimal
    }

    private static func categoryStats(
        _ category: GradingCategoryCalculationInput,
        input: CourseGradeCalculationInput,
        forceMode: CategoryCalculationMode?,
        issues: inout [GradeCalculationIssue]
    ) -> CategoryStats {
        let mode = forceMode ?? category.calculationMode
        if mode == .custom {
            issues.append(.unsupportedCustomCategory(category.name))
            return CategoryStats()
        }

        var stats = CategoryStats()
        var scored: [ScoredItem] = []
        var extraCredit: [ScoredItem] = []
        var remaining: [(GradeItemCalculationInput, Decimal)] = []

        for item in category.items {
            guard item.isIncluded else { continue }
            if item.isDropped || item.status == .dropped {
                stats.droppedItems += 1
                continue
            }
            if item.isExcused || item.status == .excused || item.status == .notCounted { continue }
            guard item.multiplier > 0 else {
                issues.append(.invalidMultiplier(item.title))
                continue
            }

            let countsMissingAsZero = item.status == .missing
                && input.missingItemPolicy == .countMissingAsZero
                && input.missingPolicyConfirmed
            let hasScore = item.percentageOverride != nil || item.earnedPoints != nil
            if item.status == .graded, !hasScore {
                issues.append(.gradedItemMissingScore(item.title))
            }

            if hasScore || countsMissingAsZero {
                guard let value = score(item, mode: mode, missingAsZero: countsMissingAsZero, issues: &issues) else {
                    continue
                }
                if item.isExtraCredit || category.isExtraCredit {
                    extraCredit.append(value)
                } else {
                    scored.append(value)
                }
                if item.status == .missing { stats.missingItems += 1 }
            } else {
                guard let denominator = denominatorForRemaining(item, mode: mode, issues: &issues) else {
                    continue
                }
                remaining.append((item, denominator))
                if item.status == .missing { stats.missingItems += 1 }
            }
        }

        if category.dropLowestCount > 0, !scored.isEmpty {
            let requested = category.dropLowestCount
            let count = min(requested, max(0, scored.count - 1))
            if requested >= scored.count { issues.append(.dropCountRemovesAll(category.name)) }
            let droppedIDs = Set(scored.sorted { $0.ratio < $1.ratio }.prefix(count).map(\.input.id))
            stats.droppedItems += droppedIDs.count
            scored.removeAll { droppedIDs.contains($0.input.id) }
        }

        stats.numerator = scored.reduce(Decimal.zero) { $0 + $1.numerator }
            + extraCredit.reduce(Decimal.zero) { $0 + $1.numerator }
        stats.gradedDenominator = scored.reduce(Decimal.zero) { $0 + $1.denominator }
        stats.remainingDenominator = remaining.reduce(Decimal.zero) { $0 + $1.1 }
        stats.gradedItems = scored.count + extraCredit.count
        stats.remainingItems = remaining.count
        stats.remainingItemIDs = remaining.map { $0.0.id }
        stats.remainingItemTypes = remaining.map { $0.0.categoryType }
        return stats
    }

    private static func score(
        _ item: GradeItemCalculationInput,
        mode: CategoryCalculationMode,
        missingAsZero: Bool,
        issues: inout [GradeCalculationIssue]
    ) -> ScoredItem? {
        let ratio: Decimal
        if missingAsZero {
            ratio = 0
        } else if let override = item.percentageOverride {
            ratio = override / 100
        } else if let earned = item.earnedPoints, item.possiblePoints > 0 {
            ratio = earned / item.possiblePoints
        } else {
            issues.append(.invalidPossiblePoints(item.title))
            return nil
        }

        let denominator: Decimal
        switch mode {
        case .equalItems, .weightedCategory:
            denominator = item.multiplier
        case .totalPoints:
            guard item.possiblePoints > 0 else {
                if item.percentageOverride != nil {
                    return ScoredItem(input: item, numerator: ratio * item.multiplier,
                                      denominator: item.multiplier, ratio: ratio)
                }
                issues.append(.invalidPossiblePoints(item.title))
                return nil
            }
            denominator = item.possiblePoints * item.multiplier
        case .custom:
            return nil
        }
        return ScoredItem(input: item, numerator: ratio * denominator,
                          denominator: denominator, ratio: ratio)
    }

    private static func denominatorForRemaining(
        _ item: GradeItemCalculationInput,
        mode: CategoryCalculationMode,
        issues: inout [GradeCalculationIssue]
    ) -> Decimal? {
        switch mode {
        case .equalItems, .weightedCategory:
            return item.multiplier
        case .totalPoints:
            guard item.possiblePoints > 0 else {
                issues.append(.invalidPossiblePoints(item.title))
                return nil
            }
            return item.possiblePoints * item.multiplier
        case .custom:
            return nil
        }
    }

    private static func validateWeight(_ total: Decimal, issues: inout [GradeCalculationIssue]) {
        if total < 100 { issues.append(.weightTotalBelow100(total)) }
        if total > 100 { issues.append(.weightTotalAbove100(total)) }
    }
}
