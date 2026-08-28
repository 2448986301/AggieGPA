import AppIntents
import Foundation
import SwiftUI

nonisolated protocol PrivateAggieIntent: AppIntent {}

nonisolated struct GetUpcomingAssignmentsIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Upcoming Assignments"
    static let description = IntentDescription("Lists assignments due in the next seven calendar days when allowed in Aggie GPA Settings.")
    static let supportedModes: IntentModes = .background
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        SiriExecutionTrace.record("assignments-started")
        do {
            let items: [AssignmentEntity]
            if let sharedItems = SiriSharedSnapshotStore.upcomingAssignments(days: 7) {
                items = sharedItems
                SiriExecutionTrace.record("snapshot-read", itemCount: items.count)
            } else {
                SiriExecutionTrace.record("snapshot-unavailable")
                items = try await AppIntentDataService.shared.upcomingAssignments(days: 7)
                SiriExecutionTrace.record("database-read", itemCount: items.count)
            }
            let text = items.isEmpty ? "No assignments are due in the next seven days." : items.map { "\($0.courseCode) \($0.title)\($0.dueDate.map { ", \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "")" }.joined(separator: "; ")
            SiriExecutionTrace.record("assignments-completed", itemCount: items.count)
            return .result(dialog: IntentDialog(stringLiteral: text), view: UpcomingAssignmentsSnippetView(items: items))
        } catch {
            SiriExecutionTrace.record("assignments-failed")
            let text = "Aggie GPA could not read assignments: \(error.localizedDescription)"
            return .result(dialog: IntentDialog(stringLiteral: text), view: UpcomingAssignmentsSnippetView(message: text))
        }
    }
}

