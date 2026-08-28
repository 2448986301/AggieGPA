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
    let targetLetterGrade: GradeLetter?
    let forecast: CourseForecastInput?
    let policyRequiresManualReview: Bool

    init(
        gradingMethod: GradingMethod, normalizeCurrentGrade: Bool = true,
        missingItemPolicy: MissingItemPolicy = .excludeUntilGraded,
        missingPolicyConfirmed: Bool = false,
        categories: [GradingCategoryCalculationInput],
        unassignedItems: [GradeItemCalculationInput] = [],
        gradeScale: CourseGradeScaleInput? = nil,
        targetPercentage: Decimal? = nil,
        targetLetterGrade: GradeLetter? = nil,
        forecast: CourseForecastInput? = nil,
        policyRequiresManualReview: Bool = false
    ) {
        self.gradingMethod = gradingMethod
        self.normalizeCurrentGrade = normalizeCurrentGrade
        self.missingItemPolicy = missingItemPolicy
        self.missingPolicyConfirmed = missingPolicyConfirmed
        self.categories = categories
        self.unassignedItems = unassignedItems
        self.gradeScale = gradeScale
        self.targetPercentage = targetPercentage
        self.targetLetterGrade = targetLetterGrade
        self.forecast = forecast
        self.policyRequiresManualReview = policyRequiresManualReview
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
    case invalidDropCount(String)
    case unassignedItems
    case hybridNeedsDirectItems
    case gradingPolicyNeedsConfirmation

    var requiresManualReview: Bool {
        switch self {
        case .missingPolicyNeedsConfirmation, .weightTotalBelow100, .weightTotalAbove100,
             .invalidCategoryWeight, .unsupportedCustomCategory, .invalidPossiblePoints,
             .invalidMultiplier, .gradedItemMissingScore, .dropCountRemovesAll,
             .invalidDropCount, .unassignedItems, .hybridNeedsDirectItems,
             .gradingPolicyNeedsConfirmation:
            true
        case .emptyGradebook, .noGradeScale:
            false
        }
    }
}

nonisolated struct CategoryGradeBreakdown: Equatable, Sendable {
    let id: UUID
    let name: String
    let weight: Decimal
    let average: Decimal?
    /// The effective portion of the course multiplied by `average` to produce
    /// `contribution`. This can be smaller than `weight` when a points-based
    /// category still contains ungraded work.
    let contributionBasis: Decimal
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
        issues.contains(where: \.requiresManualReview)
    }
}

