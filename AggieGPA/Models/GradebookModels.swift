import Foundation
import SwiftData

@Model
final class CourseGradingPolicy {
    @Attribute(.unique) var id: UUID
    var course: CourseRecord?
    var gradingMethodRaw: String
    var normalizeCurrentGrade: Bool
    var missingItemPolicyRaw: String
    var missingPolicyConfirmed: Bool
    var targetPercentage: Decimal?
    var targetLetterGradeRaw: String?
    var syllabusImportSourceRaw: String
    var importStatusRaw: String
    var manualReviewReason: String
    var lastCalculatedAt: Date?
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

    var syllabusImportSource: SyllabusImportSource {
        get { SyllabusImportSource(rawValue: syllabusImportSourceRaw) ?? .none }
        set { syllabusImportSourceRaw = newValue.rawValue }
    }

    var importStatus: GradingPolicyImportStatus {
        get { GradingPolicyImportStatus(rawValue: importStatusRaw) ?? .notImported }
        set { importStatusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        course: CourseRecord? = nil,
        gradingMethod: GradingMethod = .weightedCategories,
        normalizeCurrentGrade: Bool = true,
        missingItemPolicy: MissingItemPolicy = .excludeUntilGraded,
        missingPolicyConfirmed: Bool = false,
        targetPercentage: Decimal? = nil,
        targetLetterGrade: GradeLetter? = nil,
        syllabusImportSource: SyllabusImportSource = .none,
        importStatus: GradingPolicyImportStatus = .notImported,
        manualReviewReason: String = "",
        lastCalculatedAt: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.course = course
        self.gradingMethodRaw = gradingMethod.rawValue
        self.normalizeCurrentGrade = normalizeCurrentGrade
        self.missingItemPolicyRaw = missingItemPolicy.rawValue
        self.missingPolicyConfirmed = missingPolicyConfirmed
        self.targetPercentage = targetPercentage
        self.targetLetterGradeRaw = targetLetterGrade?.rawValue
        self.syllabusImportSourceRaw = syllabusImportSource.rawValue
        self.importStatusRaw = importStatus.rawValue
        self.manualReviewReason = manualReviewReason
        self.lastCalculatedAt = lastCalculatedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class GradingCategory {
    @Attribute(.unique) var id: UUID
    var course: CourseRecord?
    var name: String
    var categoryTypeRaw: String
    var weight: Decimal
    var calculationModeRaw: String
    var dropLowestCount: Int
    var isExtraCredit: Bool
    var isIncluded: Bool
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    var categoryType: GradeCategoryType {
        get { GradeCategoryType(rawValue: categoryTypeRaw) ?? .custom }
        set { categoryTypeRaw = newValue.rawValue }
    }

    var calculationMode: CategoryCalculationMode {
        get { CategoryCalculationMode(rawValue: calculationModeRaw) ?? .totalPoints }
        set { calculationModeRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(), course: CourseRecord? = nil, name: String,
        categoryType: GradeCategoryType = .custom, weight: Decimal = 0,
        calculationMode: CategoryCalculationMode = .totalPoints,
        dropLowestCount: Int = 0, isExtraCredit: Bool = false,
        isIncluded: Bool = true, sortOrder: Int = 0,
        createdAt: Date = .now, updatedAt: Date = .now
    ) {
        self.id = id
        self.course = course
        self.name = name
        self.categoryTypeRaw = categoryType.rawValue
        self.weight = weight
        self.calculationModeRaw = calculationMode.rawValue
        self.dropLowestCount = max(0, dropLowestCount)
        self.isExtraCredit = isExtraCredit
        self.isIncluded = isIncluded
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class GradeItem {
    @Attribute(.unique) var id: UUID
    var course: CourseRecord?
    var category: GradingCategory?
    var title: String
    var dueDate: Date?
    var earnedPoints: Decimal?
    var possiblePoints: Decimal
    var percentageOverride: Decimal?
    var statusRaw: String
    var isIncluded: Bool
    var isExtraCredit: Bool
    var isDropped: Bool
    var isExcused: Bool
    var multiplier: Decimal
    var notes: String
    var reminderEnabled: Bool
    var reminderLeadTimeRaw: String
    var customReminderDate: Date?
    var notificationIdentifier: String
    var createdAt: Date
    var updatedAt: Date

    var status: GradeItemStatus {
        get { GradeItemStatus(rawValue: statusRaw) ?? .upcoming }
        set { statusRaw = newValue.rawValue }
    }

    var reminderLeadTime: ReminderLeadTime {
        get { ReminderLeadTime(rawValue: reminderLeadTimeRaw) ?? .oneDay }
        set { reminderLeadTimeRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(), course: CourseRecord? = nil, category: GradingCategory? = nil,
        title: String, dueDate: Date? = nil, earnedPoints: Decimal? = nil,
        possiblePoints: Decimal = 0, percentageOverride: Decimal? = nil,
        status: GradeItemStatus = .upcoming, isIncluded: Bool = true,
        isExtraCredit: Bool = false, isDropped: Bool = false,
        isExcused: Bool = false, multiplier: Decimal = 1, notes: String = "",
        reminderEnabled: Bool = false, reminderLeadTime: ReminderLeadTime = .oneDay,
        customReminderDate: Date? = nil, notificationIdentifier: String? = nil,
        createdAt: Date = .now, updatedAt: Date = .now
    ) {
        self.id = id
        self.course = course
        self.category = category
        self.title = title
        self.dueDate = dueDate
        self.earnedPoints = earnedPoints
        self.possiblePoints = possiblePoints
        self.percentageOverride = percentageOverride
        self.statusRaw = status.rawValue
        self.isIncluded = isIncluded
        self.isExtraCredit = isExtraCredit
        self.isDropped = isDropped
        self.isExcused = isExcused
        self.multiplier = multiplier
        self.notes = notes
        self.reminderEnabled = reminderEnabled
        self.reminderLeadTimeRaw = reminderLeadTime.rawValue
        self.customReminderDate = customReminderDate
        self.notificationIdentifier = notificationIdentifier ?? "grade-item-\(id.uuidString)"
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct GradeScaleBoundary: Codable, Equatable, Sendable {
    var letter: GradeLetter
    var minimumPercentage: Decimal
}

@Model
final class GradeScale {
    @Attribute(.unique) var id: UUID
    var course: CourseRecord?
    var name: String
    var boundariesData: Data
    var isLetterPredictionEnabled: Bool
    var isCommonTemplate: Bool
    var curveNote: String
    var requiresManualReview: Bool
    var createdAt: Date
    var updatedAt: Date

    var boundaries: [GradeScaleBoundary] {
        get { (try? JSONDecoder().decode([GradeScaleBoundary].self, from: boundariesData)) ?? [] }
        set { boundariesData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    init(
        id: UUID = UUID(), course: CourseRecord? = nil, name: String = "Custom Scale",
        boundaries: [GradeScaleBoundary] = [], isLetterPredictionEnabled: Bool = true,
        isCommonTemplate: Bool = false, curveNote: String = "",
        requiresManualReview: Bool = false, createdAt: Date = .now, updatedAt: Date = .now
    ) {
        self.id = id
        self.course = course
        self.name = name
        self.boundariesData = (try? JSONEncoder().encode(boundaries)) ?? Data()
        self.isLetterPredictionEnabled = isLetterPredictionEnabled
        self.isCommonTemplate = isCommonTemplate
        self.curveNote = curveNote
        self.requiresManualReview = requiresManualReview
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class ForecastScenario {
    @Attribute(.unique) var id: UUID
    var course: CourseRecord?
    var name: String
    var kindRaw: String
    var assumedRemainingPercentage: Decimal
    var itemAssumptionsData: Data
    var isSelectedForGPAForecast: Bool
    var createdAt: Date
    var updatedAt: Date

    var kind: ForecastScenarioKind {
        get { ForecastScenarioKind(rawValue: kindRaw) ?? .custom }
        set { kindRaw = newValue.rawValue }
    }

    var itemAssumptions: [UUID: Decimal] {
        get { (try? JSONDecoder().decode([UUID: Decimal].self, from: itemAssumptionsData)) ?? [:] }
        set { itemAssumptionsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    init(
        id: UUID = UUID(), course: CourseRecord? = nil, name: String,
        kind: ForecastScenarioKind = .custom, assumedRemainingPercentage: Decimal = 85,
        itemAssumptions: [UUID: Decimal] = [:], isSelectedForGPAForecast: Bool = false,
        createdAt: Date = .now, updatedAt: Date = .now
    ) {
        self.id = id
        self.course = course
        self.name = name
        self.kindRaw = kind.rawValue
        self.assumedRemainingPercentage = assumedRemainingPercentage
        self.itemAssumptionsData = (try? JSONEncoder().encode(itemAssumptions)) ?? Data()
        self.isSelectedForGPAForecast = isSelectedForGPAForecast
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class SiriAccessSettings {
    @Attribute(.unique) var id: UUID
    var isSiriAccessEnabled: Bool
    var allowAssignmentSummaries: Bool
    var allowDetailedScores: Bool
    var allowGPAResponses: Bool
    var allowCreatingDrafts: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(), isSiriAccessEnabled: Bool = false,
        allowAssignmentSummaries: Bool = false, allowDetailedScores: Bool = false,
        allowGPAResponses: Bool = false, allowCreatingDrafts: Bool = false,
        createdAt: Date = .now, updatedAt: Date = .now
    ) {
        self.id = id
        self.isSiriAccessEnabled = isSiriAccessEnabled
        self.allowAssignmentSummaries = allowAssignmentSummaries
        self.allowDetailedScores = allowDetailedScores
        self.allowGPAResponses = allowGPAResponses
        self.allowCreatingDrafts = allowCreatingDrafts
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