nonisolated struct UpcomingAssignmentsSnippetView: View {
    let items: [AssignmentEntity]
    let message: String?

    init(items: [AssignmentEntity]) {
        self.items = items
        message = nil
    }

    init(message: String) {
        items = []
        self.message = message
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Aggie GPA", systemImage: "checklist")
                .font(.headline)
            if let message {
                Text(message)
                    .foregroundStyle(.secondary)
            } else if items.isEmpty {
                Text("No assignments are due in the next seven days.")
            } else {
                Text("Due in the next seven days")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ForEach(items.prefix(3), id: \.id) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.body.weight(.semibold))
                        Text("\(item.courseCode) · \(item.dueDate?.formatted(date: .abbreviated, time: .shortened) ?? "No due date")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
    }
}

nonisolated struct GetUpcomingExamsIntent: PrivateAggieIntent {
    static let title: LocalizedStringResource = "Get Upcoming Exams"
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    func perform() async throws -> some IntentResult & ProvidesDialog {
        SiriExecutionTrace.record("exams-started")
        do {
            let items = try await AppIntentDataService.shared.upcomingExams(days: 14)
            let text = items.isEmpty ? "No upcoming exams were found." : items.map { "\($0.courseCode) \($0.title)\($0.dueDate.map { ", \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "")" }.joined(separator: "; ")
            SiriExecutionTrace.record("exams-completed", itemCount: items.count)
            return .result(dialog: IntentDialog(stringLiteral: text))
        } catch {
            SiriExecutionTrace.record("exams-failed")
            throw error
        }
    }
}

nonisolated struct GetCourseGradeIntent: PrivateAggieIntent {
    static let title: LocalizedStringResource = "Get Course Grade"
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    @Parameter(title: "Course", requestValueDialog: "Which course?") nonisolated(unsafe) var course: CourseEntity
    static var parameterSummary: some ParameterSummary { Summary("Get the grade for \(\.$course)") }
    func perform() async throws -> some IntentResult & ProvidesDialog {
        SiriExecutionTrace.record("course-grade-started")
        do {
            let text = try await AppIntentDataService.shared.courseGrade(course)
            SiriExecutionTrace.record("course-grade-completed")
            return .result(dialog: IntentDialog(stringLiteral: text))
        } catch {
            SiriExecutionTrace.record("course-grade-failed")
            throw error
        }
    }
}

nonisolated struct GetQuarterGPAIntent: PrivateAggieIntent {
    static let title: LocalizedStringResource = "Get Quarter GPA"
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    @Parameter(title: "Quarter") nonisolated(unsafe) var term: AcademicTermEntity
    static var parameterSummary: some ParameterSummary { Summary("Get official GPA for \(\.$term)") }
    func perform() async throws -> some IntentResult & ProvidesDialog {
        SiriExecutionTrace.record("quarter-gpa-started")
        do {
            let text = try await AppIntentDataService.shared.quarterGPA(term)
            SiriExecutionTrace.record("quarter-gpa-completed")
            return .result(dialog: IntentDialog(stringLiteral: text))
        } catch {
            SiriExecutionTrace.record("quarter-gpa-failed")
            throw error
        }
    }
}

nonisolated struct GetGPAOverviewIntent: PrivateAggieIntent {
    static let title: LocalizedStringResource = "Get GPA Overview"
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    func perform() async throws -> some IntentResult & ProvidesDialog {
        SiriExecutionTrace.record("gpa-overview-started")
        do {
            let text = try await AppIntentDataService.shared.officialGPAOverview()
            SiriExecutionTrace.record("gpa-overview-completed")
            return .result(dialog: IntentDialog(stringLiteral: text))
        } catch {
            SiriExecutionTrace.record("gpa-overview-failed")
            throw error
        }
    }
}

nonisolated struct GetProjectedGPAIntent: PrivateAggieIntent {
    static let title: LocalizedStringResource = "Get Projected GPA"
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    @Parameter(title: "Quarter", requestValueDialog: "Which quarter?") nonisolated(unsafe) var term: AcademicTermEntity?
    static var parameterSummary: some ParameterSummary { Summary("Get projected GPA\(\.$term)") }
    func perform() async throws -> some IntentResult & ProvidesDialog {
        SiriExecutionTrace.record("projected-gpa-started")
        do {
            let text = try await AppIntentDataService.shared.projectedGPAOverview(term: term)
            SiriExecutionTrace.record("projected-gpa-completed")
            return .result(dialog: IntentDialog(stringLiteral: text))
        } catch {
            SiriExecutionTrace.record("projected-gpa-failed")
            throw error
        }
    }
}

nonisolated struct CalculateRequiredFinalScoreIntent: PrivateAggieIntent {
    static let title: LocalizedStringResource = "Calculate Required Final Score"
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    @Parameter(title: "Course") nonisolated(unsafe) var course: CourseEntity
    @Parameter(title: "Target Percentage", inclusiveRange: (0, 100)) nonisolated(unsafe) var targetPercentage: Double
    static var parameterSummary: some ParameterSummary { Summary("Calculate what \(\.$course) needs for \(\.$targetPercentage) percent") }
    func perform() async throws -> some IntentResult & ProvidesDialog {
        SiriExecutionTrace.record("required-final-started")
        do {
            let text = try await AppIntentDataService.shared.requiredFinal(course: course, target: Decimal(targetPercentage))
            SiriExecutionTrace.record("required-final-completed")
            return .result(dialog: IntentDialog(stringLiteral: text))
        } catch {
            SiriExecutionTrace.record("required-final-failed")
            throw error
        }
    }
}

nonisolated enum SiriTargetGrade: String, AppEnum {
    case aMinus
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Target Grade" }
    static var caseDisplayRepresentations: [SiriTargetGrade: DisplayRepresentation] {
        [.aMinus: "A-minus"]
    }
    var percentage: Double { 90 }
}

nonisolated struct CalculateTargetLetterGradeIntent: PrivateAggieIntent {
    static let title: LocalizedStringResource = "Calculate Target Course Grade"
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    @Parameter(title: "Course", requestValueDialog: "Which course?") nonisolated(unsafe) var course: CourseEntity
    static var parameterSummary: some ParameterSummary { Summary("Calculate what \(\.$course) needs for an A-minus") }
    func perform() async throws -> some IntentResult & ProvidesDialog {
        SiriExecutionTrace.record("target-grade-started")
        do {
            let text = try await AppIntentDataService.shared.requiredFinal(course: course, target: Decimal(SiriTargetGrade.aMinus.percentage))
            SiriExecutionTrace.record("target-grade-completed")
            return .result(dialog: IntentDialog(stringLiteral: text))
        } catch {
            SiriExecutionTrace.record("target-grade-failed")
            throw error
        }
    }
}

nonisolated struct GetAttentionItemsIntent: PrivateAggieIntent {
    static let title: LocalizedStringResource = "Get Attention Items"
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    func perform() async throws -> some IntentResult & ProvidesDialog {
        SiriExecutionTrace.record("attention-items-started")
        do {
            let assignments = try await AppIntentDataService.shared.assignments(matching: "")
            let overdue = assignments.filter { ($0.dueDate ?? .distantFuture) < .now }
            SiriExecutionTrace.record("attention-items-completed", itemCount: overdue.count)
            return .result(dialog: IntentDialog(stringLiteral: overdue.isEmpty ? "No overdue assignments need attention." : "\(overdue.count) overdue assignments need attention."))
        } catch {
            SiriExecutionTrace.record("attention-items-failed")
            throw error
        }
    }
}

@AppIntent(schema: .system.open)
struct OpenCourseIntent: OpenIntent {
    var target: CourseEntity

    init() {
        target = CourseEntity(id: "", code: "", title: "", termName: "", aliases: [])
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        SiriExecutionTrace.record("schema-open-course-started")
        PendingSiriNavigationStore.save(.init(kind: .course, courseID: target.id))
        NotificationCenter.default.post(name: .openCourseFromSiri, object: target.id)
        SiriExecutionTrace.record("schema-open-course-completed")
        return .result(dialog: "Opening \(target.code) in Aggie GPA.")
    }
}

nonisolated struct OpenAssignmentIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Assignment"
    static let openAppWhenRun = true
    @Parameter(title: "Assignment") nonisolated(unsafe) var assignment: AssignmentEntity
    func perform() async throws -> some IntentResult & ProvidesDialog {
        SiriExecutionTrace.record("open-assignment-started")
        PendingSiriNavigationStore.save(.init(kind: .assignment, courseID: assignment.courseID, itemID: assignment.id))
        SiriExecutionTrace.record("open-assignment-completed")
        return .result(dialog: "Opening \(assignment.title) in Aggie GPA.")
    }
}

