import XCTest
@testable import AggieGPA

final class AcademicCalendarEngineTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        calendar.firstWeekday = 1
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func item(
        id: UUID = UUID(),
        title: String,
        due: Date,
        type: GradeCategoryType = .homework,
        weight: Decimal = 10,
        status: GradeItemStatus = .upcoming,
        completed: Bool = false
    ) -> AcademicCalendarItemSnapshot {
        AcademicCalendarItemSnapshot(
            id: id,
            courseID: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            courseCode: "CHE 002A",
            courseTitle: "General Chemistry",
            title: title,
            dueDate: due,
            categoryName: type == .finalExam ? "Final Exam" : "Homework",
            categoryType: type,
            assessmentWeight: weight,
            possiblePoints: 20,
            status: status,
            isCompleted: completed,
            courseColorIndex: 2
        )
    }

    func testMonthGridIsFullWeeksAndPreservesLocalMidnightAcrossDST() {
        let month = date(2026, 3, 15)
        let grid = AcademicCalendarEngine.monthGrid(for: month, calendar: calendar)

        XCTAssertTrue(grid.count == 35 || grid.count == 42)
        XCTAssertEqual(grid.count % 7, 0)
        XCTAssertEqual(calendar.component(.weekday, from: grid[0]), calendar.firstWeekday)
        XCTAssertTrue(grid.allSatisfy { calendar.component(.hour, from: $0) == 0 })
        XCTAssertTrue(grid.contains { calendar.isDate($0, inSameDayAs: date(2026, 3, 1)) })
        XCTAssertTrue(grid.contains { calendar.isDate($0, inSameDayAs: date(2026, 3, 31)) })
    }

    func testDaySummaryCountsExamsWeightAndSortsDeterministically() {
        let morning = item(title: "Homework 2", due: date(2026, 10, 16, 9), weight: 10)
        let exam = item(title: "Midterm 1", due: date(2026, 10, 16, 9), type: .midterm, weight: 30)
        let summary = AcademicCalendarEngine.daySummary(
            for: date(2026, 10, 16),
            items: [morning, exam],
            calendar: calendar
        )

        XCTAssertEqual(summary.itemCount, 2)
        XCTAssertEqual(summary.examCount, 1)
        XCTAssertEqual(summary.completedCount, 0)
        XCTAssertEqual(summary.assessmentWeight, 40)
        XCTAssertEqual(summary.items.map(\.title), ["Midterm 1", "Homework 2"])
        XCTAssertEqual(summary.loadLevel, .heavy)
    }

    func testDaySummaryExcludesDroppedExcusedAndNotCountedItems() {
        let valid = item(title: "Homework", due: date(2026, 10, 23), weight: 10)
        let dropped = item(title: "Dropped", due: date(2026, 10, 23), status: .dropped)
        let excused = item(title: "Excused", due: date(2026, 10, 23), status: .excused)
        let notCounted = item(title: "Not Counted", due: date(2026, 10, 23), status: .notCounted)

        let summary = AcademicCalendarEngine.daySummary(
            for: date(2026, 10, 23),
            items: [dropped, notCounted, valid, excused],
            calendar: calendar
        )

        XCTAssertEqual(summary.items.map(\.title), ["Homework"])
        XCTAssertEqual(summary.assessmentWeight, 10)
    }

    func testAssessmentWeightMatchesCategoryCalculationMode() {
        XCTAssertEqual(
            AcademicCalendarEngine.assessmentWeight(
                categoryWeight: 20,
                calculationMode: .equalItems,
                itemPossiblePoints: 20,
                itemMultiplier: 1,
                categoryPossiblePoints: 40,
                categoryMultiplierTotal: 2
            ),
            10
        )
        XCTAssertEqual(
            AcademicCalendarEngine.assessmentWeight(
                categoryWeight: 30,
                calculationMode: .totalPoints,
                itemPossiblePoints: 50,
                itemMultiplier: 1,
                categoryPossiblePoints: 100,
                categoryMultiplierTotal: 2
            ),
            15
        )
        XCTAssertEqual(
            AcademicCalendarEngine.assessmentWeight(
                categoryWeight: 30,
                calculationMode: .custom,
                itemPossiblePoints: 50,
                itemMultiplier: 1,
                categoryPossiblePoints: 100,
                categoryMultiplierTotal: 2
            ),
            0
        )
    }

    func testBusiestDayUsesCountThenExamThenWeightAndStableColor() {
        let two = AcademicCalendarEngine.daySummary(
            for: date(2026, 10, 2),
            items: [
                item(title: "A", due: date(2026, 10, 2), weight: 5),
                item(title: "B", due: date(2026, 10, 2), weight: 5),
            ],
            calendar: calendar
        )
        let exam = AcademicCalendarEngine.daySummary(
            for: date(2026, 10, 3),
            items: [item(title: "Exam", due: date(2026, 10, 3), type: .midterm, weight: 30)],
            calendar: calendar
        )

        XCTAssertEqual(AcademicCalendarEngine.busiestDay(in: [exam, two])?.date, two.date)
        let seed = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        XCTAssertEqual(
            AcademicCalendarEngine.stableColorIndex(seed: seed, paletteCount: 6),
            AcademicCalendarEngine.stableColorIndex(seed: seed, paletteCount: 6)
        )
    }

    func testMakeItemSnapshotsPrecomputesCategoryWeightsInOnePass() {
        let courseID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let categoryID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let courses = [AcademicCalendarCourseInput(
            id: courseID, courseCode: "CHE 002A", courseTitle: "General Chemistry", courseColorIndex: 2
        )]
        let categories = [AcademicCalendarCategoryInput(
            id: categoryID, name: "Homework", categoryType: .homework, weight: 20, calculationMode: .totalPoints
        )]
        let items = [
            AcademicCalendarGradeItemInput(
                id: UUID(), courseID: courseID, categoryID: categoryID, title: "Homework 1",
                dueDate: date(2026, 9, 25), earnedPoints: 18, percentageOverride: nil,
                possiblePoints: 20, multiplier: 1, status: .graded, isIncluded: true,
                isDropped: false, isExcused: false, isDeleted: false, isExtraCredit: false
            ),
            AcademicCalendarGradeItemInput(
                id: UUID(), courseID: courseID, categoryID: categoryID, title: "Homework 2",
                dueDate: date(2026, 10, 2), earnedPoints: nil, percentageOverride: nil,
                possiblePoints: 30, multiplier: 1, status: .upcoming, isIncluded: true,
                isDropped: false, isExcused: false, isDeleted: false, isExtraCredit: false
            ),
        ]

        let snapshots = AcademicCalendarEngine.makeItemSnapshots(
            courses: courses, categories: categories, items: items, otherCategoryName: "Other"
        )

        XCTAssertEqual(snapshots.map(\.title), ["Homework 1", "Homework 2"])
        XCTAssertEqual(snapshots.map(\.assessmentWeight), [8, 12])
        XCTAssertTrue(snapshots[0].isCompleted)
        XCTAssertFalse(snapshots[1].isCompleted)
    }

    func testDaySummariesBucketsItemsWithoutChangingGridOrder() {
        let first = item(title: "First", due: date(2026, 10, 2), weight: 5)
        let second = item(title: "Second", due: date(2026, 10, 3), weight: 10)
        let dates = [date(2026, 10, 3), date(2026, 10, 2)]

        let summaries = AcademicCalendarEngine.daySummaries(
            for: dates, items: [first, second], calendar: calendar
        )

        XCTAssertEqual(summaries.map(\.date), dates.map { calendar.startOfDay(for: $0) })
        XCTAssertEqual(summaries[0].items.map(\.title), ["Second"])
        XCTAssertEqual(summaries[1].items.map(\.title), ["First"])
    }

    func testPhase15CalendarSnapshotPreparationPerformance() {
        let courseIDs = (0..<40).map { _ in UUID() }
        let categoryIDs = courseIDs.flatMap { _ in (0..<4).map { _ in UUID() } }
        let courses = courseIDs.enumerated().map { index, id in
            AcademicCalendarCourseInput(
                id: id,
                courseCode: "PERF (index)",
                courseTitle: "Performance Course (index)",
                courseColorIndex: index % 7
            )
        }
        let categories = categoryIDs.enumerated().map { index, id in
            AcademicCalendarCategoryInput(
                id: id,
                name: "Category (index % 4)",
                categoryType: .homework,
                weight: 25,
                calculationMode: .totalPoints
            )
        }
        let items = (0..<1_000).map { index in
            let courseIndex = index % courseIDs.count
            let categoryIndex = courseIndex * 4 + (index % 4)
            return AcademicCalendarGradeItemInput(
                id: UUID(),
                courseID: courseIDs[courseIndex],
                categoryID: categoryIDs[categoryIndex],
                title: "Item (index)",
                dueDate: date(2026, 10, 1).addingTimeInterval(TimeInterval(index % 28) * 86_400),
                earnedPoints: index.isMultiple(of: 3) ? 18 : nil,
                percentageOverride: nil,
                possiblePoints: 20,
                multiplier: 1,
                status: index.isMultiple(of: 3) ? .graded : .upcoming,
                isIncluded: true,
                isDropped: false,
                isExcused: false,
                isDeleted: false,
                isExtraCredit: false
            )
        }

        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]) {
            let snapshots = AcademicCalendarEngine.makeItemSnapshots(
                courses: courses,
                categories: categories,
                items: items,
                otherCategoryName: "Other"
            )
            let summaries = AcademicCalendarEngine.daySummaries(
                for: AcademicCalendarEngine.monthGrid(for: date(2026, 10, 1), calendar: calendar),
                items: snapshots,
                calendar: calendar
            )
            XCTAssertEqual(snapshots.count, items.count)
            XCTAssertFalse(summaries.isEmpty)
        }
    }
}
