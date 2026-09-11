import ImageIO
import UIKit
import XCTest
@testable import AggieGPA

final class SyllabusImageImportTests: XCTestCase {
    private var previousIdleTimerDisabled = false

    override func setUp() async throws {
        try await super.setUp()
        previousIdleTimerDisabled = await MainActor.run {
            let previous = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true
            return previous
        }
    }

    override func tearDown() async throws {
        let previous = previousIdleTimerDisabled
        await MainActor.run { UIApplication.shared.isIdleTimerDisabled = previous }
        try await super.tearDown()
    }
    func testVisionPromptIncludesTheActualSourcePage() {
        let prompt = OpenSourceLocalProvider.visionPrompt(pageNumber: 7)
        XCTAssertTrue(prompt.contains("syllabus page 7"))
        XCTAssertTrue(prompt.contains("\"categories\" array"))
    }

    func testVisionProgressIsStageScopedAndBounded() {
        XCTAssertEqual(SyllabusVisionProgress.readingImage(completedLayers: 16, totalLayers: 32).fraction, 0.5)
        XCTAssertEqual(SyllabusVisionProgress.readingImage(completedLayers: 40, totalLayers: 32).fraction, 1)
        XCTAssertEqual(SyllabusVisionProgress.readingImage(completedLayers: -1, totalLayers: 32).fraction, 0)
        XCTAssertNil(SyllabusVisionProgress.readingImage(completedLayers: 1, totalLayers: 0).fraction)
        XCTAssertNil(SyllabusVisionProgress.organizingResult.fraction)
    }

    func testImageDataIsBoundedAndKeptForVision() throws {
        let original = makeImage(width: 4_000, height: 2_000)
        let input = try XCTUnwrap(original.jpegData(compressionQuality: 1))

        let page = try SyllabusTextExtractor.readImageData(input, number: 7)

        XCTAssertEqual(page.number, 7)
        XCTAssertNil(page.text)
        XCTAssertNotNil(page.image)
        let visionData = try XCTUnwrap(page.imageData)
        XCTAssertEqual(visionData.prefix(2), Data([0xFF, 0xD8]))
        XCTAssertLessThanOrEqual(
            max(page.image?.width ?? 0, page.image?.height ?? 0),
            2_048
        )

        let source = try XCTUnwrap(CGImageSourceCreateWithData(visionData as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let width = try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? NSNumber).intValue
        let height = try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? NSNumber).intValue
        XCTAssertLessThanOrEqual(max(width, height), 2_048)
    }

    func testSelectedPhotoPagesPreserveOrderAndEveryVisionPayload() throws {
        let document = try SyllabusTextExtractor.read(images: [
            makeImage(width: 1_200, height: 800),
            makeImage(width: 800, height: 1_200),
            makeImage(width: 2_400, height: 1_600),
        ])

        XCTAssertEqual(document.source, .camera)
        XCTAssertEqual(document.pages.map(\.number), [1, 2, 3])
        XCTAssertEqual(document.pages.count, 3)
        XCTAssertTrue(document.pages.allSatisfy { $0.image != nil && $0.imageData?.isEmpty == false })
    }

