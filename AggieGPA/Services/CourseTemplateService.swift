import Foundation
import SwiftData

@MainActor
enum CourseTemplateService {
    static func seedBuiltInsIfNeeded(context: ModelContext, templates: [CourseTemplate]) {
        let builtIns = builtInTemplates()
        let existingBuiltInNames = Set(templates.filter(\.isBuiltIn).map { $0.name.lowercased() })
        let missing = builtIns.filter { !existingBuiltInNames.contains($0.name.lowercased()) }
        guard !missing.isEmpty else {
            return
        }
        for template in missing { context.insert(template) }
        try? context.save()
    }

    static func capture(
        name: String,
        course: CourseRecord,
        policy: CourseGradingPolicy?,
        categories: [GradingCategory],
        scale: GradeScale?,
        items: [GradeItem] = []
    ) -> CourseTemplate {
        let reminderDefaults = items
            .filter { !$0.isDeleted && $0.course?.id == course.id }
            .sorted { $0.updatedAt > $1.updatedAt }
            .first(where: \.reminderEnabled)
        return CourseTemplate(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            sourceCourseID: course.id,
            gradingMethod: policy?.gradingMethod ?? .weightedCategories,
            normalizeCurrentGrade: policy?.normalizeCurrentGrade ?? true,
            missingItemPolicy: policy?.missingItemPolicy ?? .excludeUntilGraded,
            missingPolicyConfirmed: policy?.missingPolicyConfirmed ?? false,
            targetPercentage: policy?.targetPercentage,
            targetLetterGrade: policy?.targetLetterGrade,
            categories: categories
                .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
                .map {
                    CourseTemplateCategorySnapshot(
                        id: $0.id, name: $0.name, categoryType: $0.categoryType,
                        weight: $0.weight, calculationMode: $0.calculationMode,
                        dropLowestCount: $0.dropLowestCount, isExtraCredit: $0.isExtraCredit,
                        isIncluded: $0.isIncluded, sortOrder: $0.sortOrder
                    )
                },
            gradeScale: scale.map {
                CourseTemplateScaleSnapshot(
                    name: $0.name, boundaries: $0.boundaries,
                    isLetterPredictionEnabled: $0.isLetterPredictionEnabled,
                    isCommonTemplate: $0.isCommonTemplate, curveNote: $0.curveNote,
                    requiresManualReview: $0.requiresManualReview
                )
            },
            defaultReminderEnabled: reminderDefaults?.reminderEnabled ?? false,
            defaultReminderLeadTime: reminderDefaults?.reminderLeadTime ?? .oneDay,
            defaultCustomReminderDate: reminderDefaults?.customReminderDate
        )
    }

