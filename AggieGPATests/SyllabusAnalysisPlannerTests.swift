import XCTest
@testable import AggieGPA

final class SyllabusAnalysisPlannerTests: XCTestCase {
    func testSimpleDocumentUsesOneCompletePass() {
        let document = SyllabusTextExtractor.Document(
            pages: [.init(number: 1, text: "Grading\n\nHomework 20%.", image: nil)],
            source: .pastedText
        )

        let plan = SyllabusAnalysisPlanner.plan(for: document)
        XCTAssertEqual(plan.complexity, .simple)
        XCTAssertEqual(plan.passes, [.complete])
        XCTAssertEqual(plan.operationCount, 1)
    }

    func testComplexRulesUseStructureRulesAndConflictReconciliationPasses() {
        let text = """
        Grading

        Homework 20%, exams 50%, and projects 30%.

        Rules

        Drop the lowest two of ten assignments. The final may replace the midterm. Extra credit is separate.

        Scale

        A is 93%, A- is 90%, and B+ is 87%.
        """
        let document = SyllabusTextExtractor.Document(
            pages: [
                .init(number: 1, text: text, image: nil),
                .init(number: 2, text: String(repeating: "Assessment details and grading policy.\n\n", count: 20), image: nil)
            ],
            source: .pdf
        )

        let plan = SyllabusAnalysisPlanner.plan(for: document)
        XCTAssertEqual(plan.complexity, .complex)
        XCTAssertEqual(plan.passes, [.gradingStructure, .rulesAndExceptions, .conflictReconciliation])
        XCTAssertEqual(plan.operationCount, plan.chunks.count * 2 + 1)
    }
}
