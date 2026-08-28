import XCTest
@testable import AggieGPA

final class AIResourceManagerTests: XCTestCase {
    func testPhase8DModelStoreIsOutsideBundleAndPinsAllThreeTiers() async {
        let snapshot = await AIModelStore.shared.snapshot()

        XCTAssertEqual(snapshot.records.count, 3)
        if let activeModelID = snapshot.activeModelID {
            XCTAssertTrue(snapshot.records.contains { $0.id == activeModelID && $0.state == .ready })
        }
        XCTAssertEqual(snapshot.recommendedTier, .balanced)
        XCTAssertEqual(snapshot.storageBudgetBytes, 10_000_000_000)
        XCTAssertTrue(snapshot.records.allSatisfy { !$0.localURL.path.contains(".app/") })
        XCTAssertTrue(snapshot.records.allSatisfy { $0.descriptor.artifactSHA256.count == 64 })
        XCTAssertEqual(snapshot.records.reduce(Int64(0)) { $0 + $1.descriptor.artifactBytes }, 9_359_489_760)
    }

    func testPhase8DResourceManagerDoesNotLoadUntilInferenceIsRequested() async throws {
        let manager = AIResourceManager(idleUnloadDuration: .milliseconds(1))
        let initial = await manager.snapshot()
        XCTAssertNil(initial.loadedModelID)
        XCTAssertEqual(initial.activeLeaseCount, 0)

        do {
            _ = try await manager.generateJSON(prompt: "{}", maximumTokens: 8)
            XCTFail("A missing active model must not trigger an implicit download or load.")
        } catch let error as AIModelStoreError {
            XCTAssertEqual(error, .modelNotInstalled)
        } catch let error as ProviderError {
            XCTAssertTrue(error.localizedDescription.contains("runtime"))
        }

        let after = await manager.snapshot()
        XCTAssertNil(after.loadedModelID)
        XCTAssertEqual(after.activeLeaseCount, 0)
    }

    func testPhase8DNoAIProviderRemainsUsableWithoutAnyModel() async throws {
        let document = SyllabusTextExtractor.Document(
            pages: [.init(number: 1, text: "Homework: 20%\nFinal: 80%", image: nil)],
            source: .pastedText
        )
        let result = try await NoAIProvider().analyze(document: document) { _ in }
        XCTAssertEqual(result.providerName, "Local Rule Recognition")
        XCTAssertTrue(result.analysis.warnings.contains { $0.code == "localRules.reviewOnly" })
    }

    func testPhase8EProviderFactoryKeepsManualModeRuntimeNeutral() {
        let provider = AIProviderFactory.make(mode: .localRules)
        XCTAssertEqual(provider.providerName, "Local Rule Recognition")
        XCTAssertFalse(provider is OpenSourceLocalProvider)
    }

    func testPhase8EProviderFactoryExposesTheCompleteProviderTree() {
        XCTAssertTrue(AIProviderFactory.make(kind: .openSourceLocal) is OpenSourceLocalProvider)
        XCTAssertTrue(AIProviderFactory.make(kind: .appleFoundationModels) is AppleFoundationModelsProvider)
        XCTAssertTrue(AIProviderFactory.make(kind: .noAI) is NoAIProvider)
    }

    func testPhase8EResourceSnapshotReportsAvailableMemoryAndTierHeadroom() async {
        let manager = AIResourceManager(idleUnloadDuration: .milliseconds(1))
        let snapshot = await manager.snapshot()
        XCTAssertGreaterThanOrEqual(snapshot.availableMemoryBytes, 0)
        XCTAssertLessThan(
            AIResourceManager.requiredMemoryHeadroomBytes(for: .efficient),
            AIResourceManager.requiredMemoryHeadroomBytes(for: .balanced)
        )
        XCTAssertLessThan(
            AIResourceManager.requiredMemoryHeadroomBytes(for: .balanced),
            AIResourceManager.requiredMemoryHeadroomBytes(for: .enhanced)
        )
    }

    func testPhase8ECurrentThermalStopLeavesResourceManagerUnloaded() async {
        let manager = AIResourceManager(idleUnloadDuration: .milliseconds(1))
        await manager.handleThermalState(.critical)
        await manager.cancelCurrentInference()
        let snapshot = await manager.snapshot()
        XCTAssertNil(snapshot.loadedModelID)
        XCTAssertEqual(snapshot.activeLeaseCount, 0)
    }
}
