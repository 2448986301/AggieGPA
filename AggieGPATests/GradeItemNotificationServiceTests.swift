import UserNotifications
import XCTest
@testable import AggieGPA

@MainActor
final class GradeItemNotificationServiceTests: XCTestCase {
    func testOneDayReminderUsesCalendarDate() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let due = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 9))!
        let item = snapshot(due: due, lead: .oneDay)
        XCTAssertEqual(GradeItemNotificationService.fireDate(for: item, calendar: calendar),
                       calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 9)))
    }

    func testCreateReplacesAnyExistingIdentifier() async throws {
        let center = FakeNotificationCenter()
        let item = snapshot(due: Date(timeIntervalSinceNow: 172_800), lead: .oneDay)
        try await GradeItemNotificationService.sync(item, center: center)
        XCTAssertEqual(center.removed, [item.notificationIdentifier])
        XCTAssertEqual(center.requests.count, 1)
    }

    func testUpdateDoesNotDuplicateRequest() async throws {
        let center = FakeNotificationCenter()
        let item = snapshot(due: Date(timeIntervalSinceNow: 172_800), lead: .oneDay)
        try await GradeItemNotificationService.sync(item, center: center)
        try await GradeItemNotificationService.sync(item, center: center)
        XCTAssertEqual(center.requests.count, 1)
        XCTAssertEqual(center.removeCount, 2)
    }

    func testDisabledReminderCancelsWithoutAdding() async throws {
        let center = FakeNotificationCenter()
        let item = snapshot(due: Date(timeIntervalSinceNow: 172_800), enabled: false)
        try await GradeItemNotificationService.sync(item, center: center)
        XCTAssertTrue(center.requests.isEmpty)
        XCTAssertEqual(center.removeCount, 1)
    }

    func testDeniedPermissionIsReportedWithoutScheduling() async throws {
        let center = FakeNotificationCenter(allowed: false)
        let allowed = try await center.requestAuthorization()
        XCTAssertFalse(allowed)
        XCTAssertTrue(center.requests.isEmpty)
    }

    private func snapshot(due: Date?, enabled: Bool = true, lead: ReminderLeadTime = .oneDay) -> GradeItemReminderSnapshot {
        GradeItemReminderSnapshot(id: UUID(), courseID: UUID(), courseCode: "CHE 002A", title: "Homework 1",
                                  dueDate: due, enabled: enabled, leadTime: lead, customDate: nil,
                                  notificationIdentifier: "grade-item-test")
    }
}

private final class FakeNotificationCenter: GradeItemNotificationCenter, @unchecked Sendable {
    private let lock = NSLock()
    private let allowed: Bool
    private var storage: [String: UNNotificationRequest] = [:]
    private(set) var removed: [String] = []
    private(set) var removeCount = 0
    var requests: [UNNotificationRequest] { lock.withLock { Array(storage.values) } }

    init(allowed: Bool = true) { self.allowed = allowed }
    func requestAuthorization() async throws -> Bool { allowed }
    func add(_ request: UNNotificationRequest) async throws { lock.withLock { storage[request.identifier] = request } }
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        lock.withLock {
            removed = identifiers; removeCount += 1
            identifiers.forEach { storage.removeValue(forKey: $0) }
        }
    }
}
