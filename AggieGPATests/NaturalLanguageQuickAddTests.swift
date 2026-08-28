import XCTest
@testable import AggieGPA

final class NaturalLanguageQuickAddTests: XCTestCase {
    private let referenceDate = ISO8601DateFormatter().date(from: "2026-08-10T09:00:00Z")!

    func testEnglishAssignmentParsesIntoPreviewFields() {
        let draft = NaturalLanguageQuickAddParser.parse(
            "CHE Lab 4 Friday 11:59 PM, 20 points, remind me one day before.",
            referenceDate: referenceDate,
            availableCourseCodes: ["CHE 002A"]
        )

        XCTAssertEqual(draft.courseCode, "CHE 002A")
        XCTAssertEqual(draft.title, "Lab 4")
        XCTAssertEqual(draft.type, .lab)
        XCTAssertEqual(draft.possiblePoints, 20)
        XCTAssertEqual(draft.reminderLeadTimeHours, 24)
        XCTAssertTrue(draft.isReadyForConfirmation)
        XCTAssertEqual(Calendar.autoupdatingCurrent.component(.weekday, from: draft.dueDate!), 6)
        XCTAssertEqual(Calendar.autoupdatingCurrent.component(.hour, from: draft.dueDate!), 23)
    }

    func testSimplifiedChineseAssignmentParsesDateTimeAndReminder() {
        let draft = NaturalLanguageQuickAddParser.parse(
            "CHE实验4周五晚上11:59截止，20分，提前一天。",
            referenceDate: referenceDate,
            availableCourseCodes: ["CHE 002A"]
        )

        XCTAssertEqual(draft.courseCode, "CHE 002A")
        XCTAssertEqual(draft.title, "实验4")
        XCTAssertEqual(draft.type, .lab)
        XCTAssertEqual(draft.possiblePoints, 20)
        XCTAssertEqual(draft.reminderLeadTimeHours, 24)
        XCTAssertEqual(Calendar.autoupdatingCurrent.component(.weekday, from: draft.dueDate!), 6)
        XCTAssertEqual(Calendar.autoupdatingCurrent.component(.hour, from: draft.dueDate!), 23)
    }

    func testMissingFieldsRemainVisibleAndBlockConfirmation() {
        let draft = NaturalLanguageQuickAddParser.parse("CHE Lab 4", referenceDate: referenceDate, availableCourseCodes: ["CHE 002A"])

        XCTAssertFalse(draft.isReadyForConfirmation)
        XCTAssertTrue(draft.warnings.contains("A weekday or calendar date is required."))
        XCTAssertTrue(draft.warnings.contains("Possible points are missing."))
        XCTAssertTrue(draft.warnings.contains("Reminder timing is not set."))
    }

    func testModelPayloadUsesTheSamePreviewContract() throws {
        let payload = NaturalLanguageQuickAddPayload(
            courseCode: "CHE",
            title: "实验4",
            type: "lab",
            dueDate: "2026-08-14",
            dueTime: "23:59",
            points: 20,
            category: "Labs",
            reminderLeadTimeHours: 24,
            confidence: 0.92
        )

        let draft = try NaturalLanguageQuickAddParser.fromModelPayload(
            payload,
            referenceDate: referenceDate,
            availableCourseCodes: ["CHE 002A"]
        )

        XCTAssertEqual(draft.source, .localModel)
        XCTAssertEqual(draft.courseCode, "CHE 002A")
        XCTAssertEqual(draft.title, "实验4")
        XCTAssertEqual(draft.categoryName, "Labs")
        XCTAssertEqual(draft.possiblePoints, 20)
        XCTAssertTrue(draft.isReadyForConfirmation)
    }

    func testPhase15QuickAddParsingPerformance() {
        let availableCourseCodes = (0..<40).map { "PERF \($0)" }
        let english = "PERF 12 Lab 4 Friday 11:59 PM, 20 points, remind me one day before."
        let chinese = "PERF 12实验4周五晚上11:59截止，20分，提前一天。"

        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]) {
            let englishDraft = NaturalLanguageQuickAddParser.parse(
                english,
                referenceDate: referenceDate,
                availableCourseCodes: availableCourseCodes
            )
            let chineseDraft = NaturalLanguageQuickAddParser.parse(
                chinese,
                referenceDate: referenceDate,
                availableCourseCodes: availableCourseCodes
            )
            XCTAssertTrue(englishDraft.isReadyForConfirmation)
            XCTAssertTrue(chineseDraft.isReadyForConfirmation)
        }
    }
}
