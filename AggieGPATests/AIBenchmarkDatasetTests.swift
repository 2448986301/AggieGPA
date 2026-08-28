import Foundation
import XCTest
@testable import AggieGPA

final class AIBenchmarkDatasetTests: XCTestCase {
    func testDatasetCoversRequiredSyllabusAndQuickAddCases() {
        XCTAssertEqual(AIBenchmarkDataset.cases.count, 14)
        XCTAssertEqual(Set(AIBenchmarkDataset.cases.map(\.id)).count, AIBenchmarkDataset.cases.count)

        let requiredKinds = Set(AIBenchmarkCase.Kind.allCases)
        XCTAssertEqual(Set(AIBenchmarkDataset.cases.map(\.kind)), requiredKinds)
        XCTAssertTrue(AIBenchmarkDataset.cases.allSatisfy { !$0.input.isEmpty && !$0.requiredFacts.isEmpty })
        XCTAssertTrue(AIBenchmarkDataset.cases.contains { $0.language == "en" && $0.kind == .quickAdd })
        XCTAssertTrue(AIBenchmarkDataset.cases.contains { $0.language == "zh-Hans" && $0.kind == .quickAdd })
    }

    func testDatasetRevisionTwoUsesFixedMondayReferenceDate() throws {
        XCTAssertEqual(AIBenchmarkDataset.revision, 2)
        XCTAssertEqual(AIBenchmarkDataset.referenceDateISO8601, "2026-08-10")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = calendar.timeZone
        let referenceDate = try XCTUnwrap(
            formatter.date(from: AIBenchmarkDataset.referenceDateISO8601)
        )
        XCTAssertEqual(calendar.component(.weekday, from: referenceDate), 2, "The fixed reference date must remain a Monday.")
    }

    func testEnglishQuickAddDefinesAssignmentDueTimePointsAndReminder() throws {
        let benchmarkCase = try quickAddCase(language: "en")
        let expected = try XCTUnwrap(benchmarkCase.quickAddExpectation)

        XCTAssertEqual(benchmarkCase.input, "CHE Lab 4 Friday 11:59 PM, 20 points, remind me one day before.")
        assertAssignmentContract(expected, title: "Lab 4")
    }

    func testSimplifiedChineseQuickAddDefinesAssignmentDueTimePointsAndReminder() throws {
        let benchmarkCase = try quickAddCase(language: "zh-Hans")
        let expected = try XCTUnwrap(benchmarkCase.quickAddExpectation)

        XCTAssertEqual(benchmarkCase.input, "CHE实验4周五晚上11:59截止，20分，提前一天提醒。")
        assertAssignmentContract(expected, title: "实验4")
    }

    func testDatasetExpectationsNeverPermitInventedValues() {
        XCTAssertTrue(AIBenchmarkDataset.cases.allSatisfy { $0.forbiddenBehavior.contains("invent") })
    }

    private func quickAddCase(language: String) throws -> AIBenchmarkCase {
        try XCTUnwrap(
            AIBenchmarkDataset.cases.first { $0.kind == .quickAdd && $0.language == language }
        )
    }

    private func assertAssignmentContract(
        _ expected: AIBenchmarkQuickAddExpectation,
        title: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(expected.referenceDateISO8601, "2026-08-10", file: file, line: line)
        XCTAssertEqual(expected.courseCode, "CHE", file: file, line: line)
        XCTAssertEqual(expected.title, title, file: file, line: line)
        XCTAssertEqual(expected.type, "lab", file: file, line: line)
        XCTAssertEqual(expected.dueDateISO8601, "2026-08-14", file: file, line: line)
        XCTAssertEqual(expected.dueTime24Hour, "23:59", file: file, line: line)
        XCTAssertEqual(expected.points, 20, file: file, line: line)
        XCTAssertEqual(expected.category, "Labs", file: file, line: line)
        XCTAssertEqual(expected.reminderLeadTimeHours, 24, file: file, line: line)
        XCTAssertTrue(expected.requiredFacts.contains("dueTime=23:59"), file: file, line: line)
        XCTAssertTrue(expected.requiredFacts.contains("points=20"), file: file, line: line)
        XCTAssertTrue(expected.requiredFacts.contains("reminderLeadTimeHours=24"), file: file, line: line)
    }
}

