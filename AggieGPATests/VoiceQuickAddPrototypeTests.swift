import XCTest
@testable import AggieGPA

final class VoiceQuickAddPrototypeTests: XCTestCase {
    private let referenceDate = ISO8601DateFormatter().date(from: "2026-08-10T09:00:00Z")!

    func testEnglishTranscriptUsesTheExistingPreviewContract() {
        let result = VoiceQuickAddPrototype.preview(
            transcript: "CHE Lab 4 Friday 11:59 PM, 20 points, remind me one day before.",
            referenceDate: referenceDate,
            availableCourseCodes: ["CHE 002A"]
        )

        XCTAssertEqual(result.draft.title, "Lab 4")
        XCTAssertEqual(result.draft.possiblePoints, 20)
        XCTAssertTrue(result.draft.isReadyForConfirmation)
        XCTAssertTrue(result.requiresConfirmation)
    }

    func testSimplifiedChineseTranscriptUsesTheSamePreviewContract() {
        let result = VoiceQuickAddPrototype.preview(
            transcript: "CHE实验4周五晚上11:59截止，20分，提前一天。",
            referenceDate: referenceDate,
            availableCourseCodes: ["CHE 002A"]
        )

        XCTAssertEqual(result.draft.title, "实验4")
        XCTAssertEqual(result.draft.type, .lab)
        XCTAssertEqual(result.draft.reminderLeadTimeHours, 24)
        XCTAssertTrue(result.draft.isReadyForConfirmation)
    }

    func testPrototypeNeverBypassesPreviewForIncompleteTranscript() {
        let result = VoiceQuickAddPrototype.preview(
            transcript: "CHE Lab 4",
            referenceDate: referenceDate,
            availableCourseCodes: ["CHE 002A"]
        )

        XCTAssertFalse(result.draft.isReadyForConfirmation)
        XCTAssertFalse(result.draft.warnings.isEmpty)
        XCTAssertTrue(result.requiresConfirmation)
    }
}
