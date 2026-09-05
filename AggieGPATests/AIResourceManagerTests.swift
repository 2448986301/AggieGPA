import Darwin.Mach
import XCTest
@testable import AggieGPA

final class AIResourceManagerTests: XCTestCase {
    func testPhase8DModelStoreIsOutsideBundleAndPinsAllThreeTiers() async {
        let snapshot = await AIModelStore.shared.snapshot()

        XCTAssertEqual(snapshot.records.count, 3)
        if let activeModelID = snapshot.activeModelID {
            XCTAssertTrue(snapshot.records.contains { $0.id == activeModelID && $0.state == .ready })
        }
        XCTAssertEqual(snapshot.recommendedTier, .efficient)
        XCTAssertEqual(snapshot.storageBudgetBytes, 10_000_000_000)
        XCTAssertTrue(snapshot.records.allSatisfy { !$0.localURL.path.contains(".app/") })
        XCTAssertTrue(snapshot.records.allSatisfy { $0.descriptor.artifactSHA256.count == 64 })
        XCTAssertEqual(snapshot.records.reduce(Int64(0)) { $0 + $1.descriptor.artifactBytes }, 9_359_489_760)
    }

    func testProductionSelectionRestrictsUnverifiedLargeModels() {
        let efficient = try! XCTUnwrap(AIModelStore.descriptors.first { $0.tier == .efficient })
        let balanced = try! XCTUnwrap(AIModelStore.descriptors.first { $0.tier == .balanced })
        let enhanced = try! XCTUnwrap(AIModelStore.descriptors.first { $0.tier == .enhanced })

        XCTAssertTrue(AIModelStore.isProductionSelectable(efficient))
        XCTAssertFalse(AIModelStore.isProductionSelectable(balanced))
        XCTAssertFalse(AIModelStore.isProductionSelectable(enhanced))
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

    func testProductionRuntimeBoundsLargeModelWorkingMemory() {
        let efficient = LlamaInferenceEngine.RuntimeConfiguration.production(for: .efficient)
        let balanced = LlamaInferenceEngine.RuntimeConfiguration.production(for: .balanced)
        let enhanced = LlamaInferenceEngine.RuntimeConfiguration.production(for: .enhanced)

        XCTAssertEqual(efficient.contextLength, 4_096)
        XCTAssertEqual(efficient.batchSize, 512)
        XCTAssertEqual(balanced.contextLength, 4_096)
        XCTAssertEqual(balanced.batchSize, 384)
        XCTAssertEqual(enhanced.contextLength, 3_072)
        XCTAssertEqual(enhanced.batchSize, 256)
        XCTAssertLessThanOrEqual(enhanced.microBatchSize, enhanced.batchSize)
        XCTAssertLessThan(enhanced.contextLength, 8_192)
        XCTAssertLessThan(enhanced.batchSize, 2_048)
    }

    func testResourceFallbackMessageDoesNotExposeMemoryEngineering() {
        let reasons: [AIResourceSelectionReason] = [
            .lowPowerMode,
            .thermalState,
            .chargingPreference,
            .memoryPressure,
        ]

        for reason in reasons {
            XCTAssertEqual(reason.messageKey, "Using a model better suited to this device.")
            XCTAssertFalse(reason.messageKey.localizedCaseInsensitiveContains("memory"))
            XCTAssertFalse(reason.messageKey.localizedCaseInsensitiveContains("KV"))
        }
    }

    func testModelDownloadRecordPersistsDurableProgressAndLegacyRecordsStillDecode() throws {
        let descriptor = try XCTUnwrap(AIModelStore.descriptors.first { $0.tier == .efficient })
        let record = AIModelRecord(
            descriptor: descriptor,
            state: .downloading,
            resumeData: Data([1, 2, 3]),
            receivedBytes: 123_456,
            expectedBytes: descriptor.artifactBytes,
            lastUsedAt: nil,
            verifiedAt: nil
        )
        XCTAssertEqual(record.downloadProgress?.receivedBytes, 123_456)
        XCTAssertEqual(record.downloadProgress?.expectedBytes, descriptor.artifactBytes)

        let encoded = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(AIModelRecord.self, from: encoded)
        XCTAssertEqual(decoded, record)

        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "receivedBytes")
        legacy.removeValue(forKey: "expectedBytes")
        let legacyData = try JSONSerialization.data(withJSONObject: legacy)
        let legacyRecord = try JSONDecoder().decode(AIModelRecord.self, from: legacyData)
        XCTAssertNil(legacyRecord.receivedBytes)
        XCTAssertNil(legacyRecord.expectedBytes)
        XCTAssertNil(legacyRecord.downloadProgress)
    }

    func testModelDownloadBackgroundSessionAndActivityProgressAreSafe() {
        XCTAssertEqual(
            ModelDownloadCoordinator.backgroundSessionIdentifier,
            "com.easonzhou.aggiegpa.model-download-v1"
        )
        let state = ModelDownloadActivityAttributes.ContentState(
            receivedBytes: 9_000,
            expectedBytes: 8_000,
            phase: .downloading
        )
        XCTAssertEqual(state.fraction, 1)
        XCTAssertEqual(
            ModelDownloadActivityAttributes.ContentState(
                receivedBytes: -1,
                expectedBytes: 0,
                phase: .paused
            ).fraction,
            0
        )
    }