    func testFileImportCreatesBoundedVisionPayload() throws {
        let imageData = try XCTUnwrap(makeImage(width: 2_400, height: 1_600).jpegData(compressionQuality: 0.95))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("aggie-syllabus-image-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        try imageData.write(to: url, options: .atomic)

        let document = try SyllabusTextExtractor.read(url: url)

        XCTAssertEqual(document.source, .image)
        let page = try XCTUnwrap(document.pages.first)
        XCTAssertNil(page.text)
        XCTAssertNotNil(page.image)
        XCTAssertFalse(try XCTUnwrap(page.imageData).isEmpty)
        XCTAssertLessThanOrEqual(max(page.image?.width ?? 0, page.image?.height ?? 0), 2_048)
    }

    func testLegacyImagePageInitializerAlsoCreatesVisionPayload() throws {
        let image = try XCTUnwrap(makeImage(width: 600, height: 400).cgImage)

        let page = SyllabusTextExtractor.Page(number: 1, text: nil, image: image)

        XCTAssertNotNil(page.imageData)
    }

    func testVisionFallbackReadsThePersistedImageBytes() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1_600, height: 900)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1_600, height: 900))
            let text = "Homework 20%\nFinal Exam 80%"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 72, weight: .semibold),
                .foregroundColor: UIColor.black
            ]
            text.draw(
                with: CGRect(x: 80, y: 180, width: 1_440, height: 300),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes,
                context: nil
            )
        }
        let data = try XCTUnwrap(image.jpegData(compressionQuality: 0.92))

        let recognized = SyllabusImageTextRecognizer.recognize(data: data)

        XCTAssertTrue(recognized.localizedCaseInsensitiveContains("Homework"))
        XCTAssertTrue(recognized.contains("20"))
        XCTAssertTrue(recognized.contains("80"))
    }

    func testProvisionedVisionBundleRunsMultimodalInference() async throws {
        print("VISION_SYNTHETIC_HEADROOM start=\(os_proc_available_memory())")
        let descriptor = OnDeviceAIVisionModelLibrary.descriptor
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: descriptor.modelURL.path),
              fileManager.fileExists(atPath: descriptor.projectorURL.path) else {
            throw XCTSkip("The pinned vision model bundle is not provisioned on this test device.")
        }

        _ = try await OnDeviceAIVisionModelLibrary.verifyReady()

        print("VISION_SYNTHETIC_HEADROOM verified=\(os_proc_available_memory())")

        let image = UIGraphicsImageRenderer(size: CGSize(width: 1_600, height: 900)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1_600, height: 900))
            let text = "Homework 20%\nFinal Exam 80%"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 72, weight: .semibold),
                .foregroundColor: UIColor.black
            ]
            text.draw(
                with: CGRect(x: 80, y: 180, width: 1_440, height: 300),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes,
                context: nil
            )
        }
        let imageData = try XCTUnwrap(image.jpegData(compressionQuality: 0.92))
        let manager = AIResourceManager(idleUnloadDuration: .seconds(90))
        let document = SyllabusTextExtractor.Document(
            pages: [try SyllabusTextExtractor.readImageData(imageData, number: 7)], source: .image
        )
        print("VISION_SYNTHETIC_HEADROOM rendered=\(os_proc_available_memory())")
        let result = try await OpenSourceLocalProvider(resourceManager: manager).analyze(document: document, progress: { _ in })
        print("AGGIE_VLM_OUTPUT \(String(decoding: try JSONEncoder().encode(result.analysis), as: UTF8.self))")
        let draft = await OnDeviceSyllabusParser.importDraft(from: result.analysis, source: .image)
        XCTAssertTrue(draft.categories.contains { $0.name.localizedCaseInsensitiveContains("Homework") && $0.weightPercent == 20 })
        XCTAssertTrue(draft.categories.contains { $0.name.localizedCaseInsensitiveContains("Final") && $0.weightPercent == 80 })
        XCTAssertTrue(draft.categories.allSatisfy { $0.evidence?.page == 7 })
        XCTAssertTrue(draft.rules.isEmpty)
        XCTAssertTrue(draft.gradeScale.isEmpty)
        XCTAssertTrue(draft.categories.allSatisfy { $0.totalPoints == nil })
        XCTAssertNotNil(result.metrics.peakObservedMemoryBytes)
        XCTAssertEqual(result.providerName, "llama.cpp")
        XCTAssertEqual(result.modelName, "Qwen2-VL 2B")
        XCTAssertTrue(result.recognizedSource?.hasContent == true)
        print(
            "AGGIE_VLM_INTEGRATION load_seconds=\(result.metrics.modelLoadSeconds) "
                + "total_seconds=\(result.metrics.totalAnalysisSeconds) "
                + "tokens=\(result.metrics.generatedTokens) "
                + "peak_bytes=\(result.metrics.peakObservedMemoryBytes ?? 0)"
        )

        let repeated = try await OpenSourceLocalProvider(resourceManager: manager)
            .analyze(document: document, progress: { _ in })
        XCTAssertEqual(repeated.providerName, "llama.cpp")
        XCTAssertTrue(repeated.analysis.categories.contains { $0.name.localizedCaseInsensitiveContains("Homework") && $0.weightPercent == 20 })
        XCTAssertTrue(repeated.analysis.categories.contains { $0.name.localizedCaseInsensitiveContains("Final") && $0.weightPercent == 80 })
        print("AGGIE_VLM_WARM_REPEAT load_seconds=\(repeated.metrics.modelLoadSeconds) total_seconds=\(repeated.metrics.totalAnalysisSeconds) peak_bytes=\(repeated.metrics.peakObservedMemoryBytes ?? 0)")

        await manager.unloadIfIdle()
        let snapshot = await manager.snapshot()
        XCTAssertNil(snapshot.loadedModelID)
        XCTAssertEqual(snapshot.activeLeaseCount, 0)
    }

    func testVisualSchemaKeepsMissingWeightsEmpty() throws {
        let page = try SyllabusVisualPage.decode(#"{"categories":[{"name":"Project","weightPercent":null,"totalPoints":null,"sourceText":"Project: to be announced"}]}"#)
        let analysis = page.analysis(pageNumber: 9)
        XCTAssertNil(analysis.categories.first?.weightPercent)
        XCTAssertNil(analysis.categories.first?.totalPoints)
        XCTAssertEqual(analysis.categories.first?.evidence.first?.sourcePage, 9)
        XCTAssertTrue(analysis.rules.isEmpty)
        XCTAssertTrue(analysis.assignments.isEmpty)
    }

    func testPhysicalVisionCancellationReleasesTheEngine() async throws {
#if targetEnvironment(simulator)
        throw XCTSkip("Cancellation during native image encoding is verified on physical devices.")
#else
        let descriptor = OnDeviceAIVisionModelLibrary.descriptor
        guard FileManager.default.fileExists(atPath: descriptor.modelURL.path),
              FileManager.default.fileExists(atPath: descriptor.projectorURL.path) else {
            throw XCTSkip("The existing visual bundle is not installed; this test never downloads it.")
        }
        let manager = AIResourceManager()
        let data = try XCTUnwrap(makeImage(width: 1200, height: 900).jpegData(compressionQuality: 0.9))
        let task = Task {
            try await manager.generateVisualJSON(
                prompt: OpenSourceLocalProvider.visionPrompt(pageNumber: 1), imageData: data
            )
        }
        let readinessDeadline = ContinuousClock.now + .seconds(45)
        while await manager.syllabusVisionProgress() == nil, ContinuousClock.now < readinessDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let startedEncoding = await manager.syllabusVisionProgress() != nil
        let start = ContinuousClock.now
        task.cancel()
        await manager.cancelCurrentInference()
        do {
            _ = try await task.value
            XCTFail("Cancelled visual inference must not return a successful result.")
        } catch is CancellationError {
            // Expected; other native errors must not masquerade as cancellation.
        } catch {
            XCTFail("Unexpected cancellation outcome: \(error)")
        }
        let elapsed = start.duration(to: .now)
        let snapshot = await manager.snapshot()
        XCTAssertTrue(startedEncoding, "The test must exercise image encoding, not only model loading.")
        XCTAssertLessThan(elapsed, .seconds(10))
        XCTAssertNil(snapshot.loadedModelID)
        XCTAssertEqual(snapshot.activeLeaseCount, 0)
        print("VISION_CANCEL elapsed=\(elapsed) released=\(snapshot.loadedModelID == nil)")
#endif
    }

    func testImageReadinessDoesNotRequireAnUnrelatedTextDownload() throws {
        let descriptor = OnDeviceAIVisionModelLibrary.descriptor
        let visual = AIVisualModelRecord(
            descriptor: descriptor, state: .ready, activeArtifact: nil,
            modelResumeData: nil, projectorResumeData: nil,
            modelReceivedBytes: descriptor.model.bytes, projectorReceivedBytes: descriptor.projector.bytes,
            verifiedAt: .now
        )
        let text = AIModelStoreSnapshot(
            records: [], activeModelID: nil, recommendedTier: .efficient,
            powerPreference: .balanced, useEnhancedOnlyWhileCharging: true,
            storageUsedBytes: 0, storageBudgetBytes: 0
        )
        let resources = AISyllabusResources(text: text, visual: .init(record: visual, storageUsedBytes: descriptor.totalBytes))
        let page = try SyllabusTextExtractor.readImageData(try XCTUnwrap(makeImage(width: 600, height: 400).jpegData(compressionQuality: 0.9)), number: 1)
        let image = SyllabusTextExtractor.Document(pages: [page], source: .image)
        XCTAssertNil(resources.unavailableReason(for: image))
        let mixed = SyllabusTextExtractor.Document(pages: [page, .init(number: 2, text: "Grading", image: nil)], source: .pdf)
        XCTAssertNotNil(resources.unavailableReason(for: mixed))
        XCTAssertNotNil(resources.unavailableReason(for: nil))
    }

    /// Uses a rendered, unmodified page from UC Davis MAT180 (Spring 2023).
    /// Provision the small PNG locally; this test never fetches any resource.
    func testProvisionedRealSyllabusImageUsesOnlyVisualModel() async throws {
        try await verifyPublicSyllabusImage(visionUsesGPU: false)
    }

    func testProvisionedRealSyllabusImageWithGPUEncoder() async throws {
#if targetEnvironment(simulator)
        throw XCTSkip("GPU encoder acceptance requires a physical device.")
#else
        try await verifyPublicSyllabusImage(visionUsesGPU: nil)
#endif
    }

    private func verifyPublicSyllabusImage(visionUsesGPU: Bool?) async throws {
        let manager: AIResourceManager
        if let visionUsesGPU {
            manager = AIResourceManager(idleUnloadDuration: .milliseconds(1), visionUsesGPU: visionUsesGPU)
        } else {
            manager = AIResourceManager(idleUnloadDuration: .milliseconds(1))
        }
        print("AGGIE_PUBLIC_FIXTURE_GPU_ENCODER \(visionUsesGPU.map(String.init) ?? "production-default")")
        let sceneMonitor = Task {
            while !Task.isCancelled {
                let state = await MainActor.run { UIApplication.shared.applicationState.rawValue }
                print("AGGIE_PUBLIC_FIXTURE_APP_STATE \(state)")
                if let fraction = await manager.syllabusVisionProgress()?.fraction {
                    print("AGGIE_PUBLIC_FIXTURE_IMAGE_PROGRESS \(fraction)")
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
        defer {
            sceneMonitor.cancel()
        }
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MAT180-page3.png")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("The local MAT180 page image has not been provisioned.")
        }
        _ = try await OnDeviceAIVisionModelLibrary.verifyReady()
        let data = try Data(contentsOf: url)
        let source = SyllabusTextExtractor.Document(
            pages: [try SyllabusTextExtractor.readImageData(data, number: 3)], source: .image
        )
        XCTAssertNil(source.pages.first?.text)
        print("AGGIE_VISION_HEADROOM \(await manager.snapshot().availableMemoryBytes)")
        var provider = OpenSourceLocalProvider(resourceManager: manager)
        provider.visualOutputDiagnostic = { print("AGGIE_PUBLIC_FIXTURE_RAW \($0)") }
        let result = try await provider.analyze(document: source, progress: { _ in })
        print("AGGIE_REAL_SYLLABUS_OUTPUT \(String(decoding: try JSONEncoder().encode(result.analysis), as: UTF8.self))")
        print("AGGIE_REAL_SYLLABUS_METRICS \(String(decoding: try JSONEncoder().encode(result.metrics), as: UTF8.self))")
        XCTAssertEqual(result.providerName, "llama.cpp")
        XCTAssertEqual(result.modelName, "Qwen2-VL 2B")
        XCTAssertEqual(result.analysis.categories.count, 3)
        XCTAssertTrue(result.analysis.categories.contains { $0.name.localizedCaseInsensitiveContains("participation") && $0.weightPercent == 20 })
        XCTAssertTrue(result.analysis.categories.contains { $0.name.localizedCaseInsensitiveContains("Homework") && $0.weightPercent == 50 })
        XCTAssertTrue(result.analysis.categories.contains { $0.name.localizedCaseInsensitiveContains("Project") && $0.weightPercent == 30 })
        XCTAssertTrue(result.analysis.categories.allSatisfy { $0.totalPoints == nil && $0.evidence.first?.sourcePage == 3 })
        XCTAssertEqual(result.analysis.totalWeight, 100)
        XCTAssertTrue(result.recognizedSource?.hasContent == true)
        await manager.unloadIfIdle()
    }

    func testVisualModelIsPinnedAsOneCompleteBundleAndProgressIsAggregate() {
        let descriptor = OnDeviceAIVisionModelLibrary.descriptor
        XCTAssertEqual(descriptor.modelName, "Qwen2-VL 2B")
        XCTAssertEqual(descriptor.quantization, "Q4_K_M + projector Q8_0")
        XCTAssertEqual(descriptor.model.sha256.count, 64)
        XCTAssertEqual(descriptor.projector.sha256.count, 64)
        XCTAssertEqual(descriptor.totalBytes, 1_695_930_304)
        XCTAssertTrue(descriptor.model.sourceReference.contains(descriptor.revision))
        XCTAssertTrue(descriptor.projector.sourceReference.contains(descriptor.revision))

        let progress = AIVisualModelProgress(
            artifact: .projector,
            receivedBytes: descriptor.projector.bytes / 2,
            expectedBytes: descriptor.projector.bytes,
            totalReceivedBytes: descriptor.model.bytes + descriptor.projector.bytes / 2,
            totalExpectedBytes: descriptor.totalBytes
        )
        XCTAssertEqual(
            progress.fraction,
            Double(descriptor.model.bytes + descriptor.projector.bytes / 2) / Double(descriptor.totalBytes),
            accuracy: 0.000_001
        )
        XCTAssertEqual(progress.asDownloadProgress.receivedBytes, progress.totalReceivedBytes)
        XCTAssertEqual(progress.asDownloadProgress.expectedBytes, descriptor.totalBytes)
    }

    func testRecognizedSourceIsOptionalAndCodableForPostImportSearch() throws {
        let source = SyllabusRecognizedSource(
            text: "作业 20%\n期末考试 80%",
            pagesData: Data([1, 2, 3])
        )
        let draft = SyllabusImportDraft()
        var updated = draft
        updated.recognizedSource = source

        let decoded = try JSONDecoder().decode(
            SyllabusImportDraft.self,
            from: JSONEncoder().encode(updated)
        )

        XCTAssertEqual(decoded.recognizedSource, source)
        XCTAssertTrue(decoded.recognizedSource?.hasContent == true)
    }

    private func makeImage(width: CGFloat, height: CGFloat) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: width, height: height)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: width * 0.1, y: height * 0.1, width: width * 0.8, height: height * 0.12))
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: width * 0.1, y: height * 0.4, width: width * 0.6, height: height * 0.08))
        }
    }
}
