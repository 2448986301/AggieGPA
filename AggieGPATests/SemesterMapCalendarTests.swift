import XCTest
@testable import AggieGPA

final class SemesterMapCalendarTests: XCTestCase {
    func testWeekStartsRemainLocalMidnightAcrossDaylightSavingTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        calendar.firstWeekday = 1
        let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: 12))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 3, day: 29, hour: 12))!

        let weeks = SemesterMapCalendar.weekStarts(
            termStart: start,
            termEnd: end,
            calendar: calendar
        )

        XCTAssertEqual(weeks.count, 5)
        XCTAssertTrue(weeks.allSatisfy { calendar.component(.hour, from: $0) == 0 })
        XCTAssertTrue(weeks.allSatisfy { calendar.component(.weekday, from: $0) == calendar.firstWeekday })
    }

    func testMissingSemesterDatesDoNotCreateAGuessedRange() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3_600)!

        let weeks = SemesterMapCalendar.weekStarts(
            termStart: nil,
            termEnd: nil,
            calendar: calendar
        )

        XCTAssertTrue(weeks.isEmpty)
    }
}