    func testPhysical4BRepeatedLoadInferenceCancellationAndCleanup() async throws {
#if targetEnvironment(simulator)
        throw XCTSkip("The 4B stability probe requires a physical iPhone or iPad.")
#else
        guard ProcessInfo.processInfo.environment["AGGIE_RUN_4B_DEVICE_STABILITY"] == "1" else {
            throw XCTSkip("Set AGGIE_RUN_4B_DEVICE_STABILITY=1 for the explicit physical-device run.")
        }

        let storeSnapshot = await AIModelStore.shared.snapshot()
        let fourB = try XCTUnwrap(storeSnapshot.records.first { $0.descriptor.modelName == "Qwen3-4B" })
        XCTAssertEqual(fourB.descriptor.quantization, "Q4_K_M")
        XCTAssertEqual(fourB.state, .ready)
        XCTAssertEqual(storeSnapshot.activeModelID, fourB.id)

        let manager = AIResourceManager(idleUnloadDuration: .seconds(300))
        let baseline = currentPhysicalFootprintBytes()
        var observedPeaks: [UInt64] = []

        for iteration in 1...3 {
            let result = try await manager.generateJSON(
                prompt: "Return one compact JSON object with keys status and iteration. iteration=\(iteration)",
                maximumTokens: 96
            )
            XCTAssertEqual(result.selection.model.id, fourB.id)
            XCTAssertFalse(result.generation.text.isEmpty)
            if let peak = result.generation.peakObservedMemoryBytes { observedPeaks.append(peak) }
            print(
                "AGGIE_4B_DEVICE_METRIC iteration=\(iteration) "
                + "load_seconds=\(result.modelLoadSeconds) "
                + "inference_seconds=\(result.generation.totalSeconds) "
                + "generated_tokens=\(result.generation.generatedTokens) "
                + "peak_bytes=\(result.generation.peakObservedMemoryBytes ?? 0)"
            )

            await manager.cancelCurrentInference()
            try await Task.sleep(for: .milliseconds(750))
            let afterUnload = await manager.snapshot()
            XCTAssertNil(afterUnload.loadedModelID)
            XCTAssertEqual(afterUnload.activeLeaseCount, 0)
            print("AGGIE_4B_DEVICE_CLEANUP iteration=\(iteration) footprint_bytes=\(currentPhysicalFootprintBytes() ?? 0)")
        }

        let cancellationTask = Task {
            try await manager.generateJSON(
                prompt: String(repeating: "Analyze this grading policy carefully. Homework is 20 percent. ", count: 80),
                maximumTokens: 768
            )
        }
        try await Task.sleep(for: .milliseconds(800))
        await manager.cancelCurrentInference()
        do {
            _ = try await cancellationTask.value
            XCTFail("The in-flight 4B decode completed instead of honoring cancellation.")
        } catch is CancellationError {
            // Expected: leaving the AI screen and model switching use this path.
        } catch {
            XCTFail("Cancellation returned an unexpected error: \(error)")
        }

        let cancelledSnapshot = await manager.snapshot()
        XCTAssertNil(cancelledSnapshot.loadedModelID)
        XCTAssertEqual(cancelledSnapshot.activeLeaseCount, 0)
        let finalFootprint = currentPhysicalFootprintBytes()
        print(
            "AGGIE_4B_DEVICE_SUMMARY baseline_bytes=\(baseline ?? 0) "
            + "peak_bytes=\(observedPeaks.max() ?? 0) "
            + "after_cancel_bytes=\(finalFootprint ?? 0)"
        )
#endif
    }

    func testPhysical4BLongSyllabusAndSemanticSearch() async throws {
#if targetEnvironment(simulator)
        throw XCTSkip("The long 4B syllabus probe requires a physical iPhone or iPad.")
#else
        guard ProcessInfo.processInfo.environment["AGGIE_RUN_4B_DEVICE_STABILITY"] == "1" else {
            throw XCTSkip("Set AGGIE_RUN_4B_DEVICE_STABILITY=1 for the explicit physical-device run.")
        }

        let pageText = """
        Homework is 20% of the course grade. The lowest two homework scores are dropped.
        Quizzes are 15%. Midterm exams are 30%. The final exam is 35%.
        Late homework is accepted for 48 hours with a 10% penalty per day.
        Attendance is required, and documented absences may be excused.
        The A threshold is 93%, A- is 90%, B+ is 87%, and B is 83%.
        """
        let document = SyllabusTextExtractor.Document(
            pages: (1...8).map { page in
                .init(number: page, text: String(repeating: pageText + "\n", count: 3), image: nil)
            },
            source: .pastedText
        )

        let semantic = SyllabusPolicySearchEngine.searchSemantic(
            query: "Can homework be submitted after the deadline?",
            in: document
        )
        XCTAssertEqual(semantic.status, .evidenceFound)
        XCTAssertFalse(semantic.matches.isEmpty)

        let manager = AIResourceManager(idleUnloadDuration: .seconds(300))
        let result = try await OpenSourceLocalProvider(resourceManager: manager).analyze(document: document) { phase in
            print("AGGIE_4B_LONG_SYLLABUS_PHASE \(String(describing: phase))")
        }
        XCTAssertEqual(result.modelName, "Qwen3-4B")
        XCTAssertGreaterThan(result.metrics.generatedTokens, 0)
        XCTAssertNotNil(result.metrics.peakObservedMemoryBytes)
        print(
            "AGGIE_4B_LONG_SYLLABUS total_seconds=\(result.metrics.totalAnalysisSeconds) "
            + "load_seconds=\(result.metrics.modelLoadSeconds) "
            + "peak_bytes=\(result.metrics.peakObservedMemoryBytes ?? 0) "
            + "thermal=\(result.metrics.thermalState)"
        )

        await manager.cancelCurrentInference()
        let finalSnapshot = await manager.snapshot()
        XCTAssertNil(finalSnapshot.loadedModelID)
        XCTAssertEqual(finalSnapshot.activeLeaseCount, 0)
#endif
    }
}

private nonisolated func currentPhysicalFootprintBytes() -> UInt64? {
    var information = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &information) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
        }
    }
    return result == KERN_SUCCESS ? UInt64(information.phys_footprint) : nil
}