nonisolated struct OpenExamIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Exam"
    static let openAppWhenRun = true
    @Parameter(title: "Exam") nonisolated(unsafe) var exam: ExamEntity
    func perform() async throws -> some IntentResult & ProvidesDialog {
        SiriExecutionTrace.record("open-exam-started")
        PendingSiriNavigationStore.save(.init(kind: .exam, courseID: exam.courseID, itemID: exam.id))
        SiriExecutionTrace.record("open-exam-completed")
        return .result(dialog: "Opening \(exam.title) in Aggie GPA.")
    }
}

nonisolated struct OpenGPAForecastIntent: AppIntent {
    static let title: LocalizedStringResource = "Open GPA Forecast"
    static let openAppWhenRun = true
    func perform() async throws -> some IntentResult & ProvidesDialog {
        SiriExecutionTrace.record("open-gpa-forecast-started")
        PendingSiriNavigationStore.save(.init(kind: .gpaForecast, courseID: nil, itemID: nil))
        SiriExecutionTrace.record("open-gpa-forecast-completed")
        return .result(dialog: "Opening GPA forecast in Aggie GPA.")
    }
}

nonisolated struct OpenPlannerScenarioIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Grade Scenario"
    static let openAppWhenRun = true
    @Parameter(title: "Scenario") nonisolated(unsafe) var scenario: GradeScenarioEntity
    func perform() async throws -> some IntentResult {
        SiriExecutionTrace.record("open-scenario-started")
        UserDefaults.standard.set(scenario.courseID, forKey: "pendingOpenCourseID")
        SiriExecutionTrace.record("open-scenario-completed")
        return .result()
    }
}

nonisolated struct SiriDraftPayload: Codable, Equatable, Sendable, Identifiable {
    nonisolated enum Kind: String, Codable, Sendable { case assignment, exam, recordGrade }
    let kind: Kind; let courseID: String; let title: String; let dueDate: Date?; let earnedPoints: Double?; let possiblePoints: Double?
    var id: String { "\(kind.rawValue)-\(courseID)-\(title)" }
}

nonisolated enum PendingSiriDraftStore {
    static let key = "pendingSiriDraft"
    nonisolated static func save(_ payload: SiriDraftPayload) throws {
        UserDefaults.standard.set(try JSONEncoder().encode(payload), forKey: key)
    }
    nonisolated static func take() -> SiriDraftPayload? {
        guard let data = UserDefaults.standard.data(forKey: key), let payload = try? JSONDecoder().decode(SiriDraftPayload.self, from: data) else { return nil }
        UserDefaults.standard.removeObject(forKey: key); return payload
    }
}

nonisolated struct PendingSiriNavigation: Codable, Sendable {
    nonisolated enum Kind: String, Codable, Sendable { case course, assignment, exam, gpaForecast, search }
    let kind: Kind
    let courseID: String?
    let itemID: String?
    let query: String?

    init(kind: Kind, courseID: String? = nil, itemID: String? = nil, query: String? = nil) {
        self.kind = kind
        self.courseID = courseID
        self.itemID = itemID
        self.query = query
    }
}