nonisolated enum CourseGradeCalculationEngine {
    static func calculate(_ input: CourseGradeCalculationInput) -> CourseGradeCalculationResult {
        calculate(input, evaluateScenarios: true)
    }

    private static func calculate(
        _ input: CourseGradeCalculationInput,
        evaluateScenarios: Bool
    ) -> CourseGradeCalculationResult {
        var issues: [GradeCalculationIssue] = []
        if input.gradeScale == nil || input.gradeScale?.isEnabled == false {
            issues.append(.noGradeScale)
        }
        if input.policyRequiresManualReview {
            issues.append(.gradingPolicyNeedsConfirmation)
        }
        if input.missingItemPolicy == .countMissingAsZero,
           !input.missingPolicyConfirmed,
           hasActiveMissingItem(in: input) {
            issues.append(.missingPolicyNeedsConfirmation)
        }

        switch input.gradingMethod {
        case .weightedCategories:
            return weightedResult(input, evaluateScenarios: evaluateScenarios, issues: &issues)
        case .totalPoints:
            return totalPointsResult(input, evaluateScenarios: evaluateScenarios, issues: &issues)
        case .hybrid:
            return hybridResult(input, evaluateScenarios: evaluateScenarios, issues: &issues)
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
        evaluateScenarios: Bool,
        issues: inout [GradeCalculationIssue]
    ) -> CourseGradeCalculationResult {
        let included = input.categories.filter(\.isIncluded)
        let regularCategories = included.filter { !$0.isExtraCredit }
        let extraCreditCategories = included.filter(\.isExtraCredit)
        if included.isEmpty { issues.append(.emptyGradebook) }
        if !input.unassignedItems.isEmpty { issues.append(.unassignedItems) }

        let totalWeight = regularCategories.reduce(Decimal.zero) { $0 + $1.weight }
        validateWeight(totalWeight, issues: &issues)

        var breakdown: [CategoryGradeBreakdown] = []
        var earnedCredit: Decimal = 0
        var gradedWeight: Decimal = 0
        var remainingIDs: [UUID] = []
        var remainingTypes: [GradeCategoryType] = []

        for category in regularCategories {
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
                    average: stats.average.map { $0 * 100 },
                    contributionBasis: category.weight,
                    contribution: contribution,
                    gradedFraction: stats.gradedFraction, gradedItems: stats.gradedItems,
                    remainingItems: stats.remainingItems, missingItems: stats.missingItems,
                    droppedItems: stats.droppedItems
                )
            )
        }

        for category in extraCreditCategories {
            guard category.weight > 0 else {
                issues.append(.invalidCategoryWeight(category.name))
                continue
            }
            let normalized = regularizedExtraCreditCategory(category)
            let stats = categoryStats(normalized, input: input, forceMode: nil, issues: &issues)
            let contribution = category.weight * (stats.average ?? 0)
            earnedCredit += contribution
            remainingIDs += stats.remainingItemIDs
            remainingTypes += stats.remainingItemTypes
            breakdown.append(
                CategoryGradeBreakdown(
                    id: category.id, name: category.name, weight: category.weight,
                    average: stats.average.map { $0 * 100 },
                    contributionBasis: category.weight,
                    contribution: contribution,
                    gradedFraction: stats.gradedFraction, gradedItems: stats.gradedItems,
                    remainingItems: stats.remainingItems, missingItems: stats.missingItems,
                    droppedItems: stats.droppedItems
                )
            )
        }

        return finish(input, earnedCredit: earnedCredit, gradedWeight: gradedWeight,
                      totalCourseWeight: totalWeight, breakdown: breakdown,
                      remainingItemIDs: remainingIDs, remainingItemTypes: remainingTypes,
                      evaluateScenarios: evaluateScenarios,
                      issues: issues)
    }

    private static func totalPointsResult(
        _ input: CourseGradeCalculationInput,
        evaluateScenarios: Bool,
        issues: inout [GradeCalculationIssue]
    ) -> CourseGradeCalculationResult {
        var allItems = input.unassignedItems
        for category in input.categories where category.isIncluded {
            allItems += category.items.map {
                category.isExtraCredit ? itemCopy($0, isExtraCredit: true) : $0
            }
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
                average: stats.average.map { $0 * 100 },
                contributionBasis: stats.gradedFraction * 100,
                contribution: earnedCredit,
                gradedFraction: stats.gradedFraction, gradedItems: stats.gradedItems,
                remainingItems: stats.remainingItems, missingItems: stats.missingItems,
                droppedItems: stats.droppedItems
            )
        ]
        return finish(input, earnedCredit: earnedCredit, gradedWeight: gradedWeight,
                      totalCourseWeight: 100, breakdown: breakdown,
                      remainingItemIDs: stats.remainingItemIDs,
                      remainingItemTypes: stats.remainingItemTypes,
                      evaluateScenarios: evaluateScenarios, issues: issues)
    }

    private static func hybridResult(
        _ input: CourseGradeCalculationInput,
        evaluateScenarios: Bool,
        issues: inout [GradeCalculationIssue]
    ) -> CourseGradeCalculationResult {
        let includedCategories = input.categories.filter(\.isIncluded)
        for category in includedCategories where category.weight < 0 {
            issues.append(.invalidCategoryWeight(category.name))
        }
        let weighted = includedCategories.filter { $0.weight > 0 && !$0.isExtraCredit }
        let extraCreditCategories = includedCategories.filter { $0.weight > 0 && $0.isExtraCredit }
        let directCategories = includedCategories.filter { $0.weight == 0 }
        let directItems = input.unassignedItems + directCategories.flatMap { category in
            category.items.map {
                category.isExtraCredit ? itemCopy($0, isExtraCredit: true) : $0
            }
        }
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
                average: stats.average.map { $0 * 100 },
                contributionBasis: category.weight * stats.gradedFraction,
                contribution: contribution,
                gradedFraction: stats.gradedFraction, gradedItems: stats.gradedItems,
                remainingItems: stats.remainingItems, missingItems: stats.missingItems,
                droppedItems: stats.droppedItems
            ))
        }

        for category in extraCreditCategories {
            let normalized = regularizedExtraCreditCategory(category)
            let stats = categoryStats(normalized, input: input, forceMode: nil, issues: &issues)
            let contribution = category.weight * (stats.average ?? 0)
            earnedCredit += contribution
            remainingIDs += stats.remainingItemIDs
            remainingTypes += stats.remainingItemTypes
            breakdown.append(CategoryGradeBreakdown(
                id: category.id, name: category.name, weight: category.weight,
                average: stats.average.map { $0 * 100 },
                contributionBasis: category.weight,
                contribution: contribution,
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
                average: stats.average.map { $0 * 100 },
                contributionBasis: directWeight * stats.gradedFraction,
                contribution: contribution,
                gradedFraction: stats.gradedFraction, gradedItems: stats.gradedItems,
                remainingItems: stats.remainingItems, missingItems: stats.missingItems,
                droppedItems: stats.droppedItems
            ))
        }

        return finish(input, earnedCredit: earnedCredit, gradedWeight: gradedWeight,
                      totalCourseWeight: 100, breakdown: breakdown,
                      remainingItemIDs: remainingIDs, remainingItemTypes: remainingTypes,
                      evaluateScenarios: evaluateScenarios,
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
        evaluateScenarios: Bool,
        issues: [GradeCalculationIssue]
    ) -> CourseGradeCalculationResult {
        let boundedGradedWeight = max(0, gradedWeight)
        let remainingWeight = max(0, totalCourseWeight - boundedGradedWeight)
        let gradedAverage = boundedGradedWeight > 0 ? earnedCredit / boundedGradedWeight * 100 : nil
        let current = input.normalizeCurrentGrade ? gradedAverage : earnedCredit
        let severe = issues.contains(where: \.requiresManualReview)

        guard evaluateScenarios else {
            return CourseGradeCalculationResult(
                gradedWorkAverage: gradedAverage,
                calculatedCurrentPercentage: current,
                currentLetterGrade: input.gradeScale?.letter(for: current),
                gradedWeight: boundedGradedWeight,
                remainingWeight: remainingWeight,
                earnedCourseCredit: earnedCredit,
                projectedFinalPercentage: nil,
                projectedLetterGrade: nil,
                bestPossiblePercentage: nil,
                worstPossiblePercentage: nil,
                requiredRemainingAverage: nil,
                finalExamNeeded: nil,
                targetFeasibility: .noTarget,
                categoryBreakdown: breakdown,
                issues: issues
            )
        }

        let projected = severe
            ? nil
            : input.forecast.flatMap { terminalPercentage(for: input, forecast: $0) }
        let best = severe
            ? nil
            : terminalPercentage(
                for: input,
                forecast: CourseForecastInput(assumedRemainingPercentage: 100)
            )
        let worst = severe
            ? nil
            : terminalPercentage(
                for: input,
                forecast: CourseForecastInput(assumedRemainingPercentage: 0)
            )
        let target = CourseTargetResolver.percentage(
            explicitPercentage: input.targetPercentage,
            targetLetterGrade: input.targetLetterGrade,
            gradeScale: input.gradeScale
        )
        let required: Decimal?
        let feasibility: TargetFeasibility
        if severe {
            required = nil
            feasibility = .manualReviewRequired
        } else if let target {
            if let worst, worst >= target {
                required = 0
                feasibility = .alreadyReached
            } else if let best, best >= target {
                required = solveUniformRemainingScore(
                    input: input,
                    target: target,
                    upperBound: 100
                )
                feasibility = required == nil ? .manualReviewRequired : .achievable
            } else if let impossibleRequirement = solveUniformRemainingScore(
                input: input,
                target: target,
                upperBound: 10_000
            ) {
                required = impossibleRequirement
                feasibility = .impossible
            } else {
                required = nil
                feasibility = .impossible
            }
        } else {
            required = nil
            feasibility = .noTarget
        }

        let emptyWeightedCategories = projectableEmptyCategoryCount(in: input)
        let finalNeeded = remainingItemIDs.count == 1
            && emptyWeightedCategories == 0
            && remainingItemTypes.first == .finalExam
            ? required
            : nil
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

    /// Evaluates a complete course outcome by materializing every active ungraded
    /// item with its own forecast percentage, then running the same category rules
    /// used for recorded scores. This keeps drop, multiplier, extra-credit, points,
    /// and equal-item behavior in one deterministic path.
    private static func terminalPercentage(
        for input: CourseGradeCalculationInput,
        forecast: CourseForecastInput
    ) -> Decimal? {
        let materialized = materializedInput(input, forecast: forecast)
        let terminal = calculate(materialized, evaluateScenarios: false)
        guard !terminal.requiresManualReview else { return nil }
        return terminal.calculatedCurrentPercentage
    }

    private static func materializedInput(
        _ input: CourseGradeCalculationInput,
        forecast: CourseForecastInput
    ) -> CourseGradeCalculationInput {
        let categories = input.categories.map { category in
            var items = category.items.map { item in
                materializedItem(item, input: input, forecast: forecast)
            }

            // A configured weighted category with no item structure still needs a
            // deterministic category-level assumption. It is not an opportunity
            // item, but it prevents an empty category from borrowing another
            // category's remaining-item assumption.
            let usesWeightedCategoryFallback = input.gradingMethod == .weightedCategories
                || (input.gradingMethod == .hybrid && category.weight > 0)
            if usesWeightedCategoryFallback,
               category.isIncluded,
               !category.isExtraCredit,
               category.weight > 0,
               category.items.isEmpty {
                items.append(GradeItemCalculationInput(
                    id: category.id,
                    title: "\(category.name) forecast",
                    categoryType: category.categoryType,
                    earnedPoints: nil,
                    possiblePoints: 1,
                    percentageOverride: forecast.assumedRemainingPercentage,
                    status: .graded
                ))
            }

            return GradingCategoryCalculationInput(
                id: category.id,
                name: category.name,
                categoryType: category.categoryType,
                weight: category.weight,
                calculationMode: category.calculationMode,
                dropLowestCount: category.dropLowestCount,
                isExtraCredit: category.isExtraCredit,
                isIncluded: category.isIncluded,
                items: items
            )
        }
        let unassignedItems = input.unassignedItems.map { item in
            materializedItem(item, input: input, forecast: forecast)
        }
        return CourseGradeCalculationInput(
            gradingMethod: input.gradingMethod,
            normalizeCurrentGrade: input.normalizeCurrentGrade,
            missingItemPolicy: input.missingItemPolicy,
            missingPolicyConfirmed: input.missingPolicyConfirmed,
            categories: categories,
            unassignedItems: unassignedItems,
            gradeScale: input.gradeScale,
            targetPercentage: nil,
            targetLetterGrade: nil,
            forecast: nil,
            policyRequiresManualReview: input.policyRequiresManualReview
        )
    }

    private static func materializedItem(
        _ item: GradeItemCalculationInput,
        input: CourseGradeCalculationInput,
        forecast: CourseForecastInput
    ) -> GradeItemCalculationInput {
        guard isActiveUngradedItem(item, input: input) else { return item }
        let percentage = forecast.itemPercentages[item.id]
            ?? forecast.assumedRemainingPercentage
        return GradeItemCalculationInput(
            id: item.id,
            title: item.title,
            categoryType: item.categoryType,
            earnedPoints: nil,
            possiblePoints: item.possiblePoints,
            percentageOverride: percentage,
            status: .graded,
            isIncluded: item.isIncluded,
            isExtraCredit: item.isExtraCredit,
            isDropped: item.isDropped,
            isExcused: item.isExcused,
            multiplier: item.multiplier
        )
    }

    private static func itemCopy(
        _ item: GradeItemCalculationInput,
        isExtraCredit: Bool
    ) -> GradeItemCalculationInput {
        GradeItemCalculationInput(
            id: item.id,
            title: item.title,
            categoryType: item.categoryType,
            earnedPoints: item.earnedPoints,
            possiblePoints: item.possiblePoints,
            percentageOverride: item.percentageOverride,
            status: item.status,
            isIncluded: item.isIncluded,
            isExtraCredit: isExtraCredit,
            isDropped: item.isDropped,
            isExcused: item.isExcused,
            multiplier: item.multiplier
        )
    }

    private static func regularizedExtraCreditCategory(
        _ category: GradingCategoryCalculationInput
    ) -> GradingCategoryCalculationInput {
        GradingCategoryCalculationInput(
            id: category.id,
            name: category.name,
            categoryType: category.categoryType,
            weight: category.weight,
            calculationMode: category.calculationMode,
            dropLowestCount: category.dropLowestCount,
            isExtraCredit: false,
            isIncluded: category.isIncluded,
            items: category.items.map { itemCopy($0, isExtraCredit: false) }
        )
    }

    private static func hasActiveMissingItem(in input: CourseGradeCalculationInput) -> Bool {
        let items = input.unassignedItems + input.categories
            .filter(\.isIncluded)
            .flatMap(\.items)
        return items.contains { item in
            item.isIncluded
                && item.status == .missing
                && !item.isDropped
                && !item.isExcused
        }
    }

    static func isActiveUngradedItem(
        _ item: GradeItemCalculationInput,
        input: CourseGradeCalculationInput
    ) -> Bool {
        guard item.isIncluded,
              !item.isDropped,
              !item.isExcused,
              item.status != .graded,
              item.status != .dropped,
              item.status != .excused,
              item.status != .notCounted,
              item.earnedPoints == nil,
              item.percentageOverride == nil,
              item.multiplier > 0 else { return false }
        if item.status == .missing,
           input.missingItemPolicy == .countMissingAsZero,
           input.missingPolicyConfirmed {
            return false
        }
        return true
    }

    static func projectedFinalPercentage(
        for input: CourseGradeCalculationInput,
        forecast: CourseForecastInput
    ) -> Decimal? {
        terminalPercentage(for: input, forecast: forecast)
    }

    private static func projectableEmptyCategoryCount(
        in input: CourseGradeCalculationInput
    ) -> Int {
        input.categories.count { category in
            let usesWeightedCategoryFallback = input.gradingMethod == .weightedCategories
                || (input.gradingMethod == .hybrid && category.weight > 0)
            return usesWeightedCategoryFallback
                && category.isIncluded
                && !category.isExtraCredit
                && category.weight > 0
                && category.items.isEmpty
        }
    }

    private static func solveUniformRemainingScore(
        input: CourseGradeCalculationInput,
        target: Decimal,
        upperBound: Decimal
    ) -> Decimal? {
        guard let lowerResult = terminalPercentage(
            for: input,
            forecast: CourseForecastInput(assumedRemainingPercentage: 0)
        ), let upperResult = terminalPercentage(
            for: input,
            forecast: CourseForecastInput(assumedRemainingPercentage: upperBound)
        ), upperResult >= target else { return nil }
        if lowerResult >= target { return 0 }

        var lower: Decimal = 0
        var upper = upperBound
        let tolerance = Decimal(string: "0.000000000001")!
        for _ in 0..<120 {
            let midpoint = (lower + upper) / 2
            guard let result = terminalPercentage(
                for: input,
                forecast: CourseForecastInput(assumedRemainingPercentage: midpoint)
            ) else { return nil }
            if result >= target {
                upper = midpoint
            } else {
                lower = midpoint
            }
            if upper - lower <= tolerance { break }
        }
        var rounded = Decimal.zero
        var value = upper
        NSDecimalRound(&rounded, &value, 6, .plain)
        return rounded
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
        var remainingExtraCredit: [GradeItemCalculationInput] = []

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
                if item.isExtraCredit || category.isExtraCredit {
                    remainingExtraCredit.append(item)
                } else {
                    remaining.append((item, denominator))
                }
                if item.status == .missing { stats.missingItems += 1 }
            }
        }

        if category.dropLowestCount < 0 {
            issues.append(.invalidDropCount(category.name))
        } else if category.dropLowestCount > 0 {
            let requested = category.dropLowestCount
            if requested >= scored.count + remaining.count {
                issues.append(.dropCountRemovesAll(category.name))
            }
            if !scored.isEmpty {
                let count = min(requested, max(0, scored.count - 1))
                let droppedIDs = Set(scored.sorted { $0.ratio < $1.ratio }.prefix(count).map(\.input.id))
                stats.droppedItems += droppedIDs.count
                scored.removeAll { droppedIDs.contains($0.input.id) }
            }
        }

        stats.numerator = scored.reduce(Decimal.zero) { $0 + $1.numerator }
            + extraCredit.reduce(Decimal.zero) { $0 + $1.numerator }
        stats.gradedDenominator = scored.reduce(Decimal.zero) { $0 + $1.denominator }
        stats.remainingDenominator = remaining.reduce(Decimal.zero) { $0 + $1.1 }
        stats.gradedItems = scored.count + extraCredit.count
        stats.remainingItems = remaining.count + remainingExtraCredit.count
        stats.remainingItemIDs = remaining.map { $0.0.id } + remainingExtraCredit.map(\.id)
        stats.remainingItemTypes = remaining.map { $0.0.categoryType }
            + remainingExtraCredit.map(\.categoryType)
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
