import AppIntents
import Foundation

nonisolated protocol PrivateAggieIntent: AppIntent {}
extension PrivateAggieIntent {
    nonisolated static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }
}

nonisolated struct GetUpcomingAssignmentsIntent: PrivateAggieIntent {
    static let title: LocalizedStringResource = "Get Upcoming Assignments"
    static let description = IntentDescription("Lists assignments due in the next seven calendar days when allowed in Aggie GPA Settings.")
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let items = try await AppIntentDataService.shared.upcomingAssignments(days: 7)
        let text = items.isEmpty ? "No assignments are due in the next seven days." : items.map { "\($0.courseCode) \($0.title)\($0.dueDate.map { ", \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "")" }.joined(separator: "; ")
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}

nonisolated struct GetUpcomingExamsIntent: PrivateAggieIntent {
    static let title: LocalizedStringResource = "Get Upcoming Exams"
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let items = try await AppIntentDataService.shared.upcomingExams(days: 14)
        let text = items.isEmpty ? "No upcoming exams were found." : items.map { "\($0.courseCode) \($0.title)\($0.dueDate.map { ", \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "")" }.joined(separator: "; ")
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}

nonisolated struct GetCourseGradeIntent: PrivateAggieIntent {
    static let title: LocalizedStringResource = "Get Course Grade"
    @Parameter(title: "Course", requestValueDialog: "Which course?") nonisolated(unsafe) var course: CourseEntity
    static var parameterSummary: some ParameterSummary { Summary("Get the grade for \(\.$course)") }
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: try await AppIntentDataService.shared.courseGrade(course)))
    }
}

nonisolated struct GetQuarterGPAIntent: PrivateAggieIntent {
    static let title: LocalizedStringResource = "Get Quarter GPA"
    @Parameter(title: "Quarter") nonisolated(unsafe) var term: AcademicTermEntity
    static var parameterSummary: some ParameterSummary { Summary("Get official GPA for \(\.$term)") }
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: try await AppIntentDataService.shared.quarterGPA(term)))
    }
}

nonisolated struct GetGPAOverviewIntent: PrivateAggieIntent {
    static let title: LocalizedStringResource = "Get GPA Overview"
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: try await AppIntentDataService.shared.officialGPAOverview()))
    }
}

nonisolated struct CalculateRequiredFinalScoreIntent: PrivateAggieIntent {
    static let title: LocalizedStringResource = "Calculate Required Final Score"
    @Parameter(title: "Course") nonisolated(unsafe) var course: CourseEntity
    @Parameter(title: "Target Percentage", inclusiveRange: (0, 100)) nonisolated(unsafe) var targetPercentage: Double
    static var parameterSummary: some ParameterSummary { Summary("Calculate what \(\.$course) needs for \(\.$targetPercentage) percent") }
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: try await AppIntentDataService.shared.requiredFinal(course: course, target: Decimal(targetPercentage))))
    }
}

nonisolated struct GetAttentionItemsIntent: PrivateAggieIntent {
    static let title: LocalizedStringResource = "Get Attention Items"
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let assignments = try await AppIntentDataService.shared.assignments(matching: "")
        let overdue = assignments.filter { ($0.dueDate ?? .distantFuture) < .now }
        return .result(dialog: IntentDialog(stringLiteral: overdue.isEmpty ? "No overdue assignments need attention." : "\(overdue.count) overdue assignments need attention."))
    }
}

nonisolated struct OpenCourseIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Course"
    static let openAppWhenRun = true
    @Parameter(title: "Course") nonisolated(unsafe) var course: CourseEntity
    func perform() async throws -> some IntentResult & ProvidesDialog {
        UserDefaults.standard.set(course.id, forKey: "pendingOpenCourseID")
        return .result(dialog: "Opening \(course.code) in Aggie GPA.")
    }
}

nonisolated struct OpenAssignmentIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Assignment"
    static let openAppWhenRun = true
    @Parameter(title: "Assignment") nonisolated(unsafe) var assignment: AssignmentEntity
    func perform() async throws -> some IntentResult { UserDefaults.standard.set(assignment.courseID, forKey: "pendingOpenCourseID"); return .result() }
}

nonisolated struct OpenExamIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Exam"
    static let openAppWhenRun = true
    @Parameter(title: "Exam") nonisolated(unsafe) var exam: ExamEntity
    func perform() async throws -> some IntentResult { UserDefaults.standard.set(exam.courseID, forKey: "pendingOpenCourseID"); return .result() }
}

nonisolated struct OpenPlannerScenarioIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Grade Scenario"
    static let openAppWhenRun = true
    @Parameter(title: "Scenario") nonisolated(unsafe) var scenario: GradeScenarioEntity
    func perform() async throws -> some IntentResult { UserDefaults.standard.set(scenario.courseID, forKey: "pendingOpenCourseID"); return .result() }
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