nonisolated enum PendingSiriNavigationStore {
    private static let appGroupIdentifier = "group.com.easonzhou.aggiegpa"
    private static let key = "pendingSiriNavigation"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroupIdentifier) }

    static func save(_ navigation: PendingSiriNavigation) {
        defaults?.set(try? JSONEncoder().encode(navigation), forKey: key)
        defaults?.synchronize()
    }

    static func peek() -> PendingSiriNavigation? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(PendingSiriNavigation.self, from: data)
    }

    static func clear() {
        defaults?.removeObject(forKey: key)
    }

    static func take() -> PendingSiriNavigation? {
        guard let value = peek() else { return nil }
        clear()
        return value
    }
}

nonisolated struct CreateAssignmentDraftIntent: PrivateAggieIntent {
    static let title: LocalizedStringResource = "Create Assignment Draft"
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static let openAppWhenRun = true
    @Parameter(title: "Course") nonisolated(unsafe) var course: CourseEntity
    @Parameter(title: "Title") nonisolated(unsafe) var titleText: String
    @Parameter(title: "Due Date") nonisolated(unsafe) var dueDate: Date
    static var parameterSummary: some ParameterSummary { Summary("Draft \(\.$titleText) for \(\.$course) due \(\.$dueDate)") }
    func perform() async throws -> some IntentResult & ProvidesDialog {
        SiriExecutionTrace.record("create-assignment-draft-started")
        do {
            try await AppIntentDataService.shared.ensureDraftsAllowed()
            try PendingSiriDraftStore.save(.init(kind: .assignment, courseID: course.id, title: titleText, dueDate: dueDate, earnedPoints: nil, possiblePoints: nil))
            SiriExecutionTrace.record("create-assignment-draft-completed")
            return .result(dialog: "A draft is ready. Confirm it in Aggie GPA before it is saved.")
        } catch {
            SiriExecutionTrace.record("create-assignment-draft-failed")
            throw error
        }
    }
}

nonisolated struct CreateExamDraftIntent: PrivateAggieIntent {
    static let title: LocalizedStringResource = "Create Exam Draft"
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static let openAppWhenRun = true
    @Parameter(title: "Course") nonisolated(unsafe) var course: CourseEntity
    @Parameter(title: "Exam Name") nonisolated(unsafe) var titleText: String
    @Parameter(title: "Date") nonisolated(unsafe) var dueDate: Date
    func perform() async throws -> some IntentResult & ProvidesDialog {
        SiriExecutionTrace.record("create-exam-draft-started")
        do {
            try await AppIntentDataService.shared.ensureDraftsAllowed()
            try PendingSiriDraftStore.save(.init(kind: .exam, courseID: course.id, title: titleText, dueDate: dueDate, earnedPoints: nil, possiblePoints: nil))
            SiriExecutionTrace.record("create-exam-draft-completed")
            return .result(dialog: "An exam draft is ready for confirmation in Aggie GPA.")
        } catch {
            SiriExecutionTrace.record("create-exam-draft-failed")
            throw error
        }
    }
}

nonisolated struct RecordGradeDraftIntent: PrivateAggieIntent {
    static let title: LocalizedStringResource = "Record Grade Draft"
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static let openAppWhenRun = true
    @Parameter(title: "Assignment") nonisolated(unsafe) var assignment: AssignmentEntity
    @Parameter(title: "Earned Points") nonisolated(unsafe) var earnedPoints: Double
    @Parameter(title: "Possible Points") nonisolated(unsafe) var possiblePoints: Double
    func perform() async throws -> some IntentResult & ProvidesDialog {
        SiriExecutionTrace.record("record-grade-draft-started")
        do {
            try await AppIntentDataService.shared.ensureDraftsAllowed()
            try PendingSiriDraftStore.save(.init(kind: .recordGrade, courseID: assignment.courseID, title: assignment.title, dueDate: assignment.dueDate, earnedPoints: earnedPoints, possiblePoints: possiblePoints))
            SiriExecutionTrace.record("record-grade-draft-completed")
            return .result(dialog: "A grade-entry draft is ready. Confirm it in Aggie GPA before the score changes.")
        } catch {
            SiriExecutionTrace.record("record-grade-draft-failed")
            throw error
        }
    }
}

