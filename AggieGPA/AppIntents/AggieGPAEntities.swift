import AppIntents
import Foundation

struct CourseEntity: AppEntity, Hashable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Course")
    static let defaultQuery = CourseEntityQuery()
    let id: String
    let code: String
    let title: String
    let termName: String
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(code)", subtitle: title.isEmpty ? "\(termName)" : "\(title) · \(termName)")
    }
}

struct AssignmentEntity: AppEntity, Hashable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Assignment")
    static let defaultQuery = AssignmentEntityQuery()
    let id: String
    let courseID: String
    let courseCode: String
    let title: String
    let dueDate: Date?
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)", subtitle: "\(courseCode)") }
}

struct ExamEntity: AppEntity, Hashable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Exam")
    static let defaultQuery = ExamEntityQuery()
    let id: String
    let courseID: String
    let courseCode: String
    let title: String
    let dueDate: Date?
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)", subtitle: "\(courseCode)") }
}

struct AcademicTermEntity: AppEntity, Hashable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Academic Term")
    static let defaultQuery = AcademicTermEntityQuery()
    let id: String
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct GradeScenarioEntity: AppEntity, Hashable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Grade Scenario")
    static let defaultQuery = GradeScenarioEntityQuery()
    let id: String
    let courseID: String
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct CourseEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [CourseEntity] { try await AppIntentDataService.shared.courses(ids: identifiers) }
    func entities(matching string: String) async throws -> [CourseEntity] { try await AppIntentDataService.shared.courses(matching: string) }
    func suggestedEntities() async throws -> [CourseEntity] { try await AppIntentDataService.shared.courses(ids: nil) }
}

struct AssignmentEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [AssignmentEntity] { try await AppIntentDataService.shared.assignments(ids: identifiers) }
    func entities(matching string: String) async throws -> [AssignmentEntity] { try await AppIntentDataService.shared.assignments(matching: string) }
    func suggestedEntities() async throws -> [AssignmentEntity] { try await AppIntentDataService.shared.upcomingAssignments(days: 7) }
}

struct ExamEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [ExamEntity] { try await AppIntentDataService.shared.exams(ids: identifiers) }
    func entities(matching string: String) async throws -> [ExamEntity] { try await AppIntentDataService.shared.exams(matching: string) }
    func suggestedEntities() async throws -> [ExamEntity] { try await AppIntentDataService.shared.upcomingExams(days: 14) }
}

struct AcademicTermEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [AcademicTermEntity] { try await AppIntentDataService.shared.terms(ids: identifiers, matching: nil) }
    func entities(matching string: String) async throws -> [AcademicTermEntity] { try await AppIntentDataService.shared.terms(ids: nil, matching: string) }
    func suggestedEntities() async throws -> [AcademicTermEntity] { try await AppIntentDataService.shared.terms(ids: nil, matching: nil) }
}

struct GradeScenarioEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [GradeScenarioEntity] { try await AppIntentDataService.shared.scenarios(ids: identifiers) }
    func suggestedEntities() async throws -> [GradeScenarioEntity] { try await AppIntentDataService.shared.scenarios(ids: nil) }
}
