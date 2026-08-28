import Foundation
import SwiftData

@Model
final class AcademicTerm {
    @Attribute(.unique) var id: UUID
    var academicYear: String
    var termTypeRaw: String
    var displayName: String
    var startDate: Date?
    var endDate: Date?
    var isIncludedInCumulativeGPA: Bool
    var notes: String
    var createdAt: Date
    var updatedAt: Date
    var sortOrder: Int

    @Relationship(deleteRule: .cascade, inverse: \CourseRecord.term)
    var courses: [CourseRecord]

    var termType: TermType {
        get { TermType(rawValue: termTypeRaw) ?? .other }
        set { termTypeRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(), academicYear: String, termType: TermType,
        displayName: String? = nil, startDate: Date? = nil, endDate: Date? = nil,
        isIncludedInCumulativeGPA: Bool = true, notes: String = "",
        createdAt: Date = .now, updatedAt: Date = .now, sortOrder: Int = 0,
        courses: [CourseRecord] = []
    ) {
        self.id = id
        self.academicYear = academicYear
        self.termTypeRaw = termType.rawValue
        self.displayName = displayName ?? "\(termType.rawValue) \(academicYear.split(separator: "–").first ?? Substring(academicYear))"
        self.startDate = startDate
        self.endDate = endDate
        self.isIncludedInCumulativeGPA = isIncludedInCumulativeGPA
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sortOrder = sortOrder
        self.courses = courses
    }
}

@Model
final class CourseRecord {
    @Attribute(.unique) var id: UUID
    var courseCode: String
    var courseTitle: String
    var units: Decimal
    var gradeRaw: String
    var gradingBasisRaw: String
    var institutionRaw: String
    var isMajorCourse: Bool
    var isUpperDivision: Bool
    var isIncludedInGPA: Bool
    var isTransferCourse: Bool
    var isRepeatCourse: Bool
    var repeatGroupID: UUID?
    var repeatAttemptOrder: Int
    var repeatHandlingModeRaw: String
    var targetGradeRaw: String?
    var notes: String
    var customColor: String?
    var createdAt: Date
    var updatedAt: Date
    var isDemoData: Bool

    var term: AcademicTerm?

    var grade: CourseGrade {
        get { CourseGrade(rawValue: gradeRaw) ?? .noGrade }
        set { gradeRaw = newValue.rawValue }
    }
    var gradingBasis: GradingBasis {
        get { GradingBasis(rawValue: gradingBasisRaw) ?? .letter }
        set { gradingBasisRaw = newValue.rawValue }
    }
    var institution: InstitutionType {
        get { InstitutionType(rawValue: institutionRaw) ?? .ucDavis }
        set { institutionRaw = newValue.rawValue }
    }
    var repeatHandlingMode: RepeatHandlingMode {
        get { RepeatHandlingMode(rawValue: repeatHandlingModeRaw) ?? .manualReview }
        set { repeatHandlingModeRaw = newValue.rawValue }
    }
    var targetGrade: CourseGrade? {
        get { targetGradeRaw.flatMap(CourseGrade.init(rawValue:)) }
        set { targetGradeRaw = newValue?.rawValue }
    }

    init(
        id: UUID = UUID(), courseCode: String, courseTitle: String = "", units: Decimal,
        grade: CourseGrade, gradingBasis: GradingBasis = .letter,
        institution: InstitutionType = .ucDavis, term: AcademicTerm? = nil,
        isMajorCourse: Bool = false, isUpperDivision: Bool = false,
        isIncludedInGPA: Bool = true, isTransferCourse: Bool = false,
        isRepeatCourse: Bool = false, repeatGroupID: UUID? = nil,
        repeatAttemptOrder: Int = 0, repeatHandlingMode: RepeatHandlingMode = .manualReview,
        targetGrade: CourseGrade? = nil, notes: String = "", customColor: String? = nil,
        createdAt: Date = .now, updatedAt: Date = .now, isDemoData: Bool = false
    ) {
        self.id = id
        self.courseCode = courseCode
        self.courseTitle = courseTitle
        self.units = units
        self.gradeRaw = grade.rawValue
        self.gradingBasisRaw = gradingBasis.rawValue
        self.institutionRaw = institution.rawValue
        self.term = term
        self.isMajorCourse = isMajorCourse
        self.isUpperDivision = isUpperDivision
        self.isIncludedInGPA = isIncludedInGPA
        self.isTransferCourse = isTransferCourse
        self.isRepeatCourse = isRepeatCourse
        self.repeatGroupID = repeatGroupID
        self.repeatAttemptOrder = repeatAttemptOrder
        self.repeatHandlingModeRaw = repeatHandlingMode.rawValue
        self.targetGradeRaw = targetGrade?.rawValue
        self.notes = notes
        self.customColor = customColor
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDemoData = isDemoData
    }

}
