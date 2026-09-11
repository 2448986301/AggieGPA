import XCTest
@testable import AggieGPA

@MainActor
final class InsightPriorityPerformanceTests: XCTestCase {
    @MainActor private struct Fixture {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var courses: [CourseRecord] = []
        var policies: [CourseGradingPolicy] = []
        var categories: [GradingCategory] = []
        var items: [GradeItem] = []
        var insights: [AcademicInsight] = []

        init() {
            for index in 0..<3 {
                let course = CourseRecord(courseCode: "TEST \(index)", units: 4, grade: .inProgress)
                let policy = CourseGradingPolicy(course: course, targetPercentage: [85, 95, 50][index])
                let category = GradingCategory(course: course, name: "Work", weight: 100)
                let graded = GradeItem(course: course, category: category, title: "Scored", earnedPoints: 80, possiblePoints: 100, status: .graded)
                let upcoming = GradeItem(course: course, category: category, title: "Remaining", dueDate: now.addingTimeInterval(7_200), possiblePoints: 100)
                courses.append(course)
                policies.append(policy)
                categories.append(category)
                items += [graded, upcoming]
                for number in 0..<8 {
                    insights.append(AcademicInsight(
                        id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index * 8 + number))!,
                        courseID: course.id, itemID: number.isMultiple(of: 2) ? upcoming.id : nil,
                        severity: AcademicInsightSeverity.allCases[number % 4], symbolName: "book",
                        title: "Insight \(index)-\(number)", detail: "Keep this content", calculationBasis: "Deterministic fixture"
                    ))
                }
            }
            insights.reverse()
        }

        func score(_ insight: AcademicInsight, at date: Date? = nil) -> Double {
            InsightPriorityEngine.score(insight, courses: courses, policies: policies,
                categories: categories, items: items, scales: [], forecasts: [], now: date ?? now)
        }

        func rank(at date: Date? = nil) -> [AcademicInsight] {
            InsightPriorityEngine.rank(insights, courses: courses, policies: policies,
                categories: categories, items: items, scales: [], forecasts: [], now: date ?? now)
        }

        // The previous production sorting algorithm, retained only as a test oracle.
        func comparatorBaseline(at date: Date? = nil) -> [AcademicInsight] {
            insights.sorted {
                let lhs = score($0, at: date), rhs = score($1, at: date)
                return lhs == rhs ? $0.id.uuidString < $1.id.uuidString : lhs > rhs
            }
        }
    }

    func testRankingPreservesScoresContentAndTieBreaks() {
        var fixture = Fixture()
        let missing = AcademicInsight(id: UUID(), courseID: UUID(), itemID: nil,
            severity: .urgent, symbolName: "book", title: "Unknown", detail: "", calculationBasis: "")
        fixture.insights += [missing, fixture.insights[0]]
        XCTAssertEqual(fixture.rank(), fixture.comparatorBaseline())
        XCTAssertEqual(fixture.score(missing), 0)
        XCTAssertEqual(fixture.rank().count, fixture.insights.count, "Do not coalesce duplicate insight IDs.")
    }

    func testRankingRefreshesAfterEditsAndTimeChanges() {
        let fixture = Fixture()
        let before = fixture.rank()
        fixture.policies[0].targetPercentage = 200
        fixture.courses[0].units = 8
        let later = fixture.now.addingTimeInterval(90_000)
        let after = fixture.rank(at: later)
        XCTAssertEqual(after, fixture.comparatorBaseline(at: later))
        XCTAssertNotEqual(after.map(\.id), before.map(\.id))
        XCTAssertEqual(fixture.courses[0].grade, .inProgress, "Ranking never records an official grade.")
    }

    func testPriorityWeightsRemainUnchanged() {
        let fixture = Fixture()
        let insight = AcademicInsight(id: UUID(), courseID: fixture.courses[0].id,
            itemID: fixture.items[1].id, severity: .informative, symbolName: "book",
            title: "Upcoming", detail: "", calculationBasis: "")
        // Severity 220 + units 48 + due soon 320 + impact 500 + target gap 25.
        XCTAssertEqual(fixture.score(insight), 1_113, accuracy: 0.0001)
        XCTAssertEqual(fixture.score(insight, at: fixture.now.addingTimeInterval(90_000)), 1_213, accuracy: 0.0001)
    }

    func testComparatorBaselinePerformance() {
        let fixture = Fixture()
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTClockMetric()], options: options) {
            XCTAssertEqual(fixture.comparatorBaseline().count, 24)
        }
    }

    func testPrecomputedRankingPerformance() {
        let fixture = Fixture()
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTClockMetric()], options: options) {
            XCTAssertEqual(fixture.rank().count, 24)
        }
    }
}