nonisolated struct CreateAssignmentDraftIntent: PrivateAggieIntent {
    static let title: LocalizedStringResource = "Create Assignment Draft"
    static let openAppWhenRun = true
    @Parameter(title: "Course") nonisolated(unsafe) var course: CourseEntity
    @Parameter(title: "Title") nonisolated(unsafe) var titleText: String
    @Parameter(title: "Due Date") nonisolated(unsafe) var dueDate: Date
    static var parameterSummary: some ParameterSummary { Summary("Draft \(\.$titleText) for \(\.$course) due \(\.$dueDate)") }
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await AppIntentDataService.shared.ensureDraftsAllowed()
        try PendingSiriDraftStore.save(.init(kind: .assignment, courseID: course.id, title: titleText, dueDate: dueDate, earnedPoints: nil, possiblePoints: nil))
        return .result(dialog: "A draft is ready. Confirm it in Aggie GPA before it is saved.")
    }
}

nonisolated struct CreateExamDraftIntent: PrivateAggieIntent {
    static let title: LocalizedStringResource = "Create Exam Draft"
    static let openAppWhenRun = true
    @Parameter(title: "Course") nonisolated(unsafe) var course: CourseEntity
    @Parameter(title: "Exam Name") nonisolated(unsafe) var titleText: String
    @Parameter(title: "Date") nonisolated(unsafe) var dueDate: Date
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await AppIntentDataService.shared.ensureDraftsAllowed()
        try PendingSiriDraftStore.save(.init(kind: .exam, courseID: course.id, title: titleText, dueDate: dueDate, earnedPoints: nil, possiblePoints: nil))
        return .result(dialog: "An exam draft is ready for confirmation in Aggie GPA.")
    }
}

nonisolated struct RecordGradeDraftIntent: PrivateAggieIntent {
    static let title: LocalizedStringResource = "Record Grade Draft"
    static let openAppWhenRun = true
    @Parameter(title: "Assignment") nonisolated(unsafe) var assignment: AssignmentEntity
    @Parameter(title: "Earned Points") nonisolated(unsafe) var earnedPoints: Double
    @Parameter(title: "Possible Points") nonisolated(unsafe) var possiblePoints: Double
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await AppIntentDataService.shared.ensureDraftsAllowed()
        try PendingSiriDraftStore.save(.init(kind: .recordGrade, courseID: assignment.courseID, title: assignment.title, dueDate: assignment.dueDate, earnedPoints: earnedPoints, possiblePoints: possiblePoints))
        return .result(dialog: "A grade-entry draft is ready. Confirm it in Aggie GPA before the score changes.")
    }
}

nonisolated struct AggieGPAAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: GetUpcomingAssignmentsIntent(), phrases: ["View assignments in \(.applicationName)", "查看 \(.applicationName) 本周作业"], shortTitle: "Upcoming Assignments", systemImageName: "checklist")
        AppShortcut(intent: GetUpcomingExamsIntent(), phrases: ["View upcoming exams in \(.applicationName)", "查看 \(.applicationName) 近期考试"], shortTitle: "Upcoming Exams", systemImageName: "graduationcap")
        AppShortcut(intent: GetCourseGradeIntent(), phrases: ["Get a course grade in \(.applicationName)", "查询 \(.applicationName) 课程成绩"], shortTitle: "Course Grade", systemImageName: "percent")
        AppShortcut(intent: GetGPAOverviewIntent(), phrases: ["Get my GPA from \(.applicationName)", "查询 \(.applicationName) 累计 GPA"], shortTitle: "GPA Overview", systemImageName: "chart.line.uptrend.xyaxis")
        AppShortcut(intent: CalculateRequiredFinalScoreIntent(), phrases: ["Calculate my final score in \(.applicationName)", "用 \(.applicationName) 计算期末所需成绩"], shortTitle: "Final Score Needed", systemImageName: "target")
        AppShortcut(intent: OpenCourseIntent(), phrases: ["Open a course in \(.applicationName)", "在 \(.applicationName) 打开课程"], shortTitle: "Open Course", systemImageName: "book")
        AppShortcut(intent: CreateAssignmentDraftIntent(), phrases: ["Draft an assignment in \(.applicationName)", "在 \(.applicationName) 添加作业草稿"], shortTitle: "Assignment Draft", systemImageName: "plus")
        AppShortcut(intent: CreateExamDraftIntent(), phrases: ["Draft an exam in \(.applicationName)", "在 \(.applicationName) 添加考试草稿"], shortTitle: "Exam Draft", systemImageName: "calendar.badge.plus")
    }
}
