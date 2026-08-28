import XCTest
@testable import AggieGPA

@MainActor
final class SyllabusPolicySearchTests: XCTestCase {
    private let document = SyllabusTextExtractor.Document(
        pages: [
            .init(number: 2, text: "Homework is due Friday. Late homework may be submitted within 48 hours with a 10% penalty.", image: nil),
            .init(number: 8, text: "Attendance is required for all laboratory meetings.", image: nil)
        ],
        source: .pdf
    )

    func testEnglishPolicyQueryReturnsPageBackedEvidence() {
        let result = SyllabusPolicySearchEngine.search(query: "Can I submit homework late?", in: document)

        XCTAssertEqual(result.status, .evidenceFound)
        XCTAssertEqual(result.matches.first?.page, 2)
        XCTAssertTrue(result.matches.first?.sourceText.contains("48 hours") == true)
        XCTAssertGreaterThan(result.matches.first?.confidence ?? 0, 0)
    }

    func testSimplifiedChineseQueryUsesPolicySynonymsAndKeepsSourcePage() {
        let result = SyllabusPolicySearchEngine.search(query: "作业可以迟交吗？", in: document)

        XCTAssertEqual(result.status, .evidenceFound)
        XCTAssertEqual(result.matches.first?.page, 2)
    }

    func testNoEvidenceNeverProducesAnAnswer() {
        let result = SyllabusPolicySearchEngine.search(query: "Can I retake the final exam?", in: document)

        XCTAssertEqual(result.status, .noMatchingEvidence)
        XCTAssertTrue(result.matches.isEmpty)
    }

    func testManualFallbackOnlyUsesRetrievedEvidence() {
        let result = SyllabusPolicySearchEngine.search(query: "late homework", in: document)
        let explanation = SyllabusPolicyExplanation.manualFallback(query: result.query, evidence: result.matches)

        XCTAssertEqual(explanation.source, .manualEvidenceFallback)
        XCTAssertTrue(explanation.text.contains("48 hours"))
        XCTAssertFalse(explanation.text.contains("retake"))
    }

    func testSemanticSearchKeepsEvidencePageAndFallsBackSafely() {
        let result = SyllabusPolicySearchEngine.searchSemantic(
            query: "Are late assignments accepted?",
            in: document
        )

        XCTAssertEqual(result.status, .evidenceFound)
        XCTAssertEqual(result.matches.first?.page, 2)
        XCTAssertTrue(result.retrievalMode == .sentenceEmbedding || result.retrievalMode == .lexicalFallback)
    }

    func testSemanticSearchDoesNotInventMissingPolicy() {
        let result = SyllabusPolicySearchEngine.searchSemantic(
            query: "Can I replace the final exam with extra credit?",
            in: document
        )

        XCTAssertEqual(result.status, .noMatchingEvidence)
        XCTAssertTrue(result.matches.isEmpty)
    }

    func testStoredSyllabusSourceRoundTripsWithPageEvidence() throws {
        let pages = SyllabusTextExtractor.Document(
            pages: [
                .init(number: 3, text: "The final exam is worth 40%.", image: nil),
                .init(number: 7, text: "The lowest quiz may be dropped.", image: nil),
            ],
            source: .pdf
        )

        let storedPages = SyllabusTextExtractor.storedPageData(from: pages)
        let storedText = SyllabusTextExtractor.storedText(from: pages)
        let restored = SyllabusTextExtractor.document(
            storedPageData: storedPages,
            fallbackText: storedText,
            source: .pdf
        )

        XCTAssertNotNil(storedPages)
        XCTAssertEqual(storedText?.contains("final exam"), true)
        XCTAssertEqual(restored?.pages.map(\.number), [3, 7])

        let result = SyllabusPolicySearchEngine.searchSemantic(
            query: "What percentage is the final?",
            in: try XCTUnwrap(restored)
        )
        XCTAssertEqual(result.status, .evidenceFound)
        XCTAssertEqual(result.matches.first?.page, 3)
        XCTAssertTrue(result.matches.first?.sourceText.contains("40%") == true)
    }

    func testConfirmedSyllabusSourcePersistsForCourseScopedQuestions() throws {
        let policyID = UUID()
        defer { SyllabusSourceStore.remove(policyID: policyID) }
        let document = SyllabusTextExtractor.Document(
            pages: [
                .init(number: 4, text: "The final exam is worth 40%.", image: nil),
            ],
            source: .pdf
        )

        SyllabusSourceStore.save(document: document, for: policyID)
        let stored = try XCTUnwrap(SyllabusSourceStore.source(for: policyID))
        let restored = try XCTUnwrap(
            SyllabusTextExtractor.document(
                storedPageData: stored.pagesData,
                fallbackText: stored.sourceText,
                source: stored.source
            )
        )
        let result = SyllabusPolicySearchEngine.searchSemantic(
            query: "What percentage is the final?",
            in: restored
        )

        XCTAssertEqual(stored.policyID, policyID)
        XCTAssertEqual(result.status, .evidenceFound)
        XCTAssertEqual(result.matches.first?.page, 4)
        XCTAssertTrue(result.matches.first?.sourceText.contains("40%") == true)
    }

    func testPhase15PolicySearchPerformance() {
        let corpus = SyllabusTextExtractor.Document(
            pages: (1...120).map { page in
                .init(
                    number: page,
                    text: (0..<6).map { paragraph in
                        "Homework (paragraph) is due Friday. Late homework may be submitted within 48 hours with a 10% penalty."
                    }.joined(separator: "\n"),
                    image: nil
                )
            },
            source: .pdf
        )

        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]) {
            let result = SyllabusPolicySearchEngine.searchSemantic(
                query: "Are late assignments accepted?",
                in: corpus,
                limit: 5
            )
            XCTAssertEqual(result.searchedPageCount, 120)
            XCTAssertFalse(result.matches.isEmpty)
        }
    }
}
