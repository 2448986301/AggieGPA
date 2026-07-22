import XCTest
@testable import AggieGPA

final class AppIntentDataServiceTests: XCTestCase {
    func testCourseCodeNormalization() {
        XCTAssertEqual(AppIntentDataService.normalizeCourseCode("CHE 2A"), "CHE002A")
        XCTAssertEqual(AppIntentDataService.normalizeCourseCode("che002a"), "CHE002A")
        XCTAssertEqual(AppIntentDataService.normalizeCourseCode(" CHE-002A "), "CHE002A")
    }

    func testSiriDraftRoundTripDoesNotWriteModels() throws {
        UserDefaults.standard.removeObject(forKey: PendingSiriDraftStore.key)
        let payload = SiriDraftPayload(kind: .assignment, courseID: UUID().uuidString, title: "Homework 4",
                                       dueDate: .now, earnedPoints: nil, possiblePoints: nil)
        try PendingSiriDraftStore.save(payload)
        XCTAssertEqual(PendingSiriDraftStore.take(), payload)
        XCTAssertNil(PendingSiriDraftStore.take())
    }

    func testCalendarWeekUsesCalendarBoundaries() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 7, day: 22, hour: 23, minute: 30))!
        let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))!
        XCTAssertEqual(calendar.component(.day, from: nextDay), 23)
        XCTAssertEqual(calendar.component(.hour, from: nextDay), 0)
    }
}
