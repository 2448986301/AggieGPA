import Foundation
import SwiftData

@MainActor
final class AppIntentDataService {
    static let shared = AppIntentDataService()
    private let containerResult: Result<ModelContainer, Error>
    private let usesSharedSnapshot: Bool

    private init() {
        containerResult = Result {
            try PersistentStoreService.makeAppIntentContainer()
        }
        usesSharedSnapshot = true
    }

    init(container: ModelContainer) {
        containerResult = .success(container)
        // An injected container is an isolated data source (for previews and tests), so a
        // persisted snapshot from another store must never shadow its records.
        usesSharedSnapshot = false
    }

    private var context: ModelContext {
        get throws { ModelContext(try containerResult.get()) }
    }

    func courses(ids: [String]?) throws -> [CourseEntity] {
        let context = try permittedContext()
        let courses = try context.fetch(FetchDescriptor<CourseRecord>())
        return courses.filter { ids == nil || ids!.contains($0.id.uuidString) }.map(Self.courseEntity)
    }

    func courses(matching query: String) throws -> [CourseEntity] {
        let candidates = try courses(ids: nil)
        let normalized = Self.normalizeCourseCode(query)
        return candidates.filter {
            Self.normalizeCourseCode($0.code) == normalized || $0.code.localizedCaseInsensitiveContains(query) ||
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.aliases.contains { $0.localizedCaseInsensitiveCompare(query) == .orderedSame || $0.localizedCaseInsensitiveContains(query) }
        }
    }

    func assignments(ids: [String]) throws -> [AssignmentEntity] { try assignmentSnapshots().filter { ids.contains($0.id) } }
    func assignments(matching query: String) throws -> [AssignmentEntity] {
        let normalized = Self.normalizeWorkTitle(query)
        return try assignmentSnapshots().filter {
            Self.normalizeWorkTitle($0.title).contains(normalized) || normalized.contains(Self.normalizeWorkTitle($0.title)) ||
            $0.courseCode.localizedCaseInsensitiveContains(query)
        }
    }
    func upcomingAssignments(days: Int, calendar: Calendar = .autoupdatingCurrent, now: Date = .now) throws -> [AssignmentEntity] {
        if usesSharedSnapshot,
           let sharedAssignments = SiriSharedSnapshotStore.upcomingAssignments(days: days, now: now, calendar: calendar) {
            return sharedAssignments
        }
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: days, to: start)!
        return try assignmentSnapshots().filter { item in item.dueDate.map { $0 >= start && $0 < end } ?? false }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    func exams(ids: [String]) throws -> [ExamEntity] { try examSnapshots().filter { ids.contains($0.id) } }
    func exams(matching query: String) throws -> [ExamEntity] {
        let normalized = Self.normalizeWorkTitle(query)
        return try examSnapshots().filter {
            Self.normalizeWorkTitle($0.title).contains(normalized) || normalized.contains(Self.normalizeWorkTitle($0.title)) ||
            $0.courseCode.localizedCaseInsensitiveContains(query)
        }
    }
    func upcomingExams(days: Int, calendar: Calendar = .autoupdatingCurrent, now: Date = .now) throws -> [ExamEntity] {
        if usesSharedSnapshot,
           let sharedExams = SiriSharedSnapshotStore.upcomingExams(days: days, now: now, calendar: calendar) {
            return sharedExams
        }
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: days, to: start)!
        return try examSnapshots().filter { item in item.dueDate.map { $0 >= start && $0 < end } ?? false }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    func terms(ids: [String]?, matching: String?) throws -> [AcademicTermEntity] {
        let context = try permittedContext()
        return try context.fetch(FetchDescriptor<AcademicTerm>()).filter {
            (ids == nil || ids!.contains($0.id.uuidString)) && (matching == nil || $0.displayName.localizedCaseInsensitiveContains(matching!))
        }.map { AcademicTermEntity(id: $0.id.uuidString, name: $0.displayName) }
    }

    func scenarios(ids: [String]?) throws -> [GradeScenarioEntity] {
        let context = try permittedContext()
        let courses = try context.fetch(FetchDescriptor<CourseRecord>())
        let liveCourseModelIDs = Set(courses.filter { !$0.isDeleted }.map(\.persistentModelID))
        return try context.fetch(FetchDescriptor<ForecastScenario>()).filter { ids == nil || ids!.contains($0.id.uuidString) }.compactMap {
            guard let course = $0.course, liveCourseModelIDs.contains(course.persistentModelID) else { return nil }
            return GradeScenarioEntity(id: $0.id.uuidString, courseID: course.id.uuidString, name: "\(course.courseCode): \($0.name)")
        }
    }

