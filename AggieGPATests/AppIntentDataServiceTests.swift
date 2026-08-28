import XCTest
import SwiftData
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

    @MainActor
    func testIntentServiceReadsTheSameContainerAsTheApp() async throws {
        let store = PersistentStoreService.makeContainer(inMemory: true).container
        let context = ModelContext(store)
        let term = AcademicTerm(academicYear: "2026–2027", termType: .fall, displayName: "Fall 2026")
        let course = CourseRecord(courseCode: "CHE 002A", courseTitle: "General Chemistry", units: 5, grade: .noGrade, term: term)
        let category = GradingCategory(course: course, name: "Homework", categoryType: .homework, weight: 100)
        let dueDate = Calendar.autoupdatingCurrent.date(byAdding: .day, value: 2, to: .now)!
        let assignment = GradeItem(course: course, category: category, title: "Homework 3", dueDate: dueDate, possiblePoints: 20, status: .upcoming)
        let access = SiriAccessSettings(isSiriAccessEnabled: true, allowAssignmentSummaries: true, allowDetailedScores: true, allowGPAResponses: true, allowCreatingDrafts: true)
        context.insert(term)
        context.insert(course)
        context.insert(category)
        context.insert(assignment)
        context.insert(access)
        try context.save()

        let service = AppIntentDataService(container: store)
        let courses = try await service.courses(matching: "CHE 2A")
        let assignments = try await service.upcomingAssignments(days: 7)

        XCTAssertEqual(courses.map(\.id), [course.id.uuidString])
        XCTAssertEqual(assignments.map(\.title), ["Homework 3"])
    }

    func testSiriAliasRoundTrip() {
        let id = UUID()
        SiriAliasStore.save("Chemistry, Chem 2A, 化学", for: id)
        XCTAssertEqual(Set(SiriAliasStore.aliases(for: id)), Set(["Chemistry", "Chem 2A", "化学"]))
    }

    func testSharedSnapshotUsesExactDayBoundaryAndSeparatesExams() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 23, hour: 15)))
        let start = calendar.startOfDay(for: now)
        let lastIncludedDate = try XCTUnwrap(calendar.date(byAdding: DateComponents(day: 6, hour: 23), to: start))
        let exactEnd = try XCTUnwrap(calendar.date(byAdding: .day, value: 7, to: start))
        let snapshot = SiriSharedSnapshotStore.Snapshot(
            isEnabled: true,
            allowsAssignmentSummaries: true,
            courses: [],
            assignments: [
                .init(id: "included-assignment", courseID: "course", courseCode: "CHE 002A", title: "Homework 3",
                      dueDate: lastIncludedDate, category: "Homework", status: "upcoming"),
                .init(id: "excluded-assignment", courseID: "course", courseCode: "CHE 002A", title: "Homework 4",
                      dueDate: exactEnd, category: "Homework", status: "upcoming"),
            ],
            exams: [
                .init(id: "included-exam", courseID: "course", courseCode: "CHE 002A", title: "Midterm 1",
                      dueDate: lastIncludedDate, examType: "Midterms", status: "upcoming"),
                .init(id: "excluded-exam", courseID: "course", courseCode: "CHE 002A", title: "Final Exam",
                      dueDate: exactEnd, examType: "Final Exam", status: "upcoming"),
            ]
        )

        let assignments = SiriSharedSnapshotStore.upcomingAssignments(in: snapshot, days: 7, now: now, calendar: calendar)
        let exams = SiriSharedSnapshotStore.upcomingExams(in: snapshot, days: 7, now: now, calendar: calendar)

        XCTAssertEqual(assignments?.map(\.id), ["included-assignment"])
        XCTAssertEqual(exams?.map(\.id), ["included-exam"])
    }

    func testSharedSnapshotRespectsAssignmentSummaryPermission() {
        let snapshot = SiriSharedSnapshotStore.Snapshot(
            isEnabled: true,
            allowsAssignmentSummaries: false,
            courses: [],
            assignments: [],
            exams: []
        )

        XCTAssertNil(SiriSharedSnapshotStore.upcomingAssignments(in: snapshot, days: 7, now: .now, calendar: .autoupdatingCurrent))
        XCTAssertNil(SiriSharedSnapshotStore.upcomingExams(in: snapshot, days: 14, now: .now, calendar: .autoupdatingCurrent))
    }
}
