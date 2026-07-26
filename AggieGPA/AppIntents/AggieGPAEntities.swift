import AppIntents
import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

struct CourseEntity: IndexedEntity, Hashable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Course")
    static let defaultQuery = CourseEntityQuery()
    let id: String
    let code: String
    let title: String
    let termName: String
    let aliases: [String]
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(code)", subtitle: title.isEmpty ? "\(termName)" : "\(title) · \(termName)")
    }
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = code
        attributes.contentDescription = title.isEmpty ? termName : "\(title) · \(termName)"
        attributes.keywords = [code, title, termName, "Aggie GPA", "course", "class"] + aliases
        return attributes
    }
    var hideInSpotlight: Bool { false }
}

struct AssignmentEntity: IndexedEntity, Hashable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Assignment")
    static let defaultQuery = AssignmentEntityQuery()
    let id: String
    let courseID: String
    let courseCode: String
    let title: String
    let dueDate: Date?
    let category: String
    let status: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)", subtitle: "\(courseCode)") }
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = title
        attributes.contentDescription = "\(courseCode) · \(category)"
        attributes.keywords = [title, courseCode, category, status, "Aggie GPA", "assignment", "homework"]
        attributes.dueDate = dueDate
        return attributes
    }
    var hideInSpotlight: Bool { false }
}

struct ExamEntity: IndexedEntity, Hashable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Exam")
    static let defaultQuery = ExamEntityQuery()
    let id: String
    let courseID: String
    let courseCode: String
    let title: String
    let dueDate: Date?
    let examType: String
    let status: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)", subtitle: "\(courseCode)") }
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = title
        attributes.contentDescription = "\(courseCode) · \(examType)"
        attributes.keywords = [title, courseCode, examType, status, "Aggie GPA", "exam", "test"]
        attributes.dueDate = dueDate
        return attributes
    }
    var hideInSpotlight: Bool { false }
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

struct CourseEntityQuery: EntityStringQuery, IndexedEntityQuery {
    func entities(for identifiers: [String]) async throws -> [CourseEntity] {
        if let entities = SiriSharedSnapshotStore.courses(ids: identifiers) { return entities }
        return try await AppIntentDataService.shared.courses(ids: identifiers)
    }
    func entities(matching string: String) async throws -> [CourseEntity] {
        if let entities = SiriSharedSnapshotStore.courses(matching: string) { return entities }
        return try await AppIntentDataService.shared.courses(matching: string)
    }
    func suggestedEntities() async throws -> [CourseEntity] {
        if let entities = SiriSharedSnapshotStore.courses() { return entities }
        return try await AppIntentDataService.shared.courses(ids: nil)
    }
    func reindexEntities(for identifiers: [String], indexDescription: CSSearchableIndexDescription) async throws {
        try await SiriSpotlightIndex.index(try await entities(for: identifiers), domain: "course")
    }
    func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
        try await SiriSpotlightIndex.index(try await suggestedEntities(), domain: "course")
    }
}

struct AssignmentEntityQuery: EntityStringQuery, IndexedEntityQuery {
    func entities(for identifiers: [String]) async throws -> [AssignmentEntity] { try await AppIntentDataService.shared.assignments(ids: identifiers) }
    func entities(matching string: String) async throws -> [AssignmentEntity] { try await AppIntentDataService.shared.assignments(matching: string) }
    func suggestedEntities() async throws -> [AssignmentEntity] { try await AppIntentDataService.shared.upcomingAssignments(days: 7) }
    func reindexEntities(for identifiers: [String], indexDescription: CSSearchableIndexDescription) async throws {
        try await SiriSpotlightIndex.index(try await entities(for: identifiers), domain: "assignment")
    }
    func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
        try await SiriSpotlightIndex.index(try await suggestedEntities(), domain: "assignment")
    }
}

struct ExamEntityQuery: EntityStringQuery, IndexedEntityQuery {
    func entities(for identifiers: [String]) async throws -> [ExamEntity] { try await AppIntentDataService.shared.exams(ids: identifiers) }
    func entities(matching string: String) async throws -> [ExamEntity] { try await AppIntentDataService.shared.exams(matching: string) }
    func suggestedEntities() async throws -> [ExamEntity] { try await AppIntentDataService.shared.upcomingExams(days: 14) }
    func reindexEntities(for identifiers: [String], indexDescription: CSSearchableIndexDescription) async throws {
        try await SiriSpotlightIndex.index(try await entities(for: identifiers), domain: "exam")
    }
    func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
        try await SiriSpotlightIndex.index(try await suggestedEntities(), domain: "exam")
    }
}

enum SiriSpotlightIndex {
    static func index<Entity: IndexedEntity>(_ entities: [Entity], domain: String) async throws {
        // Build explicit Core Spotlight items from AppEntity values. This keeps
        // the item visible in Spotlight while preserving the related
        // AppEntity identifier that system OpenIntent resolution needs.
        let items = entities.map { entity in
            let item = CSSearchableItem(appEntity: entity, priority: 100)
            item.domainIdentifier = "com.easonzhou.aggiegpa.\(domain)"
            return item
        }
        try await CSSearchableIndex.default().indexSearchableItems(items)
    }

    static func rebuildAll() async throws {
        let index = CSSearchableIndex.default()

        // Remove entries created by the previous plain-CSSearchableItem
        // implementation before rebuilding the entity-associated index.
        try await index.deleteSearchableItems(withDomainIdentifiers: [
            "com.easonzhou.aggiegpa.course",
            "com.easonzhou.aggiegpa.assignment",
            "com.easonzhou.aggiegpa.exam",
        ])

        try await index.deleteAppEntities(ofType: CourseEntity.self)
        try await index.deleteAppEntities(ofType: AssignmentEntity.self)
        try await index.deleteAppEntities(ofType: ExamEntity.self)

        let description = CSSearchableIndexDescription()
        try await CourseEntityQuery().reindexAllEntities(indexDescription: description)
        try await AssignmentEntityQuery().reindexAllEntities(indexDescription: description)
        try await ExamEntityQuery().reindexAllEntities(indexDescription: description)
    }
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
