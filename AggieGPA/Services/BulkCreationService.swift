import Foundation
import SwiftData

struct BulkCreationConfiguration: Equatable, Sendable {
    var prefix: String
    var startNumber: Int
    var count: Int
    var intervalDays: Int
    var firstDueDate: Date
    var possiblePoints: Decimal
    var categoryName: String
    var categoryID: UUID?
    var reminderEnabled: Bool
    var reminderLeadTime: ReminderLeadTime
    var customReminderDate: Date?
}

struct BulkGradeItemDraft: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let dueDate: Date
    let categoryName: String
    let categoryID: UUID?
    let possiblePoints: Decimal
    let reminderEnabled: Bool
    let reminderLeadTime: ReminderLeadTime
    let customReminderDate: Date?
    var isIncluded: Bool = true
}

struct BulkCreationValidation: Equatable, Sendable {
    let duplicateTitleIDs: Set<UUID>
    let duplicateRecordIDs: Set<UUID>
    let duplicateDateCount: Int

    var hasBlockingDuplicates: Bool {
        !duplicateTitleIDs.isEmpty || !duplicateRecordIDs.isEmpty || duplicateDateCount > 0
    }
}

enum BulkCreationError: LocalizedError {
    case invalidConfiguration
    case duplicateItems
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "Enter a name, a positive count, and possible points greater than zero."
        case .duplicateItems: "Remove duplicate item names or dates before creating items."
        case .saveFailed: "The items could not be created. Your existing data was preserved."
        }
    }
}

@MainActor
enum BulkCreationService {
    static func preview(_ configuration: BulkCreationConfiguration) -> [BulkGradeItemDraft] {
        guard !configuration.prefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              configuration.count > 0, configuration.count <= 100,
              configuration.possiblePoints > 0 else { return [] }
        let interval = max(0, configuration.intervalDays)
        return (0..<configuration.count).map { offset in
            let dueDate = Calendar.autoupdatingCurrent.date(
                byAdding: .day, value: offset * interval, to: configuration.firstDueDate
            ) ?? configuration.firstDueDate
            return BulkGradeItemDraft(
                id: UUID(),
                title: configuration.prefix.trimmingCharacters(in: .whitespacesAndNewlines) + " " + String(configuration.startNumber + offset),
                dueDate: dueDate, categoryName: configuration.categoryName, categoryID: configuration.categoryID,
                possiblePoints: configuration.possiblePoints,
                reminderEnabled: configuration.reminderEnabled,
                reminderLeadTime: configuration.reminderLeadTime,
                customReminderDate: configuration.customReminderDate
            )
        }
    }

    static func validate(_ drafts: [BulkGradeItemDraft], existingItems: [GradeItem]) -> BulkCreationValidation {
        var duplicateTitleIDs = Set<UUID>()
        var duplicateRecordIDs = Set<UUID>()
        var titleOwners: [String: UUID] = [:]
        var dateOwners: [String: UUID] = [:]

        for item in existingItems where !item.isDeleted {
            titleOwners[item.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] = item.id
            if let dueDate = item.dueDate {
                dateOwners[dateKey(dueDate)] = item.id
            }
        }

        for draft in drafts where draft.isIncluded {
            let titleKey = draft.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if let previousID = titleOwners[titleKey] {
                duplicateTitleIDs.insert(draft.id)
                if existingItems.contains(where: { $0.id == previousID }) {
                    duplicateRecordIDs.insert(previousID)
                } else {
                    duplicateTitleIDs.insert(previousID)
                }
            }
            titleOwners[titleKey] = draft.id
        }

        var duplicateDates = Set<String>()
        for draft in drafts where draft.isIncluded {
            let key = dateKey(draft.dueDate)
            if dateOwners[key] != nil { duplicateDates.insert(key) }
            dateOwners[key] = draft.id
        }

        return BulkCreationValidation(
            duplicateTitleIDs: duplicateTitleIDs,
            duplicateRecordIDs: duplicateRecordIDs,
            duplicateDateCount: duplicateDates.count
        )
    }

    static func insert(
        _ drafts: [BulkGradeItemDraft], course: CourseRecord, categories: [GradingCategory],
        context: ModelContext
    ) throws -> [UUID] {
        let selected = drafts.filter(\.isIncluded)
        guard !selected.isEmpty else { throw BulkCreationError.invalidConfiguration }
        let existing = (try? context.fetch(FetchDescriptor<GradeItem>())) ?? []
        let validation = validate(selected, existingItems: existing.filter { $0.course?.id == course.id })
        guard !validation.hasBlockingDuplicates else { throw BulkCreationError.duplicateItems }

        let category = selected.first?.categoryID.flatMap { id in categories.first { $0.id == id } }
            ?? categories.first { $0.name.caseInsensitiveCompare(selected.first?.categoryName ?? "") == .orderedSame }
        var insertedIDs: [UUID] = []
        var insertedItems: [GradeItem] = []
        for draft in selected {
            let item = GradeItem(
                course: course, category: category, title: draft.title, dueDate: draft.dueDate,
                possiblePoints: draft.possiblePoints, reminderEnabled: draft.reminderEnabled,
                reminderLeadTime: draft.reminderLeadTime, customReminderDate: draft.customReminderDate
            )
            context.insert(item)
            insertedIDs.append(item.id)
            insertedItems.append(item)
        }
        do {
            try context.save()
            for item in insertedItems where item.reminderEnabled {
                Task { try? await GradeItemNotificationService.sync(GradeItemReminderSnapshot(item)) }
            }
            return insertedIDs
        } catch {
            context.rollback()
            throw BulkCreationError.saveFailed
        }
    }

    static func remove(
        ids: [UUID], course: CourseRecord, context: ModelContext
    ) throws {
        let items = try context.fetch(FetchDescriptor<GradeItem>())
            .filter { $0.course?.id == course.id && ids.contains($0.id) }
        let identifiers = items.map(\.notificationIdentifier)
        items.forEach(context.delete)
        do {
            try context.save()
            identifiers.forEach { GradeItemNotificationService.cancel(identifier: $0) }
        } catch {
            context.rollback()
            throw BulkCreationError.saveFailed
        }
    }

    private static func dateKey(_ date: Date) -> String {
        let day = Calendar.autoupdatingCurrent.startOfDay(for: date).timeIntervalSince1970
        return String(day)
    }
}
