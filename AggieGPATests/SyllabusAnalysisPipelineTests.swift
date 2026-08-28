import XCTest
@testable import AggieGPA

final class SyllabusAnalysisPipelineTests: XCTestCase {
    func testRelevantSectionsKeepPageMarkersAndDropUnrelatedIntro() {
        let document = SyllabusTextExtractor.Document(
            pages: [
                .init(number: 1, text: "Course description\n\nWelcome to the course.", image: nil),
                .init(number: 2, text: "Grading\n\nHomework 20%, quizzes 10%, and final exam 40%.", image: nil)
            ],
            source: .pastedText
        )

        let chunks = SyllabusAnalysisPipeline.chunks(from: document, maximumCharacters: 1_000)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertTrue(chunks[0].text.contains("[PAGE 2]"))
        XCTAssertTrue(chunks[0].text.contains("Homework 20%"))
        XCTAssertFalse(chunks[0].text.contains("Welcome to the course"))
    }

    func testLongSectionsAreBoundedAndRetainTheirSourcePage() {
        let body = String(repeating: "Homework points and grading policy. ", count: 120)
        let document = SyllabusTextExtractor.Document(
            pages: [.init(number: 7, text: body, image: nil)],
            source: .pdf
        )

        let chunks = SyllabusAnalysisPipeline.chunks(from: document, maximumCharacters: 512)
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertTrue(chunks.allSatisfy { $0.text.count <= 512 })
        XCTAssertTrue(chunks.allSatisfy { $0.pages == [7] && $0.text.contains("[PAGE 7]") })
    }

    func testUnknownHeadingsFallBackToAllNativeText() {
        let document = SyllabusTextExtractor.Document(
            pages: [.init(number: 3, text: "This document uses an unusual heading.\n\nThe syllabus describes weekly work.", image: nil)],
            source: .pastedText
        )

        let sections = SyllabusAnalysisPipeline.relevantSections(from: document)
        XCTAssertEqual(sections.count, 2)
        XCTAssertTrue(SyllabusAnalysisPipeline.relevantText(from: document).contains("unusual heading"))
    }

    func testImageOnlyPagesProduceNoModelChunks() {
        let document = SyllabusTextExtractor.Document(
            pages: [.init(number: 1, text: nil, image: nil)],
            source: .camera
        )
        XCTAssertTrue(SyllabusAnalysisPipeline.chunks(from: document).isEmpty)
    }

    func testCompactRetryTextKeepsPageMarkerAndBoundedSource() {
        let source = "[PAGE 7]\n" + String(repeating: "Homework grading policy. ", count: 400)
        let compact = SyllabusAnalysisPipeline.compactRetryText(source, maximumCharacters: 900)

        XCTAssertLessThanOrEqual(compact.count, 900)
        XCTAssertTrue(compact.contains("[PAGE 7]"))
        XCTAssertTrue(compact.contains("shortened for retry"))
    }

    func testRecoveryOrderEndsInManualReviewInsteadOfSilentImport() {
        XCTAssertEqual(
            SyllabusAnalysisRecovery.orderedSteps,
            [.structuredRepair, .relevantSectionRetry, .smallerContextRetry, .partialExtraction, .manualReview]
        )
    }

    @MainActor func testImportDraftPreservesEvidencePageAndConfidence() {
        let evidence = GradingEvidence(sourceText: "Homework 20%", sourcePage: 4, confidence: 0.82)
        let analysis = GradingAnalysis(
            gradingMode: .weightedCategories,
            categories: [
                .init(
                    name: "Homework",
                    type: .homework,
                    weightPercent: 20,
                    totalPoints: nil,
                    dropLowestCount: nil,
                    bestCount: nil,
                    totalCount: nil,
                    isExtraCredit: false,
                    confidence: 0.82,
                    evidence: [evidence]
                )
            ],
            assignments: [],
            exams: [],
            gradingScale: [],
            totalWeight: 20,
            rules: [],
            warnings: [],
            confidence: 0.82,
            evidence: [evidence]
        )

        let draft = OnDeviceSyllabusParser.importDraft(from: analysis, source: .pdf)
        XCTAssertEqual(draft.categories.first?.evidence?.page, 4)
        XCTAssertEqual(draft.categories.first?.evidence?.confidence, 0.82)
    }
}