    func courseGrade(_ entity: CourseEntity) throws -> String {
        let context = try permittedContext(detailedScores: true)
        guard let id = UUID(uuidString: entity.id), let course = try context.fetch(FetchDescriptor<CourseRecord>()).first(where: { $0.id == id }) else { throw ServiceError.deletedEntity }
        let policies = try context.fetch(FetchDescriptor<CourseGradingPolicy>())
        let categories = try context.fetch(FetchDescriptor<GradingCategory>())
        let items = try context.fetch(FetchDescriptor<GradeItem>())
        let scales = try context.fetch(FetchDescriptor<GradeScale>())
        let forecasts = try context.fetch(FetchDescriptor<ForecastScenario>())
        let courseModelID = course.persistentModelID
        let input = CourseGradeSnapshotBuilder.makeInput(
            course: course, policy: policies.first { $0.course?.persistentModelID == courseModelID }, categories: categories, items: items,
            gradeScale: scales.first { $0.course?.persistentModelID == courseModelID }, forecast: forecasts.first { $0.course?.persistentModelID == courseModelID && $0.isSelectedForGPAForecast }
        )
        let result = CourseGradeCalculationEngine.calculate(input)
        let final = course.grade.isPending ? "Final report grade pending." : "Final grade: \(course.grade.rawValue)."
        let current = result.calculatedCurrentPercentage.map { "Current calculated grade: \(DecimalFormatters.compact($0))%." } ?? "No calculated current grade is available."
        let projected = result.projectedFinalPercentage.map { "Projected grade: \(DecimalFormatters.compact($0))%\(result.projectedLetterGrade.map { ", \($0.rawValue)" } ?? "")." } ?? "No projected grade is available."
        return "\(entity.code). \(final) \(current) \(projected) \(DecimalFormatters.compact(result.gradedWeight))% of course weight is graded."
    }

    func officialGPAOverview() throws -> String {
        let context = try permittedContext(gpa: true)
        let terms = try context.fetch(FetchDescriptor<AcademicTerm>())
        let includedTermModelIDs = Set(terms.filter { !$0.isDeleted && $0.isIncludedInCumulativeGPA }.map(\.persistentModelID))
        let courses = try context.fetch(FetchDescriptor<CourseRecord>()).filter {
            !$0.isDeleted && $0.term.map { includedTermModelIDs.contains($0.persistentModelID) } ?? false
        }
        let planningInputs = GPAPlanningEngine.makeInputs(
            courses: courses,
            policies: try context.fetch(FetchDescriptor<CourseGradingPolicy>()),
            categories: try context.fetch(FetchDescriptor<GradingCategory>()),
            items: try context.fetch(FetchDescriptor<GradeItem>()),
            scales: try context.fetch(FetchDescriptor<GradeScale>()),
            forecasts: try context.fetch(FetchDescriptor<ForecastScenario>())
        )
        let snapshot = GPAPlanningEngine.resolve(
            inputs: planningInputs,
            scenario: GPAPlanningScenarioInput(targetGPA: 0),
            fallbackTargetUnits: 12
        )
        let current = snapshot.current.gpa.map(DecimalFormatters.compact) ?? "—"
        let projected = snapshot.projected.gpa.map(DecimalFormatters.compact) ?? "—"
        if let final = snapshot.final?.gpa {
            return "Final GPA: \(DecimalFormatters.compact(final)). Current GPA: \(current). Projected GPA: \(projected). Final grades are complete."
        }
        return "Current GPA: \(current). Projected GPA: \(projected). Final grades available: \(snapshot.eligibleFinalGradeCount) of \(snapshot.eligibleCourseCount)."
    }

    func projectedGPAOverview(term: AcademicTermEntity? = nil) throws -> String {
        let context = try permittedContext(gpa: true)
        let courses = try context.fetch(FetchDescriptor<CourseRecord>()).filter { !$0.isDeleted }
        let policies = try context.fetch(FetchDescriptor<CourseGradingPolicy>())
        let categories = try context.fetch(FetchDescriptor<GradingCategory>())
        let items = try context.fetch(FetchDescriptor<GradeItem>())
        let scales = try context.fetch(FetchDescriptor<GradeScale>())
        let forecasts = try context.fetch(FetchDescriptor<ForecastScenario>())
        let scopedTermID = term.flatMap { UUID(uuidString: $0.id) }
        let scopedCourses = courses.filter { course in
            guard let scopedTermID else { return course.term.map { !$0.isDeleted && $0.isIncludedInCumulativeGPA } ?? false }
            return course.term?.id == scopedTermID
        }
        let planningInputs = GPAPlanningEngine.makeInputs(
            courses: scopedCourses,
            policies: policies,
            categories: categories,
            items: items,
            scales: scales,
            forecasts: forecasts
        )
        let snapshot = GPAPlanningEngine.resolve(
            inputs: planningInputs,
            scenario: GPAPlanningScenarioInput(targetGPA: 0),
            fallbackTargetUnits: 12
        )
        let scope = term?.name ?? "your included terms"
        return "Projected GPA for \(scope): \(snapshot.projected.gpa.map(DecimalFormatters.compact) ?? "—"). Final grades available: \(snapshot.eligibleFinalGradeCount) of \(snapshot.eligibleCourseCount)."
    }

