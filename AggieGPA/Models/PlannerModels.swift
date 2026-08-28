import Foundation
import SwiftData

nonisolated private struct PlannerScenarioPlanningMetadata: Codable {
    var targetGPA: String?
    var selectedCourseIDs: [UUID]?
    var assumedGrades: [UUID: String]
}

@Model
final class PlannerScenario {
    @Attribute(.unique) var id: UUID
    var name: String
    var scenarioTypeRaw: String
    var associatedTerm: AcademicTerm?
    var createdAt: Date
    var updatedAt: Date
    var sortOrder: Int
    @Relationship(deleteRule: .cascade, inverse: \SimulatedCourse.scenario)
    var simulatedCourses: [SimulatedCourse]

    /// GPA 2.0 plan inputs. The calculated GPA is never persisted as source
    /// data; it is resolved again from the current gradebook when opened.
    ///
    /// These values are encoded in a private, non-GPA `SimulatedCourse` record
    /// so existing V1.4 stores can open without a destructive schema rewrite.
    /// The record is excluded from visible legacy courses and backup exports.
    var targetGPA: Decimal? {
        get {
            guard let raw = planningMetadata?.targetGPA else { return nil }
            return Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX"))
        }
        set {
            var metadata = planningMetadata ?? PlannerScenarioPlanningMetadata(targetGPA: nil, selectedCourseIDs: nil, assumedGrades: [:])
            metadata.targetGPA = newValue.map { NSDecimalNumber(decimal: $0).stringValue }
            savePlanningMetadata(metadata)
        }
    }

    var scenarioType: ScenarioType {
        get { ScenarioType(rawValue: scenarioTypeRaw) ?? .custom }
        set { scenarioTypeRaw = newValue.rawValue }
    }

    var selectedCourseIDs: Set<UUID>? {
        get {
            planningMetadata?.selectedCourseIDs.map(Set.init)
        }
        set {
            var metadata = planningMetadata ?? PlannerScenarioPlanningMetadata(targetGPA: nil, selectedCourseIDs: nil, assumedGrades: [:])
            metadata.selectedCourseIDs = newValue.map(Array.init)
            savePlanningMetadata(metadata)
        }
    }

    var assumedGrades: [UUID: CourseGrade] {
        get {
            guard let raw = planningMetadata?.assumedGrades else { return [:] }
            return raw.reduce(into: [:]) { result, entry in
                if let grade = CourseGrade(rawValue: entry.value) { result[entry.key] = grade }
            }
        }
        set {
            var metadata = planningMetadata ?? PlannerScenarioPlanningMetadata(targetGPA: nil, selectedCourseIDs: nil, assumedGrades: [:])
            metadata.assumedGrades = Dictionary(uniqueKeysWithValues: newValue.map { ($0.key, $0.value.rawValue) })
            savePlanningMetadata(metadata)
        }
    }

    var visibleSimulatedCourses: [SimulatedCourse] {
        simulatedCourses.filter { $0.courseCode != Self.metadataCourseCode }
    }

    private static let metadataCourseCode = "__AGGIE_GPA_2_PLAN_METADATA__"

