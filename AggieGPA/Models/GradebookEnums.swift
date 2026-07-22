import Foundation

enum GradingMethod: String, Codable, CaseIterable, Sendable {
    case weightedCategories
    case totalPoints
    case hybrid
    case manualLetterGradeOnly
}

enum MissingItemPolicy: String, Codable, CaseIterable, Sendable {
    case excludeUntilGraded
    case countMissingAsZero
}

enum SyllabusImportSource: String, Codable, CaseIterable, Sendable {
    case none
    case pdf
    case image
    case camera
    case pastedText
    case manual
}

enum GradingPolicyImportStatus: String, Codable, CaseIterable, Sendable {
    case notImported
    case draft
    case needsReview
    case confirmed
    case failed
}

enum GradeCategoryType: String, Codable, CaseIterable, Identifiable, Sendable {
    case homework
    case quiz
    case lab
    case discussion
    case participation
    case attendance
    case project
    case presentation
    case midterm
    case finalExam
    case extraCredit
    case custom

    var id: String { rawValue }
}

enum CategoryCalculationMode: String, Codable, CaseIterable, Sendable {
    case weightedCategory
    case totalPoints
    case equalItems
    case custom
}

enum GradeItemStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case upcoming
    case submitted
    case graded
    case missing
    case excused
    case dropped
    case notCounted

    var id: String { rawValue }
}

enum ReminderLeadTime: String, Codable, CaseIterable, Sendable {
    case oneDay
    case threeDays
    case oneWeek
    case custom
}

enum ForecastScenarioKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case bestCase
    case expected
    case conservative
    case finalsGoal
    case custom

    var id: String { rawValue }
}

enum GradeLetter: String, Codable, CaseIterable, Identifiable, Sendable {
    case aPlus = "A+"
    case a = "A"
    case aMinus = "A-"
    case bPlus = "B+"
    case b = "B"
    case bMinus = "B-"
    case cPlus = "C+"
    case c = "C"
    case cMinus = "C-"
    case dPlus = "D+"
    case d = "D"
    case dMinus = "D-"
    case f = "F"

    var id: String { rawValue }
}