    func quarterGPA(_ term: AcademicTermEntity) throws -> String {
        let context = try permittedContext(gpa: true)
        guard let id = UUID(uuidString: term.id), let record = try context.fetch(FetchDescriptor<AcademicTerm>()).first(where: { $0.id == id }) else { throw ServiceError.deletedEntity }
        let recordModelID = record.persistentModelID
        let termCourses = try context.fetch(FetchDescriptor<CourseRecord>()).filter {
            !$0.isDeleted && $0.term?.persistentModelID == recordModelID
        }
        let policies = try context.fetch(FetchDescriptor<CourseGradingPolicy>())
        let categories = try context.fetch(FetchDescriptor<GradingCategory>())
        let items = try context.fetch(FetchDescriptor<GradeItem>())
        let scales = try context.fetch(FetchDescriptor<GradeScale>())
        let forecasts = try context.fetch(FetchDescriptor<ForecastScenario>())
        let planningInputs = GPAPlanningEngine.makeInputs(
            courses: termCourses,
            policies: policies,
            categories: categories,
            items: items,
            scales: scales,
            forecasts: forecasts
        )
        let snapshot = GPAPlanningEngine.resolve(
            inputs: planningInputs,
            scenario: GPAPlanningScenarioInput(targetGPA: 0),
            fallbackTargetUnits: 12
        )
        if let final = snapshot.final?.gpa {
            return "\(record.displayName) Final GPA: \(DecimalFormatters.compact(final)). Final grades are complete."
        }
        return "\(record.displayName) Current GPA: \(snapshot.current.gpa.map(DecimalFormatters.compact) ?? "—"). Projected GPA: \(snapshot.projected.gpa.map(DecimalFormatters.compact) ?? "—"). Final grades available: \(snapshot.eligibleFinalGradeCount) of \(snapshot.eligibleCourseCount)."
    }

    func requiredFinal(course entity: CourseEntity, target: Decimal) throws -> String {
        let context = try permittedContext(detailedScores: true)
        guard let id = UUID(uuidString: entity.id), let course = try context.fetch(FetchDescriptor<CourseRecord>()).first(where: { $0.id == id }) else { throw ServiceError.deletedEntity }
        let policies = try context.fetch(FetchDescriptor<CourseGradingPolicy>())
        let categories = try context.fetch(FetchDescriptor<GradingCategory>())
        let items = try context.fetch(FetchDescriptor<GradeItem>())
        let scales = try context.fetch(FetchDescriptor<GradeScale>())
        let forecasts = try context.fetch(FetchDescriptor<ForecastScenario>())
        let courseModelID = course.persistentModelID
        let base = CourseGradeSnapshotBuilder.makeInput(course: course, policy: policies.first { $0.course?.persistentModelID == courseModelID }, categories: categories,
                                                        items: items, gradeScale: scales.first { $0.course?.persistentModelID == courseModelID },
                                                        forecast: forecasts.first { $0.course?.persistentModelID == courseModelID && $0.isSelectedForGPAForecast })
        let input = CourseGradeCalculationInput(gradingMethod: base.gradingMethod, normalizeCurrentGrade: base.normalizeCurrentGrade,
                                                missingItemPolicy: base.missingItemPolicy, missingPolicyConfirmed: base.missingPolicyConfirmed,
                                                categories: base.categories, unassignedItems: base.unassignedItems,
                                                gradeScale: base.gradeScale, targetPercentage: target, forecast: base.forecast)
        let result = CourseGradeCalculationEngine.calculate(input)
        if let final = result.finalExamNeeded { return "\(entity.code) needs \(DecimalFormatters.compact(final))% on the remaining final exam to reach \(DecimalFormatters.compact(target))%." }
        if let remaining = result.requiredRemainingAverage { return "\(entity.code) needs a \(DecimalFormatters.compact(remaining))% average across remaining work to reach \(DecimalFormatters.compact(target))%." }
        return "A reliable requirement cannot be calculated until the grading policy is complete."
    }

    func ensureDraftsAllowed() throws {
        guard try settings().allowCreatingDrafts else { throw ServiceError.draftsDisabled }
    }

    func settings() throws -> SiriAccessSettings {
        let context = try context
        guard let settings = try context.fetch(FetchDescriptor<SiriAccessSettings>()).first, settings.isSiriAccessEnabled else { throw ServiceError.siriDisabled }
        return settings
    }

