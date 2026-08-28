import Foundation
import XCTest
@testable import AggieGPA

final class AIBenchmarkTierMatrixTests: XCTestCase {
    func testPhase8CCatalogHasExactlyThreeCandidatesAndNoDefault() {
        let candidates = AIBenchmarkCandidateCatalog.candidates
        XCTAssertEqual(candidates.count, 3)
        XCTAssertEqual(Set(candidates.map(\.tier)), Set(AIBenchmarkQualityTier.allCases))
        XCTAssertTrue(candidates.allSatisfy { !$0.modelName.isEmpty && !$0.quantization.isEmpty })
        XCTAssertTrue(candidates.allSatisfy(\.hasPinnedArtifactMetadata))
        XCTAssertTrue(candidates.allSatisfy { $0.modelLicense == "Apache-2.0" })
        XCTAssertTrue(candidates.allSatisfy { $0.licenseReference.contains($0.revision) })
        XCTAssertTrue(candidates.allSatisfy { $0.licenseReference.hasSuffix("/LICENSE") })
        XCTAssertTrue(candidates.allSatisfy { $0.sourceReference.contains($0.revision) })
        XCTAssertTrue(candidates.allSatisfy { candidate in
            guard let fileName = candidate.artifactFileName else { return false }
            return candidate.sourceReference.hasSuffix("/\(fileName)")
        })
        XCTAssertFalse(candidates.contains { $0.modelName.localizedCaseInsensitiveContains("0.5B") })

        XCTAssertEqual(
            candidates.reduce(Int64(0)) { $0 + ($1.artifactBytes ?? 0) },
            9_359_489_760
        )
        XCTAssertLessThan(
            candidates.reduce(Int64(0)) { $0 + ($1.artifactBytes ?? 0) },
            10_000_000_000
        )
    }

    func testPhase8CCatalogPinsVerifiedOfficialArtifacts() {
        let candidates = Dictionary(
            uniqueKeysWithValues: AIBenchmarkCandidateCatalog.candidates.map { ($0.tier, $0) }
        )

        XCTAssertEqual(candidates[.efficient]?.modelName, "Qwen3-1.7B")
        XCTAssertEqual(candidates[.efficient]?.quantization, "Q8_0")
        XCTAssertEqual(candidates[.efficient]?.repository, "Qwen/Qwen3-1.7B-GGUF")
        XCTAssertEqual(candidates[.efficient]?.revision, "90862c4b9d2787eaed51d12237eafdfe7c5f6077")
        XCTAssertEqual(candidates[.efficient]?.artifactFileName, "Qwen3-1.7B-Q8_0.gguf")
        XCTAssertEqual(candidates[.efficient]?.artifactSHA256, "061b54daade076b5d3362dac252678d17da8c68f07560be70818cace6590cb1a")
        XCTAssertEqual(candidates[.efficient]?.artifactBytes, 1_834_426_016)

        XCTAssertEqual(candidates[.balanced]?.modelName, "Qwen3-4B")
        XCTAssertEqual(candidates[.balanced]?.quantization, "Q4_K_M")
        XCTAssertEqual(candidates[.balanced]?.repository, "Qwen/Qwen3-4B-GGUF")
        XCTAssertEqual(candidates[.balanced]?.revision, "bc640142c66e1fdd12af0bd68f40445458f3869b")
        XCTAssertEqual(candidates[.balanced]?.artifactFileName, "Qwen3-4B-Q4_K_M.gguf")
        XCTAssertEqual(candidates[.balanced]?.artifactSHA256, "7485fe6f11af29433bc51cab58009521f205840f5b4ae3a32fa7f92e8534fdf5")
        XCTAssertEqual(candidates[.balanced]?.artifactBytes, 2_497_280_256)

        XCTAssertEqual(candidates[.enhanced]?.modelName, "Qwen3-8B")
        XCTAssertEqual(candidates[.enhanced]?.quantization, "Q4_K_M")
        XCTAssertEqual(candidates[.enhanced]?.repository, "Qwen/Qwen3-8B-GGUF")
        XCTAssertEqual(candidates[.enhanced]?.revision, "7c41481f57cb95916b40956ab2f0b139b296d974")
        XCTAssertEqual(candidates[.enhanced]?.artifactFileName, "Qwen3-8B-Q4_K_M.gguf")
        XCTAssertEqual(candidates[.enhanced]?.artifactSHA256, "d98cdcbd03e17ce47681435b5150e34c1417f50b5c0019dd560e4882c5745785")
        XCTAssertEqual(candidates[.enhanced]?.artifactBytes, 5_027_783_488)
    }

    func testPhase8CUnavailablePreflightDoesNotFabricateMetrics() {
        let capabilities = AIBenchmarkRuntimeCapabilities(
            llamaCppLinked: false,
            mlxSwiftLinked: false
        )
        let results = AIBenchmarkMatrixPreflight.run(capabilities: capabilities)

        XCTAssertEqual(results.count, 3)
        XCTAssertTrue(results.allSatisfy { $0.status == .blocked })
        XCTAssertTrue(results.allSatisfy { $0.metrics == nil })
        XCTAssertTrue(results.allSatisfy { $0.blockers.contains(.runtimeNotLinked) })
        XCTAssertTrue(results.allSatisfy { $0.blockers.contains(.candidateArtifactNotProvisioned) })
        XCTAssertTrue(results.allSatisfy { !$0.blockers.contains(.physicalDeviceEvidenceRequired) })
        XCTAssertTrue(results.allSatisfy { $0.productionBlockers == [.physicalDeviceEvidenceRequired] })
    }

