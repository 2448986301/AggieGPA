import Foundation

struct CourseCalculationInput: Identifiable, Equatable, Codable {
    let id: UUID
    var courseCode: String
    var units: Decimal
    var grade: CourseGrade
    var isIncludedInGPA: Bool
    var isMajorCourse: Bool
    var isUpperDivision: Bool
    var termID: UUID?
    var repeatGroupID: UUID?
    var repeatAttemptOrder: Int
    var repeatHandlingMode: RepeatHandlingMode
    var attemptedAt: Date

    init(id: UUID = UUID(), courseCode: String, units: Decimal, grade: CourseGrade,
         isIncludedInGPA: Bool = true, isMajorCourse: Bool = false,
         isUpperDivision: Bool = false, termID: UUID? = nil, repeatGroupID: UUID? = nil,
         repeatAttemptOrder: Int = 0, repeatHandlingMode: RepeatHandlingMode = .manualReview,
         attemptedAt: Date = .now) {
        self.id = id
        self.courseCode = courseCode
        self.units = units
        self.grade = grade
        self.isIncludedInGPA = isIncludedInGPA
        self.isMajorCourse = isMajorCourse
        self.isUpperDivision = isUpperDivision
        self.termID = termID
        self.repeatGroupID = repeatGroupID
        self.repeatAttemptOrder = repeatAttemptOrder
        self.repeatHandlingMode = repeatHandlingMode
        self.attemptedAt = attemptedAt
    }
}

extension CourseCalculationInput {
    init(_ course: CourseRecord) {
        self.init(
            id: course.id, courseCode: course.courseCode, units: course.units,
            grade: course.grade, isIncludedInGPA: course.isIncludedInGPA,
            isMajorCourse: course.isMajorCourse, isUpperDivision: course.isUpperDivision,
            termID: course.term?.id, repeatGroupID: course.repeatGroupID,
            repeatAttemptOrder: course.repeatAttemptOrder,
            repeatHandlingMode: course.repeatHandlingMode, attemptedAt: course.createdAt
        )
    }

    init(_ course: SimulatedCourse) {
        self.init(
            id: course.id, courseCode: course.courseCode, units: course.units,
            grade: course.grade, isIncludedInGPA: course.isIncludedInGPA,
            isMajorCourse: course.isMajorCourse, isUpperDivision: course.isUpperDivision,
            attemptedAt: .distantFuture
        )
    }
}

struct GPAResult: Equatable {
    let gpa: Decimal?
    let attemptedUnits: Decimal
    let gradePoints: Decimal
    let includedCourseCount: Int
    let excludedCourseCount: Int

    static let empty = GPAResult(gpa: nil, attemptedUnits: 0, gradePoints: 0,
                                 includedCourseCount: 0, excludedCourseCount: 0)
}

struct RepeatEvaluation: Equatable {
    let includedIDs: Set<UUID>
    let excludedIDs: Set<UUID>
    let repeatUnitsUsed: Decimal
    let repeatUnitsRemaining: Decimal
    let includedAfterLimit: Set<UUID>
    let manualReviewGroupIDs: Set<UUID>
    let warnings: [String]
}