    private func permittedContext(detailedScores: Bool = false, gpa: Bool = false) throws -> ModelContext {
        let context = try context
        guard let settings = try context.fetch(FetchDescriptor<SiriAccessSettings>()).first, settings.isSiriAccessEnabled else { throw ServiceError.siriDisabled }
        if detailedScores && !settings.allowDetailedScores { throw ServiceError.detailedScoresDisabled }
        if gpa && !settings.allowGPAResponses { throw ServiceError.gpaDisabled }
        return context
    }

    private func assignmentSnapshots() throws -> [AssignmentEntity] {
        let context = try permittedContext()
        guard try settings().allowAssignmentSummaries else { throw ServiceError.assignmentSummariesDisabled }
        return try context.fetch(FetchDescriptor<GradeItem>()).filter { !Self.isExam($0) && !$0.isExcused && !$0.isDropped }.compactMap(Self.assignmentEntity)
    }

    private func examSnapshots() throws -> [ExamEntity] {
        let context = try permittedContext()
        guard try settings().allowAssignmentSummaries else { throw ServiceError.assignmentSummariesDisabled }
        return try context.fetch(FetchDescriptor<GradeItem>()).filter(Self.isExam).compactMap(Self.examEntity)
    }

    private static func courseEntity(_ course: CourseRecord) -> CourseEntity {
        CourseEntity(id: course.id.uuidString, code: course.courseCode, title: course.courseTitle, termName: course.term?.displayName ?? "No term", aliases: SiriAliasStore.aliases(for: course.id))
    }
    private static func assignmentEntity(_ item: GradeItem) -> AssignmentEntity? {
        guard let course = item.course else { return nil }
        return AssignmentEntity(id: item.id.uuidString, courseID: course.id.uuidString, courseCode: course.courseCode, title: item.title, dueDate: item.dueDate, category: item.category?.name ?? "Assignment", status: item.status.rawValue)
    }
    private static func examEntity(_ item: GradeItem) -> ExamEntity? {
        guard let course = item.course else { return nil }
        return ExamEntity(id: item.id.uuidString, courseID: course.id.uuidString, courseCode: course.courseCode, title: item.title, dueDate: item.dueDate, examType: item.category?.name ?? "Exam", status: item.status.rawValue)
    }
    private static func isExam(_ item: GradeItem) -> Bool { item.category?.categoryType == .midterm || item.category?.categoryType == .finalExam }

    nonisolated static func normalizeCourseCode(_ value: String) -> String {
        let compact = value.uppercased().filter { $0.isLetter || $0.isNumber }
        guard let regex = try? NSRegularExpression(pattern: #"^([A-Z]+)(\d+)([A-Z]*)$"#),
              let match = regex.firstMatch(in: compact, range: NSRange(compact.startIndex..., in: compact)),
              let lettersRange = Range(match.range(at: 1), in: compact),
              let numberRange = Range(match.range(at: 2), in: compact),
              let suffixRange = Range(match.range(at: 3), in: compact) else { return compact }
        let number = String(compact[numberRange]); let padded = String(repeating: "0", count: max(0, 3 - number.count)) + number
        return String(compact[lettersRange]) + padded + String(compact[suffixRange])
    }

    nonisolated static func normalizeWorkTitle(_ value: String) -> String {
        let lowercased = value.lowercased()
            .replacingOccurrences(of: "homework", with: "hw")
            .replacingOccurrences(of: "作业", with: "hw")
            .replacingOccurrences(of: "midterm", with: "mid")
            .replacingOccurrences(of: "期中考试", with: "mid")
            .replacingOccurrences(of: "期中", with: "mid")
            .replacingOccurrences(of: "final exam", with: "final")
            .replacingOccurrences(of: "期末考试", with: "final")
        return lowercased.filter { $0.isLetter || $0.isNumber }
    }

    enum ServiceError: LocalizedError {
        case siriDisabled, assignmentSummariesDisabled, detailedScoresDisabled, gpaDisabled, draftsDisabled, deletedEntity
        var errorDescription: String? {
            switch self {
            case .siriDisabled: "Enable Siri Access in Aggie GPA Settings."
            case .assignmentSummariesDisabled: "Assignment summaries are disabled in Aggie GPA Settings."
            case .detailedScoresDisabled: "Detailed score responses are disabled in Aggie GPA Settings."
            case .gpaDisabled: "GPA responses are disabled in Aggie GPA Settings."
            case .draftsDisabled: "Creating drafts with Siri is disabled in Aggie GPA Settings."
            case .deletedEntity: "That item no longer exists in Aggie GPA."
            }
        }
    }
}