    static func createCourse(
        from template: CourseTemplate,
        courseCode: String,
        courseTitle: String,
        units: Decimal,
        term: AcademicTerm,
        gradingBasis: GradingBasis,
        copyCommonSettings: Bool,
        copyReminders: Bool,
        context: ModelContext
    ) throws -> CourseRecord {
        let course = CourseRecord(
            courseCode: courseCode.trimmingCharacters(in: .whitespacesAndNewlines),
            courseTitle: courseTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            units: units, grade: .noGrade, gradingBasis: gradingBasis, term: term,
        )
        context.insert(course)

        if copyReminders {
            context.insert(
                CourseReminderDefaults(
                    courseID: course.id,
                    reminderEnabled: template.defaultReminderEnabled,
                    reminderLeadTime: template.defaultReminderLeadTime,
                    customReminderDate: template.defaultCustomReminderDate
                )
            )
        }

        let policy = CourseGradingPolicy(
            course: course,
            gradingMethod: template.gradingMethod,
            normalizeCurrentGrade: copyCommonSettings ? template.normalizeCurrentGrade : true,
            missingItemPolicy: copyCommonSettings ? template.missingItemPolicy : .excludeUntilGraded,
            missingPolicyConfirmed: copyCommonSettings && template.missingPolicyConfirmed,
            targetPercentage: copyCommonSettings ? template.targetPercentage : nil,
            targetLetterGrade: copyCommonSettings ? template.targetLetterGrade : nil
        )
        context.insert(policy)

        var usedNames = Set<String>()
        for snapshot in template.categories.sorted(by: { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }) {
            let key = snapshot.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty, usedNames.insert(key).inserted else { continue }
            context.insert(
                GradingCategory(
                    course: course, name: snapshot.name, categoryType: snapshot.categoryType,
                    weight: snapshot.weight, calculationMode: snapshot.calculationMode,
                    dropLowestCount: snapshot.dropLowestCount, isExtraCredit: snapshot.isExtraCredit,
                    isIncluded: snapshot.isIncluded, sortOrder: snapshot.sortOrder
                )
            )
        }

        if let snapshot = template.gradeScale {
            context.insert(
                GradeScale(
                    course: course, name: snapshot.name, boundaries: snapshot.boundaries,
                    isLetterPredictionEnabled: snapshot.isLetterPredictionEnabled,
                    isCommonTemplate: snapshot.isCommonTemplate, curveNote: snapshot.curveNote,
                    requiresManualReview: snapshot.requiresManualReview
                )
            )
        }

        do {
            try context.save()
            return course
        } catch {
            context.rollback()
            throw error
        }
    }

    static func builtInTemplates() -> [CourseTemplate] {
        let scale = CourseTemplateScaleSnapshot(
            name: "Common Scale Template", boundaries: standardScale,
            isLetterPredictionEnabled: true, isCommonTemplate: true,
            curveNote: "", requiresManualReview: false
        )
        return [
            CourseTemplate(
                name: "Weighted Categories", gradingMethod: .weightedCategories,
                categories: [
                    category("Homework", .homework, 40, 0), category("Quizzes", .quiz, 20, 1),
                    category("Midterms", .midterm, 20, 2), category("Final Exam", .finalExam, 20, 3)
                ], gradeScale: scale, isBuiltIn: true
            ),
            CourseTemplate(
                name: "Points Based", gradingMethod: .totalPoints,
                categories: [category("Course Points", .custom, 100, 0, mode: .totalPoints)],
                gradeScale: scale, isBuiltIn: true
            ),
            CourseTemplate(
                name: "Homework / Quizzes / Midterms / Final", gradingMethod: .weightedCategories,
                categories: [
                    category("Homework", .homework, 25, 0), category("Quizzes", .quiz, 15, 1),
                    category("Midterms", .midterm, 25, 2), category("Final Exam", .finalExam, 35, 3)
                ], gradeScale: scale, isBuiltIn: true
            )
        ]
    }

    private static func category(
        _ name: String, _ type: GradeCategoryType, _ weight: Decimal, _ order: Int,
        mode: CategoryCalculationMode = .weightedCategory
    ) -> CourseTemplateCategorySnapshot {
        CourseTemplateCategorySnapshot(
            name: name, categoryType: type, weight: weight,
            calculationMode: mode, sortOrder: order
        )
    }

    private static let standardScale: [GradeScaleBoundary] = [
        .init(letter: .aPlus, minimumPercentage: 97), .init(letter: .a, minimumPercentage: 93),
        .init(letter: .aMinus, minimumPercentage: 90), .init(letter: .bPlus, minimumPercentage: 87),
        .init(letter: .b, minimumPercentage: 83), .init(letter: .bMinus, minimumPercentage: 80),
        .init(letter: .cPlus, minimumPercentage: 77), .init(letter: .c, minimumPercentage: 73),
        .init(letter: .cMinus, minimumPercentage: 70), .init(letter: .dPlus, minimumPercentage: 67),
        .init(letter: .d, minimumPercentage: 63), .init(letter: .dMinus, minimumPercentage: 60),
        .init(letter: .f, minimumPercentage: 0)
    ]
}
