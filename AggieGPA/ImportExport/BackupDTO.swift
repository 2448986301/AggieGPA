import Foundation

struct BackupEnvelope: Codable, Equatable {
    static let currentSchemaVersion = 1
    var schemaVersion: Int
    var exportDate: Date
    var appVersion: String
    var terms: [TermDTO]
    var courses: [CourseDTO]
    var plannerScenarios: [ScenarioDTO]
    var preferences: PreferencesDTO

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
}

struct ImportPreview: Equatable {
    let envelope: BackupEnvelope
    let duplicateTermCount: Int
    let duplicateCourseCount: Int
}

enum ImportMode { case merge, replace }
