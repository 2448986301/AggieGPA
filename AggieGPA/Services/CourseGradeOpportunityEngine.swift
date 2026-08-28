import Foundation

nonisolated struct CourseGradeOpportunity: Equatable, Sendable {
    let itemID: UUID
    let itemTitle: String
    let categoryName: String
    let categoryWeight: Decimal
    let courseImpact: Decimal
    let baselineProjectedPercentage: Decimal?
    let targetPercentage: Decimal?
    let requiredScorePercentage: Decimal?
    let projectedAtRequiredScore: Decimal?
    let maximumProjectedPercentage: Decimal?
    let targetFeasibility: TargetFeasibility
}

/// Pure counterfactual analysis over `CourseGradeCalculationInput` snapshots.
/// It never receives a model context and cannot mutate recorded or official data.
nonisolated enum CourseGradeOpportunityEngine {
    static func biggestOpportunity(
        for input: CourseGradeCalculationInput
    ) -> CourseGradeOpportunity? {
        let baselineResult = CourseGradeCalculationEngine.calculate(input)
        guard !baselineResult.requiresManualReview else { return nil }

        let target = CourseTargetResolver.percentage(
            explicitPercentage: input.targetPercentage,
            targetLetterGrade: input.targetLetterGrade,
            gradeScale: input.gradeScale
        )
        let evaluationForecast = input.forecast
            ?? CourseForecastInput(assumedRemainingPercentage: 0)

        let opportunities = candidates(in: input).compactMap { candidate in
            opportunity(
                for: candidate,
                input: input,
                baselineResult: baselineResult,
                evaluationForecast: evaluationForecast,
                target: target
            )
        }

        return opportunities.sorted(by: opportunitySort).first
    }

    private nonisolated struct Candidate {
        let item: GradeItemCalculationInput
        let categoryName: String
        let categoryWeight: Decimal
    }

    private static func candidates(in input: CourseGradeCalculationInput) -> [Candidate] {
        let directWeight = max(
            0,
            100 - input.categories
                .filter { $0.isIncluded && $0.weight > 0 }
                .reduce(Decimal.zero) { $0 + $1.weight }
        )
        var values: [Candidate] = []

        for category in input.categories where category.isIncluded {
            let effectiveWeight: Decimal
            switch input.gradingMethod {
            case .weightedCategories:
                effectiveWeight = category.weight
            case .totalPoints:
                effectiveWeight = 100
            case .hybrid:
                effectiveWeight = category.weight > 0 ? category.weight : directWeight
            case .manualLetterGradeOnly:
                continue
            }
            values += category.items.compactMap { item in
                guard CourseGradeCalculationEngine.isActiveUngradedItem(item, input: input) else {
                    return nil
                }
                return Candidate(
                    item: item,
                    categoryName: category.name,
                    categoryWeight: effectiveWeight
                )
            }
        }

        let unassignedWeight: Decimal
        switch input.gradingMethod {
        case .totalPoints: unassignedWeight = 100
        case .hybrid: unassignedWeight = directWeight
        case .weightedCategories, .manualLetterGradeOnly: unassignedWeight = 0
        }
        values += input.unassignedItems.compactMap { item in
            guard CourseGradeCalculationEngine.isActiveUngradedItem(item, input: input) else {
                return nil
            }
            return Candidate(
                item: item,
                categoryName: "Unassigned",
                categoryWeight: unassignedWeight
            )
        }
        return values
    }

    private static func opportunity(
        for candidate: Candidate,
        input: CourseGradeCalculationInput,
        baselineResult: CourseGradeCalculationResult,
        evaluationForecast: CourseForecastInput,
        target: Decimal?
    ) -> CourseGradeOpportunity? {
        guard let minimumProjected = projectedPercentage(
            input: input,
            baseForecast: evaluationForecast,
            itemID: candidate.item.id,
            score: 0
        ), let maximumProjected = projectedPercentage(
            input: input,
            baseForecast: evaluationForecast,
            itemID: candidate.item.id,
            score: 100
        ) else { return nil }

        let impact = maximumProjected - minimumProjected
        guard impact > 0 else { return nil }

        var requiredScore: Decimal?
        var projectedAtRequired: Decimal?
        let feasibility: TargetFeasibility
        if let target, input.forecast != nil {
            if minimumProjected >= target {
                requiredScore = 0
                projectedAtRequired = minimumProjected
                feasibility = .alreadyReached
            } else if maximumProjected < target {
                feasibility = .impossible
            } else if let solution = solveRequiredScore(
                input: input,
                baseForecast: evaluationForecast,
                itemID: candidate.item.id,
                target: target
            ) {
                requiredScore = solution.score
                projectedAtRequired = solution.projected
                feasibility = .achievable
            } else {
                feasibility = .manualReviewRequired
            }
        } else if target == nil {
            feasibility = .noTarget
        } else {
            feasibility = baselineResult.targetFeasibility
        }

        return CourseGradeOpportunity(
            itemID: candidate.item.id,
            itemTitle: candidate.item.title,
            categoryName: candidate.categoryName,
            categoryWeight: candidate.categoryWeight,
            courseImpact: impact,
            baselineProjectedPercentage: input.forecast == nil
                ? nil
                : baselineResult.projectedFinalPercentage,
            targetPercentage: target,
            requiredScorePercentage: requiredScore,
            projectedAtRequiredScore: projectedAtRequired,
            maximumProjectedPercentage: maximumProjected,
            targetFeasibility: feasibility
        )
    }

    private static func projectedPercentage(
        input: CourseGradeCalculationInput,
        baseForecast: CourseForecastInput,
        itemID: UUID,
        score: Decimal
    ) -> Decimal? {
        var assumptions = baseForecast.itemPercentages
        assumptions[itemID] = score
        let forecast = CourseForecastInput(
            assumedRemainingPercentage: baseForecast.assumedRemainingPercentage,
            itemPercentages: assumptions
        )
        return CourseGradeCalculationEngine.projectedFinalPercentage(
            for: input,
            forecast: forecast
        )
    }

    private static func solveRequiredScore(
        input: CourseGradeCalculationInput,
        baseForecast: CourseForecastInput,
        itemID: UUID,
        target: Decimal
    ) -> (score: Decimal, projected: Decimal)? {
        var lower: Decimal = 0
        var upper: Decimal = 100
        let tolerance = Decimal(string: "0.000001")!
        for _ in 0..<80 {
            let midpoint = (lower + upper) / 2
            guard let projected = projectedPercentage(
                input: input,
                baseForecast: baseForecast,
                itemID: itemID,
                score: midpoint
            ) else { return nil }
            if projected >= target {
                upper = midpoint
            } else {
                lower = midpoint
            }
            if upper - lower <= tolerance { break }
        }
        guard let projected = projectedPercentage(
            input: input,
            baseForecast: baseForecast,
            itemID: itemID,
            score: upper
        ) else { return nil }
        return (upper, projected)
    }

    private static func opportunitySort(
        _ lhs: CourseGradeOpportunity,
        _ rhs: CourseGradeOpportunity
    ) -> Bool {
        if lhs.courseImpact != rhs.courseImpact {
            return lhs.courseImpact > rhs.courseImpact
        }
        if lhs.categoryName != rhs.categoryName {
            return lhs.categoryName < rhs.categoryName
        }
        if lhs.itemTitle != rhs.itemTitle {
            return lhs.itemTitle < rhs.itemTitle
        }
        return lhs.itemID.uuidString < rhs.itemID.uuidString
    }
}
