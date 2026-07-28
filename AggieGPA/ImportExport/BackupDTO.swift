import Foundation

struct BackupEnvelope: Codable, Equatable {
  static let currentSchemaVersion = 2
  var schemaVersion: Int
  var exportDate: Date
  var appVersion: String
  var terms: [TermDTO]
  var courses: [CourseDTO]
  var plannerScenarios: [ScenarioDTO]
  var preferences: PreferencesDTO
  var gradingPolicies: [GradingPolicyDTO]?
  var gradingCategories: [GradingCategoryDTO]?
  var gradeItems: [GradeItemDTO]?
  var gradeScales: [GradeScaleDTO]?
  var forecastScenarios: [ForecastScenarioDTO]?
  var siriSettings: SiriSettingsDTO?

  struct TermDTO: Codable, Equatable {
    var id: UUID
    var academicYear: String
    var termType: TermType
    var displayName: String
    var startDate: Date?
    var endDate: Date?
    var isIncludedInCumulativeGPA: Bool
    var notes: String
    var createdAt: Date
    var updatedAt: Date
    var sortOrder: Int
  }

  struct CourseDTO: Codable, Equatable {
    var id: UUID
    var termID: UUID?
    var courseCode: String
    var courseTitle: String
    var units: Decimal
    var grade: CourseGrade
    var gradingBasis: GradingBasis
    var institution: InstitutionType
    var isMajorCourse: Bool
    var isUpperDivision: Bool
    var isIncludedInGPA: Bool
    var isTransferCourse: Bool
    var isRepeatCourse: Bool
    var repeatGroupID: UUID?
    var repeatAttemptOrder: Int
    var repeatHandlingMode: RepeatHandlingMode
    var targetGrade: CourseGrade?
    var notes: String
    var customColor: String?
    var createdAt: Date
    var updatedAt: Date
    var isDemoData: Bool
  }

  struct ScenarioDTO: Codable, Equatable {
    var id: UUID
    var name: String
    var scenarioType: ScenarioType
    var associatedTermID: UUID?
    var createdAt: Date
    var updatedAt: Date
    var sortOrder: Int
    var courses: [SimulatedCourseDTO]
  }

  struct SimulatedCourseDTO: Codable, Equatable {
    var id: UUID
    var sourceCourseID: UUID?
    var courseCode: String
    var units: Decimal
    var grade: CourseGrade
    var isIncludedInGPA: Bool
    var isMajorCourse: Bool
    var isUpperDivision: Bool
    var confidence: Int
    var notes: String
  }

  struct PreferencesDTO: Codable, Equatable {
    var displayName: String
    var major: String
    var targetGPA: Decimal
    var firstAcademicYear: String
    var decimalPrecision: Int
    var appearance: AppAppearance
    var language: AppLanguage?
    var hapticsEnabled: Bool
    var showMajorGPA: Bool
    var showUpperDivisionGPA: Bool
    var showRepeatSummary: Bool
    var defaultGradingBasis: GradingBasis
  }

  struct GradingPolicyDTO: Codable, Equatable {
    var id: UUID
    var courseID: UUID
    var gradingMethod: GradingMethod
    var normalizeCurrentGrade: Bool
    var missingItemPolicy: MissingItemPolicy
    var missingPolicyConfirmed: Bool
    var targetPercentage: Decimal?
    var targetLetterGrade: GradeLetter?
    var syllabusImportSource: SyllabusImportSource
    var importStatus: GradingPolicyImportStatus
    var manualReviewReason: String
    var lastCalculatedAt: Date?
    var createdAt: Date
    var updatedAt: Date
  }

  struct GradingCategoryDTO: Codable, Equatable {
    var id: UUID
    var courseID: UUID
    var name: String
    var categoryType: GradeCategoryType
    var weight: Decimal
    var calculationMode: CategoryCalculationMode
    var dropLowestCount: Int
    var isExtraCredit: Bool
    var isIncluded: Bool
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
  }

  struct GradeItemDTO: Codable, Equatable {
    var id: UUID
    var courseID: UUID
    var categoryID: UUID?
    var title: String
    var dueDate: Date?
    var earnedPoints: Decimal?
    var possiblePoints: Decimal
    var percentageOverride: Decimal?
    var status: GradeItemStatus
    var isIncluded: Bool
    var isExtraCredit: Bool
    var isDropped: Bool
    var isExcused: Bool
    var multiplier: Decimal
    var notes: String
    var reminderEnabled: Bool
    var reminderLeadTime: ReminderLeadTime
    var customReminderDate: Date?
    var notificationIdentifier: String
    var createdAt: Date
    var updatedAt: Date
  }

  struct GradeScaleDTO: Codable, Equatable {
    var id: UUID
    var courseID: UUID
    var name: String
    var boundaries: [GradeScaleBoundary]
    var isLetterPredictionEnabled: Bool
    var isCommonTemplate: Bool
    var curveNote: String
    var requiresManualReview: Bool
    var createdAt: Date
    var updatedAt: Date
  }

  struct ForecastScenarioDTO: Codable, Equatable {
    var id: UUID
    var courseID: UUID
    var name: String
    var kind: ForecastScenarioKind
    var assumedRemainingPercentage: Decimal
    var itemAssumptions: [UUID: Decimal]
    var isSelectedForGPAForecast: Bool
    var createdAt: Date
    var updatedAt: Date
  }

  struct SiriSettingsDTO: Codable, Equatable {
    var id: UUID
    var isSiriAccessEnabled: Bool
    var allowAssignmentSummaries: Bool
    var allowDetailedScores: Bool
    var allowGPAResponses: Bool
    var allowCreatingDrafts: Bool
    var createdAt: Date
    var updatedAt: Date
  }
}

struct ImportPreview: Equatable {
  let envelope: BackupEnvelope
  let duplicateTermCount: Int
  let duplicateCourseCount: Int
}

enum ImportMode { case merge, replace }
