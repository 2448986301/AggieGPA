import Foundation
import SwiftData

nonisolated struct CourseTemplateCategorySnapshot: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var categoryType: GradeCategoryType
    var weight: Decimal
    var calculationMode: CategoryCalculationMode
    var dropLowestCount: Int
    var isExtraCredit: Bool
    var isIncluded: Bool
    var sortOrder: Int

    init(
        id: UUID = UUID(), name: String, categoryType: GradeCategoryType,
        weight: Decimal, calculationMode: CategoryCalculationMode = .totalPoints,
        dropLowestCount: Int = 0, isExtraCredit: Bool = false, isIncluded: Bool = true,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.categoryType = categoryType
        self.weight = weight
        self.calculationMode = calculationMode
        self.dropLowestCount = max(0, dropLowestCount)
        self.isExtraCredit = isExtraCredit
        self.isIncluded = isIncluded
        self.sortOrder = sortOrder
    }
}

nonisolated struct CourseTemplateScaleSnapshot: Codable, Equatable, Sendable {
    var name: String
    var boundaries: [GradeScaleBoundary]
    var isLetterPredictionEnabled: Bool
    var isCommonTemplate: Bool
    var curveNote: String
    var requiresManualReview: Bool
}

@Model
final class CourseTemplate {
    @Attribute(.unique) var id: UUID
    var name: String
    var sourceCourseID: UUID?
    var gradingMethodRaw: String
    var normalizeCurrentGrade: Bool
    var missingItemPolicyRaw: String
    var missingPolicyConfirmed: Bool
    var targetPercentage: Decimal?
    var targetLetterGradeRaw: String?
    var categoriesData: Data
    var gradeScaleData: Data?
    var defaultReminderEnabled: Bool
    var defaultReminderLeadTimeRaw: String
    var defaultCustomReminderDate: Date?
    var isBuiltIn: Bool
    var createdAt: Date
    var updatedAt: Date

    var gradingMethod: GradingMethod {
        get { GradingMethod(rawValue: gradingMethodRaw) ?? .weightedCategories }
        set { gradingMethodRaw = newValue.rawValue }
    }

    var missingItemPolicy: MissingItemPolicy {
        get { MissingItemPolicy(rawValue: missingItemPolicyRaw) ?? .excludeUntilGraded }
        set { missingItemPolicyRaw = newValue.rawValue }
    }

    var targetLetterGrade: GradeLetter? {
        get { targetLetterGradeRaw.flatMap(GradeLetter.init(rawValue:)) }
        set { targetLetterGradeRaw = newValue?.rawValue }
    }

    var defaultReminderLeadTime: ReminderLeadTime {
        get { ReminderLeadTime(rawValue: defaultReminderLeadTimeRaw) ?? .oneDay }
        set { defaultReminderLeadTimeRaw = newValue.rawValue }
    }

    var categories: [CourseTemplateCategorySnapshot] {
        get { (try? JSONDecoder().decode([CourseTemplateCategorySnapshot].self, from: categoriesData)) ?? [] }
        set { categoriesData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var gradeScale: CourseTemplateScaleSnapshot? {
        get {
            guard let gradeScaleData else { return nil }
            return try? JSONDecoder().decode(CourseTemplateScaleSnapshot.self, from: gradeScaleData)
        }
        set { gradeScaleData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    init(
        id: UUID = UUID(), name: String, sourceCourseID: UUID? = nil,
        gradingMethod: GradingMethod = .weightedCategories,
        normalizeCurrentGrade: Bool = true,
        missingItemPolicy: MissingItemPolicy = .excludeUntilGraded,
        missingPolicyConfirmed: Bool = false,
        targetPercentage: Decimal? = nil,
        targetLetterGrade: GradeLetter? = nil,
        categories: [CourseTemplateCategorySnapshot] = [],
        gradeScale: CourseTemplateScaleSnapshot? = nil,
        defaultReminderEnabled: Bool = false,
        defaultReminderLeadTime: ReminderLeadTime = .oneDay,
        defaultCustomReminderDate: Date? = nil,
        isBuiltIn: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.sourceCourseID = sourceCourseID
        self.gradingMethodRaw = gradingMethod.rawValue
        self.normalizeCurrentGrade = normalizeCurrentGrade
        self.missingItemPolicyRaw = missingItemPolicy.rawValue
        self.missingPolicyConfirmed = missingPolicyConfirmed
        self.targetPercentage = targetPercentage
        self.targetLetterGradeRaw = targetLetterGrade?.rawValue
        self.categoriesData = (try? JSONEncoder().encode(categories)) ?? Data()
        self.gradeScaleData = gradeScale.flatMap { try? JSONEncoder().encode($0) }
        self.defaultReminderEnabled = defaultReminderEnabled
        self.defaultReminderLeadTimeRaw = defaultReminderLeadTime.rawValue
        self.defaultCustomReminderDate = defaultCustomReminderDate
        self.isBuiltIn = isBuiltIn
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Optional per-course defaults captured by a template without changing the
/// historical CourseRecord schema. Keeping this as its own model lets an
/// existing SwiftData store migrate without changing CourseRecord's hash.
@Model
final class CourseReminderDefaults {
    @Attribute(.unique) var courseID: UUID
    var reminderEnabled: Bool
    var reminderLeadTimeRaw: String
    var customReminderDate: Date?
    var createdAt: Date
    var updatedAt: Date

    var reminderLeadTime: ReminderLeadTime {
        get { ReminderLeadTime(rawValue: reminderLeadTimeRaw) ?? .oneDay }
        set { reminderLeadTimeRaw = newValue.rawValue }
    }

    init(
        courseID: UUID, reminderEnabled: Bool = false,
        reminderLeadTime: ReminderLeadTime = .oneDay,
        customReminderDate: Date? = nil,
        createdAt: Date = .now, updatedAt: Date = .now
    ) {
        self.courseID = courseID
        self.reminderEnabled = reminderEnabled
        self.reminderLeadTimeRaw = reminderLeadTime.rawValue
        self.customReminderDate = customReminderDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
