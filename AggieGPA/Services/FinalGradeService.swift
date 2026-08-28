import Foundation

struct GradeCategoryInput: Equatable {
    var name: String
    var weight: Decimal
    var earnedPoints: Decimal
    var possiblePoints: Decimal
    var isExtraCredit: Bool = false
    var isMissing: Bool = false
}

struct FinalGradeResult: Equatable {
    let currentPercentage: Decimal?
    let completedWeight: Decimal
    let remainingWeight: Decimal
    let projectedOverall: Decimal?
    let finalExamNeeded: Decimal?
    let bestPossible: Decimal
    let worstPossible: Decimal
    let weightsAreComplete: Bool
    let targetIsReachable: Bool
}

enum FinalGradeService {
    static func calculate(categories: [GradeCategoryInput], targetPercentage: Decimal,
                          finalExamWeight: Decimal, assumedFinalScore: Decimal? = nil) -> FinalGradeResult? {
        guard targetPercentage >= 0, targetPercentage <= 100,
              finalExamWeight >= 0, finalExamWeight <= 100,
              categories.allSatisfy({ $0.weight >= 0 && $0.weight <= 100 && $0.earnedPoints >= 0 && $0.possiblePoints >= 0 }) else {
            return nil
        }

        var weightedEarned: Decimal = 0
        var completedWeight: Decimal = 0
        var configuredWeight: Decimal = finalExamWeight
        for category in categories {
            configuredWeight += category.weight
            guard !category.isMissing, category.possiblePoints > 0 else { continue }
            let contribution = (category.earnedPoints / category.possiblePoints) * category.weight
            weightedEarned += contribution
            completedWeight += category.weight
        }

        let current = completedWeight > 0 ? weightedEarned / completedWeight * 100 : nil
        let remaining = max(0, 100 - completedWeight)
        let needed = finalExamWeight > 0 ? (targetPercentage - weightedEarned) / finalExamWeight * 100 : nil
        let projected = assumedFinalScore.map { weightedEarned + ($0 / 100 * finalExamWeight) }
        let best = weightedEarned + remaining
        let worst = weightedEarned
        let reachable = needed.map { $0 >= 0 && $0 <= 100 } ?? (weightedEarned >= targetPercentage)

        return FinalGradeResult(
            currentPercentage: current, completedWeight: completedWeight,
            remainingWeight: remaining, projectedOverall: projected,
            finalExamNeeded: needed, bestPossible: best, worstPossible: worst,
            weightsAreComplete: configuredWeight == 100,
            targetIsReachable: reachable
        )
    }
}