    func testPhase8CReportKeepsBaselineSeparateAndLeavesSelectionUnset() throws {
        let report = AIBenchmarkMatrixPreflight.report(
            datasetCaseCount: 14,
            baselineReportReference: "/private/tmp/AggieGPA-ai-benchmark-llama-live.json",
            capabilities: .init(
                llamaCppLinked: false,
                mlxSwiftLinked: false
            ),
            now: Date(timeIntervalSince1970: 1_755_000_000)
        )

        XCTAssertEqual(report.schemaVersion, 2)
        XCTAssertEqual(report.datasetCaseCount, 14)
        XCTAssertFalse(report.baselineIsProductionCandidate)
        XCTAssertNil(report.defaultSelection)
        XCTAssertFalse(report.isComparisonComplete)
        XCTAssertFalse(report.isProductionSelectionReady)
        XCTAssertTrue(report.selectionStatus.hasPrefix("blocked:"))

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(report)
        let decoded = try JSONDecoder().decode(AIBenchmarkMatrixReport.self, from: data)
        XCTAssertEqual(decoded, report)

        let url = URL(fileURLWithPath: "/private/tmp/AggieGPA-ai-benchmark-phase8c-matrix.json")
        try data.write(to: url, options: .atomic)
        print("AI Phase 8C matrix preflight: \(url.path)")
        print(String(decoding: data, as: UTF8.self))
    }

    func testPhase8CCurrentEnvironmentReportIsExplicitAboutWhatCanRun() throws {
        let report = AIBenchmarkMatrixPreflight.report(
            datasetCaseCount: 14,
            baselineReportReference: "/private/tmp/AggieGPA-ai-benchmark-llama-live.json",
            capabilities: .current
        )

        XCTAssertEqual(report.candidateResults.count, 3)
        XCTAssertNil(report.defaultSelection)
        XCTAssertTrue(report.candidateResults.allSatisfy { $0.metrics == nil || $0.status == .completed })

        let url = URL(fileURLWithPath: "/private/tmp/AggieGPA-ai-benchmark-phase8c-matrix-current.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(report)
        try data.write(to: url, options: .atomic)
        print("AI Phase 8C current matrix: \(url.path)")
        print(String(decoding: data, as: UTF8.self))
    }

    func testPhase8CQualityBenchmarkCanRunWithoutPhysicalDeviceEvidence() throws {
        let candidate = try XCTUnwrap(
            AIBenchmarkCandidateCatalog.candidates.first { $0.tier == .efficient }
        )
        let capabilities = AIBenchmarkRuntimeCapabilities(
            llamaCppLinked: true,
            mlxSwiftLinked: false,
            verifiedArtifactCandidateIDs: [candidate.id]
        )

        let result = try XCTUnwrap(
            AIBenchmarkMatrixPreflight.run(candidates: [candidate], capabilities: capabilities).first
        )

        XCTAssertEqual(result.status, .ready)
        XCTAssertTrue(result.isReadyForQualityBenchmark)
        XCTAssertTrue(result.blockers.isEmpty)
        XCTAssertEqual(result.productionBlockers, [.physicalDeviceEvidenceRequired])
        XCTAssertFalse(result.isEligibleForProductionSelection)
        XCTAssertNil(result.metrics)
    }

    func testPhase8CVerifiedIDCannotReplacePinnedArtifactMetadata() {
        let capabilities = AIBenchmarkRuntimeCapabilities(
            llamaCppLinked: true,
            mlxSwiftLinked: false,
            verifiedArtifactCandidateIDs: ["ready-without-artifact"],
            physicalDeviceEvidenceCandidateIDs: ["ready-without-artifact"]
        )
        let candidate = AIBenchmarkCandidate(
            id: "ready-without-artifact",
            tier: .balanced,
            modelName: "Pinned candidate placeholder",
            quantization: "Q4_K_M",
            parameterBand: AIBenchmarkQualityTier.balanced.parameterBand,
            repository: "test/repository",
            revision: String(repeating: "a", count: 40),
            modelLicense: "Apache-2.0",
            licenseReference: "https://example.com/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/LICENSE",
            sourceReference: "test",
            artifactFileName: nil,
            artifactSHA256: nil,
            artifactBytes: nil
        )

        guard let result = AIBenchmarkMatrixPreflight.run(candidates: [candidate], capabilities: capabilities).first else {
            return XCTFail("The single candidate preflight result was missing.")
        }
        XCTAssertEqual(result.status, .blocked)
        XCTAssertEqual(result.blockers, [.candidateArtifactNotProvisioned])
        XCTAssertTrue(result.productionBlockers.isEmpty)
        XCTAssertNil(result.metrics)
    }
}
