import Foundation

@MainActor
enum CourseGradeSnapshotBuilder {
    static func makeInput(
        course: CourseRecord,
        policy: CourseGradingPolicy?,
        categories: [GradingCategory],
        items: [GradeItem],
        gradeScale: GradeScale?,
        forecast: ForecastScenario?
    ) -> CourseGradeCalculationInput {
        let courseCategories = categories
            .filter { $0.course?.id == course.id }
            .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
        let courseItems = items.filter { $0.course?.id == course.id }

        let categoryInputs = courseCategories.map { category in
            GradingCategoryCalculationInput(
                id: category.id,
                name: category.name,
                categoryType: category.categoryType,
                weight: category.weight,
                calculationMode: category.calculationMode,
                dropLowestCount: category.dropLowestCount,
                isExtraCredit: category.isExtraCredit,
                isIncluded: category.isIncluded,
                items: courseItems
                    .filter { $0.category?.id == category.id }
                    .map { itemInput($0, fallbackType: category.categoryType) }
            )
        }

        let unassigned = courseItems
            .filter { $0.category == nil }
            .map { itemInput($0, fallbackType: .custom) }
        let scaleInput = gradeScale.map {
            CourseGradeScaleInput(
                isEnabled: $0.isLetterPredictionEnabled,
                boundaries: $0.boundaries
            )
        }
        let forecastInput = forecast.map {
            CourseForecastInput(
                assumedRemainingPercentage: $0.assumedRemainingPercentage,
                itemPercentages: $0.itemAssumptions
            )
        }

        return CourseGradeCalculationInput(
            gradingMethod: policy?.gradingMethod ?? .weightedCategories,
            normalizeCurrentGrade: policy?.normalizeCurrentGrade ?? true,
            missingItemPolicy: policy?.missingItemPolicy ?? .excludeUntilGraded,
            missingPolicyConfirmed: policy?.missingPolicyConfirmed ?? false,
            categories: categoryInputs,
            unassignedItems: unassigned,
            gradeScale: scaleInput,
            targetPercentage: policy?.targetPercentage,
            forecast: forecastInput
        )
    }

    private static func itemInput(
        _ item: GradeItem,
        fallbackType: GradeCategoryType
    ) -> GradeItemCalculationInput {
        GradeItemCalculationInput(
            id: item.id,
            title: item.title,
            categoryType: item.category?.categoryType ?? fallbackType,
            earnedPoints: item.earnedPoints,
            possiblePoints: item.possiblePoints,
            percentageOverride: item.percentageOverride,
            status: item.status,
            isIncluded: item.isIncluded,
            isExtraCredit: item.isExtraCredit,
            isDropped: item.isDropped,
            isExcused: item.isExcused,
            multiplier: item.multiplier
        )
    }
}