    private var planningMetadata: PlannerScenarioPlanningMetadata? {
        guard let record = simulatedCourses.first(where: { $0.courseCode == Self.metadataCourseCode }),
              let data = record.notes.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PlannerScenarioPlanningMetadata.self, from: data)
    }

    private func savePlanningMetadata(_ metadata: PlannerScenarioPlanningMetadata) {
        guard let data = try? JSONEncoder().encode(metadata),
              let notes = String(data: data, encoding: .utf8) else { return }
        if let record = simulatedCourses.first(where: { $0.courseCode == Self.metadataCourseCode }) {
            record.notes = notes
            return
        }
        let record = SimulatedCourse(courseCode: Self.metadataCourseCode,
                                     units: 0,
                                     grade: .planned,
                                     isIncludedInGPA: false,
                                     confidence: 0,
                                     notes: notes,
                                     scenario: self)
        simulatedCourses.append(record)
    }

    init(id: UUID = UUID(), name: String, scenarioType: ScenarioType = .custom,
         associatedTerm: AcademicTerm? = nil, createdAt: Date = .now,
         updatedAt: Date = .now, sortOrder: Int = 0, targetGPA: Decimal? = nil,
         selectedCourseIDs: Set<UUID>? = nil, assumedGrades: [UUID: CourseGrade] = [:],
         simulatedCourses: [SimulatedCourse] = []) {
        self.id = id
        self.name = name
        self.scenarioTypeRaw = scenarioType.rawValue
        self.associatedTerm = associatedTerm
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sortOrder = sortOrder
        self.simulatedCourses = simulatedCourses
        let metadata = PlannerScenarioPlanningMetadata(
            targetGPA: targetGPA.map { NSDecimalNumber(decimal: $0).stringValue },
            selectedCourseIDs: selectedCourseIDs.map(Array.init),
            assumedGrades: Dictionary(uniqueKeysWithValues: assumedGrades.map { ($0.key, $0.value.rawValue) })
        )
        if metadata.targetGPA != nil || metadata.selectedCourseIDs != nil || !metadata.assumedGrades.isEmpty {
            savePlanningMetadata(metadata)
        }
    }
}

@Model
final class SimulatedCourse {
    @Attribute(.unique) var id: UUID
    var sourceCourseID: UUID?
    var courseCode: String
    var units: Decimal
    var gradeRaw: String
    var isIncludedInGPA: Bool
    var isMajorCourse: Bool
    var isUpperDivision: Bool
    var confidence: Int
    var notes: String
    var scenario: PlannerScenario?

    var grade: CourseGrade {
        get { CourseGrade(rawValue: gradeRaw) ?? .planned }
        set { gradeRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), sourceCourseID: UUID? = nil, courseCode: String,
         units: Decimal, grade: CourseGrade, isIncludedInGPA: Bool = true,
         isMajorCourse: Bool = false, isUpperDivision: Bool = false,
         confidence: Int = 2, notes: String = "", scenario: PlannerScenario? = nil) {
        self.id = id
        self.sourceCourseID = sourceCourseID
        self.courseCode = courseCode
        self.units = units
        self.gradeRaw = grade.rawValue
        self.isIncludedInGPA = isIncludedInGPA
        self.isMajorCourse = isMajorCourse
        self.isUpperDivision = isUpperDivision
        self.confidence = confidence
        self.notes = notes
        self.scenario = scenario
    }
}

@Model
final class GradeCategory {
    @Attribute(.unique) var id: UUID
    var name: String
    var weight: Decimal
    var earnedPoints: Decimal
    var possiblePoints: Decimal
    var dropLowestCount: Int
    var isExtraCredit: Bool
    var isMissing: Bool
    var assignmentCount: Int
    var notes: String
    var sortOrder: Int
    var plan: CourseGradePlan?

    init(id: UUID = UUID(), name: String, weight: Decimal, earnedPoints: Decimal = 0,
         possiblePoints: Decimal = 0, dropLowestCount: Int = 0, isExtraCredit: Bool = false,
         isMissing: Bool = false, assignmentCount: Int = 1, notes: String = "", sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.weight = weight
        self.earnedPoints = earnedPoints
        self.possiblePoints = possiblePoints
        self.dropLowestCount = dropLowestCount
        self.isExtraCredit = isExtraCredit
        self.isMissing = isMissing
        self.assignmentCount = assignmentCount
        self.notes = notes
        self.sortOrder = sortOrder
    }
}

@Model
final class CourseGradePlan {
    @Attribute(.unique) var id: UUID
    var courseName: String
    var gradingScaleData: Data
    var targetPercentage: Decimal
    var finalExamWeight: Decimal
    var notes: String
    var curveNote: String
    var syllabusNote: String

    @Relationship(deleteRule: .cascade, inverse: \GradeCategory.plan)
    var categories: [GradeCategory]

    init(id: UUID = UUID(), courseName: String, gradingScale: [String: Decimal] = ["A": 90, "B": 80, "C": 70, "D": 60],
         categories: [GradeCategory] = [], targetPercentage: Decimal = 90,
         finalExamWeight: Decimal = 20, notes: String = "", curveNote: String = "", syllabusNote: String = "") {
        self.id = id
        self.courseName = courseName
        self.gradingScaleData = (try? JSONEncoder().encode(gradingScale)) ?? Data()
        self.categories = categories
        self.targetPercentage = targetPercentage
        self.finalExamWeight = finalExamWeight
        self.notes = notes
        self.curveNote = curveNote
        self.syllabusNote = syllabusNote
    }