nonisolated struct AIBenchmarkQuickAddExpectation: Sendable, Equatable {
    let referenceDateISO8601: String
    let courseCode: String
    let title: String
    let type: String
    let dueDateISO8601: String
    let dueTime24Hour: String
    let points: Decimal
    let category: String
    let reminderLeadTimeHours: Int

    var requiredFacts: [String] {
        [
            "courseCode=\(courseCode)",
            "title=\(title)",
            "type=\(type)",
            "dueDate=\(dueDateISO8601)",
            "dueTime=\(dueTime24Hour)",
            "points=\(NSDecimalNumber(decimal: points).stringValue)",
            "category=\(category)",
            "reminderLeadTimeHours=\(reminderLeadTimeHours)"
        ]
    }
}

nonisolated struct AIBenchmarkCase: Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case simpleWeighted, complexWeighted, points, mixed, dropLowest, bestNOfM
        case replacement, extraCredit, customScale, ambiguous, conflicting, longDocument
        case quickAdd
    }

    let id: String
    let kind: Kind
    let language: String
    let input: String
    let requiredFacts: [String]
    let forbiddenBehavior: String
    let quickAddExpectation: AIBenchmarkQuickAddExpectation?
}

nonisolated enum AIBenchmarkDataset {
    static let revision = 2
    static let referenceDateISO8601 = "2026-08-10"

    static let cases: [AIBenchmarkCase] = [
        sample("weighted-simple", .simpleWeighted, "Homework 20%; Midterms 45%; Final 35%.", ["weights total 100"]),
        sample("weighted-complex", .complexWeighted, "Labs 15%, weekly work 20%, midterm one 20%, midterm two 15%, project 10%, final 20%.", ["six distinct categories"]),
        sample("points", .points, "The course has 1,000 points: homework 200, labs 250, exams 550.", ["total points 1000"]),
        sample("mixed", .mixed, "Participation is 10%. Remaining work uses 900 points.", ["mixed method requires review"]),
        sample("drop-lowest", .dropLowest, "Quizzes are 20%; the lowest two of ten quizzes are dropped.", ["drop count 2", "total count 10"]),
        sample("best-n-of-m", .bestNOfM, "Only the best 4 of 5 midterms count toward the 50% exam category.", ["best 4 of 5"]),
        sample("replacement", .replacement, "If the final exam percentage is higher, it replaces the lower midterm percentage.", ["conditional replacement rule"]),
        sample("extra-credit", .extraCredit, "Up to 15 bonus points may be added after the 1,000 regular points; extra credit cannot reduce a grade.", ["extra credit separate from denominator"]),
        sample("custom-scale", .customScale, "A: 94, A-: 90, B+: 87, B: 84, B-: 80, C+: 77, C: 70, D: 60.", ["custom A threshold 94"]),
        sample("ambiguous", .ambiguous, "Participation matters. Exact grading weights will be announced later.", ["missing values stay nil", "manual review"]),
        sample("conflicting", .conflicting, "Page 2: homework is 15%. Page 8: homework is 20%.", ["conflict preserved", "both evidence pages"]),
        sample("long-document", .longDocument, String(repeating: "Course policy and schedule. ", count: 700) + "Final grading: homework 30%, projects 30%, final 40%.", ["late-page grading facts retained"]),
        quickAddSample(
            "quick-add-en",
            input: "CHE Lab 4 Friday 11:59 PM, 20 points, remind me one day before.",
            title: "Lab 4",
            language: "en"
        ),
        quickAddSample(
            "quick-add-zh",
            input: "CHE实验4周五晚上11:59截止，20分，提前一天提醒。",
            title: "实验4",
            language: "zh-Hans"
        )
    ]

    private static func sample(
        _ id: String, _ kind: AIBenchmarkCase.Kind, _ input: String,
        _ requiredFacts: [String], language: String = "en"
    ) -> AIBenchmarkCase {
        AIBenchmarkCase(
            id: id, kind: kind, language: language, input: input,
            requiredFacts: requiredFacts,
            forbiddenBehavior: "Do not invent missing values, rules, dates, courses, or scores.",
            quickAddExpectation: nil
        )
    }

    private static func quickAddSample(
        _ id: String,
        input: String,
        title: String,
        language: String
    ) -> AIBenchmarkCase {
        let expectation = AIBenchmarkQuickAddExpectation(
            referenceDateISO8601: referenceDateISO8601,
            courseCode: "CHE",
            title: title,
            type: "lab",
            dueDateISO8601: "2026-08-14",
            dueTime24Hour: "23:59",
            points: 20,
            category: "Labs",
            reminderLeadTimeHours: 24
        )
        return AIBenchmarkCase(
            id: id,
            kind: .quickAdd,
            language: language,
            input: input,
            requiredFacts: expectation.requiredFacts,
            forbiddenBehavior: "Do not invent missing values, rules, dates, courses, or scores.",
            quickAddExpectation: expectation
        )
    }
}
