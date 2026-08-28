import Foundation
import SwiftData
import UserNotifications

nonisolated struct GradeItemReminderSnapshot: Equatable, Sendable {
    let id: UUID
    let courseID: UUID
    let courseCode: String
    let title: String
    let dueDate: Date?
    let enabled: Bool
    let leadTime: ReminderLeadTime
    let customDate: Date?
    let notificationIdentifier: String

    init(id: UUID, courseID: UUID, courseCode: String, title: String, dueDate: Date?, enabled: Bool,
         leadTime: ReminderLeadTime, customDate: Date?, notificationIdentifier: String) {
        self.id = id; self.courseID = courseID; self.courseCode = courseCode; self.title = title
        self.dueDate = dueDate; self.enabled = enabled; self.leadTime = leadTime
        self.customDate = customDate; self.notificationIdentifier = notificationIdentifier
    }

    @MainActor init(_ item: GradeItem) {
        id = item.id
        if let course = item.course, !course.isDeleted {
            courseID = course.id
            courseCode = course.courseCode
        } else {
            courseID = UUID()
            courseCode = "Course"
        }
        title = item.title; dueDate = item.dueDate; enabled = item.reminderEnabled
        leadTime = item.reminderLeadTime; customDate = item.customReminderDate
        notificationIdentifier = item.notificationIdentifier
    }
}

protocol GradeItemNotificationCenter: Sendable {
    func requestAuthorization() async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
}

extension UNUserNotificationCenter: GradeItemNotificationCenter {
    func requestAuthorization() async throws -> Bool { try await requestAuthorization(options: [.alert, .badge, .sound]) }
}

@MainActor
enum GradeItemNotificationService {
    static func sync(
        _ item: GradeItemReminderSnapshot,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent,
        center: any GradeItemNotificationCenter = UNUserNotificationCenter.current()
    ) async throws {
        center.removePendingNotificationRequests(withIdentifiers: [item.notificationIdentifier])
        guard item.enabled, let fireDate = fireDate(for: item, calendar: calendar), fireDate > now else { return }

        let content = UNMutableNotificationContent()
        content.title = item.courseCode
        content.body = "\(item.title) is due soon."
        content.sound = .default
        content.userInfo = ["gradeItemID": item.id.uuidString, "courseID": item.courseID.uuidString]
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try await center.add(UNNotificationRequest(identifier: item.notificationIdentifier, content: content, trigger: trigger))
    }

    static func cancel(identifier: String, center: any GradeItemNotificationCenter = UNUserNotificationCenter.current()) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    static func fireDate(for item: GradeItemReminderSnapshot, calendar: Calendar) -> Date? {
        switch item.leadTime {
        case .custom: return item.customDate
        case .oneDay: return item.dueDate.flatMap { calendar.date(byAdding: .day, value: -1, to: $0) }
        case .threeDays: return item.dueDate.flatMap { calendar.date(byAdding: .day, value: -3, to: $0) }
        case .oneWeek: return item.dueDate.flatMap { calendar.date(byAdding: .day, value: -7, to: $0) }
        }
    }
}