    var gradingScale: [String: Decimal] {
        get { (try? JSONDecoder().decode([String: Decimal].self, from: gradingScaleData)) ?? [:] }
        set { gradingScaleData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
}

@Model
final class UserPreferences {
    @Attribute(.unique) var id: UUID
    var displayName: String
    var major: String
    var targetGPA: Decimal
    var firstAcademicYear: String
    var decimalPrecision: Int
    var appearanceRaw: String
    var languageRaw: String = AppLanguage.system.rawValue
    var hapticsEnabled: Bool
    var privacyLockEnabled: Bool
    var privacyLockDelayRaw: String
    var showMajorGPA: Bool
    var showUpperDivisionGPA: Bool
    var showRepeatSummary: Bool
    var preferredAppIconRaw: String
    var defaultGradingBasisRaw: String
    var onboardingCompleted: Bool
    var demoDataLoaded: Bool

    var appearance: AppAppearance {
        get { AppAppearance(rawValue: appearanceRaw) ?? .system }
        set { appearanceRaw = newValue.rawValue }
    }
    var language: AppLanguage {
        get { AppLanguage(rawValue: languageRaw) ?? .system }
        set { languageRaw = newValue.rawValue }
    }
    var privacyLockDelay: PrivacyLockDelay {
        get { PrivacyLockDelay(rawValue: privacyLockDelayRaw) ?? .immediately }
        set { privacyLockDelayRaw = newValue.rawValue }
    }
    var preferredAppIcon: AppIconStyle {
        get { AppIconStyle(rawValue: preferredAppIconRaw) ?? .defaultStyle }
        set { preferredAppIconRaw = newValue.rawValue }
    }
    var defaultGradingBasis: GradingBasis {
        get { GradingBasis(rawValue: defaultGradingBasisRaw) ?? .letter }
        set { defaultGradingBasisRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), displayName: String = "", major: String = "Biological Sciences",
         targetGPA: Decimal = Decimal(35) / Decimal(10), firstAcademicYear: String = "2026–2027",
         decimalPrecision: Int = 3, appearance: AppAppearance = .system, language: AppLanguage = .system,
         hapticsEnabled: Bool = true, privacyLockEnabled: Bool = false,
         privacyLockDelay: PrivacyLockDelay = .immediately, showMajorGPA: Bool = true,
         showUpperDivisionGPA: Bool = true, showRepeatSummary: Bool = true,
         preferredAppIcon: AppIconStyle = .defaultStyle, defaultGradingBasis: GradingBasis = .letter,
         onboardingCompleted: Bool = false, demoDataLoaded: Bool = false) {
        self.id = id
        self.displayName = displayName
        self.major = major
        self.targetGPA = targetGPA
        self.firstAcademicYear = firstAcademicYear
        self.decimalPrecision = decimalPrecision
        self.appearanceRaw = appearance.rawValue
        self.languageRaw = language.rawValue
        self.hapticsEnabled = hapticsEnabled
        self.privacyLockEnabled = privacyLockEnabled
        self.privacyLockDelayRaw = privacyLockDelay.rawValue
        self.showMajorGPA = showMajorGPA
        self.showUpperDivisionGPA = showUpperDivisionGPA
        self.showRepeatSummary = showRepeatSummary
        self.preferredAppIconRaw = preferredAppIcon.rawValue
        self.defaultGradingBasisRaw = defaultGradingBasis.rawValue
        self.onboardingCompleted = onboardingCompleted
        self.demoDataLoaded = demoDataLoaded
    }
}

@Model
final class BackupSnapshot {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var fileName: String
    var reason: String
    var byteCount: Int

    init(id: UUID = UUID(), createdAt: Date = .now, fileName: String, reason: String, byteCount: Int) {
        self.id = id
        self.createdAt = createdAt
        self.fileName = fileName
        self.reason = reason
        self.byteCount = byteCount
    }
}