nonisolated struct AggieGPAAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetUpcomingAssignmentsIntent(),
            phrases: [
                "View assignments in \(.applicationName)",
                "What assignments are due this week in \(.applicationName)",
                "查看 \(.applicationName) 本周到期的作业",
                "问 \(.applicationName) 我这周有什么作业"
            ],
            shortTitle: "Upcoming Assignments",
            systemImageName: "checklist"
        )
        AppShortcut(
            intent: GetUpcomingExamsIntent(),
            phrases: [
                "What exams are coming up in \(.applicationName)",
                "Show upcoming exams in \(.applicationName)",
                "查看 \(.applicationName) 近期考试",
                "问 \(.applicationName) 最近有什么考试"
            ],
            shortTitle: "Upcoming Exams",
            systemImageName: "graduationcap"
        )
        AppShortcut(
            intent: GetCourseGradeIntent(),
            phrases: [
                "What is the current and projected grade for \(\.$course) in \(.applicationName)",
                "Show the grade for \(\.$course) in \(.applicationName)",
                "查看 \(.applicationName) 里 \(\.$course) 的当前和预测成绩",
                "查询 \(.applicationName) 的 \(\.$course) 课程成绩"
            ],
            shortTitle: "Current & Projected Grade",
            systemImageName: "percent"
        )
        AppShortcut(
            intent: GetProjectedGPAIntent(),
            phrases: [
                "What is my projected GPA in \(.applicationName)",
                "Show my projected GPA in \(.applicationName)",
                "查询 \(.applicationName) 的预测 GPA",
                "查看 \(.applicationName) 本学期预测 GPA"
            ],
            shortTitle: "Projected GPA",
            systemImageName: "chart.line.uptrend.xyaxis"
        )
        AppShortcut(
            intent: CalculateTargetLetterGradeIntent(),
            phrases: [
                "What does \(\.$course) need for an A-minus in \(.applicationName)",
                "Calculate an A-minus target for \(\.$course) in \(.applicationName)",
                "用 \(.applicationName) 计算 \(\.$course) 达到 A 减需要的成绩",
                "问 \(.applicationName) 的 \(\.$course) 达到 A 减还需要多少分"
            ],
            shortTitle: "A-minus Target",
            systemImageName: "target"
        )
        AppShortcut(
            intent: OpenCourseIntent(),
            phrases: [
                "Open \(\.$target) in \(.applicationName)",
                "Show \(\.$target) in \(.applicationName)",
                "在 \(.applicationName) 打开 \(\.$target)",
                "用 \(.applicationName) 查看 \(\.$target)"
            ],
            shortTitle: "Open Course",
            systemImageName: "book.closed"
        )
        AppShortcut(
            intent: CreateAssignmentDraftIntent(),
            phrases: [
                "Create an assignment draft for \(\.$course) in \(.applicationName)",
                "Draft an assignment for \(\.$course) in \(.applicationName)",
                "在 \(.applicationName) 为 \(\.$course) 创建作业草稿",
                "用 \(.applicationName) 给 \(\.$course) 添加作业草稿"
            ],
            shortTitle: "Assignment Draft",
            systemImageName: "plus"
        )
        AppShortcut(
            intent: CreateExamDraftIntent(),
            phrases: [
                "Create an exam draft for \(\.$course) in \(.applicationName)",
                "Draft an exam for \(\.$course) in \(.applicationName)",
                "在 \(.applicationName) 为 \(\.$course) 创建考试草稿",
                "用 \(.applicationName) 给 \(\.$course) 添加考试草稿"
            ],
            shortTitle: "Exam Draft",
            systemImageName: "calendar.badge.plus"
        )
        AppShortcut(
            intent: RecordGradeDraftIntent(),
            phrases: [
                "Record a score draft for \(\.$assignment) in \(.applicationName)",
                "Draft a score for \(\.$assignment) in \(.applicationName)",
                "在 \(.applicationName) 为 \(\.$assignment) 记录成绩草稿",
                "用 \(.applicationName) 给 \(\.$assignment) 添加分数草稿"
            ],
            shortTitle: "Score Draft",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: OpenGPAForecastIntent(),
            phrases: [
                "Open GPA forecast in \(.applicationName)",
                "Show GPA forecast in \(.applicationName)",
                "在 \(.applicationName) 打开 GPA 预测",
                "用 \(.applicationName) 查看 GPA 预测"
            ],
            shortTitle: "Open GPA Forecast",
            systemImageName: "chart.line.uptrend.xyaxis"
        )
    }
}
