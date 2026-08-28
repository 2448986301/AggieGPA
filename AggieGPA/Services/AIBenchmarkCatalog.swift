import Foundation

/// The three model-quality tiers that Phase 8C must compare against the
/// retained 0.5B baseline. A tier remains a candidate until comparable model
/// quality results and the release-only physical-device evidence are recorded.
nonisolated enum AIBenchmarkQualityTier: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case efficient
    case balanced
    case enhanced

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .efficient: return "Efficient"
        case .balanced: return "Balanced"
        case .enhanced: return "Enhanced"
        }
    }

    /// This is a selection band, not a measured model size.  Exact parameter
    /// count and storage must come from the pinned artifact before a run.
    var parameterBand: String {
        switch self {
        case .efficient: return "~1.5B–2B"
        case .balanced: return "~3B–4B"
        case .enhanced: return "~7B–8B"
        }
    }
}

nonisolated struct AIBenchmarkCandidate: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let tier: AIBenchmarkQualityTier
    let modelName: String
    let quantization: String
    let parameterBand: String
    let repository: String
    let revision: String
    let modelLicense: String
    let licenseReference: String
    let sourceReference: String
    let artifactFileName: String?
    let artifactSHA256: String?
    let artifactBytes: Int64?

    var hasPinnedArtifactMetadata: Bool {
        !repository.isEmpty
            && revision.count == 40
            && !modelLicense.isEmpty
            && licenseReference.contains(revision)
            && artifactFileName != nil
            && artifactSHA256?.count == 64
            && (artifactBytes ?? 0) > 0
    }
}

nonisolated enum AIBenchmarkTierRunStatus: String, Codable, Sendable {
    case ready
    case blocked
    case completed
    case failed
}

nonisolated enum AIBenchmarkBlocker: String, Codable, CaseIterable, Sendable {
    case runtimeNotLinked
    case candidateArtifactNotProvisioned
    case physicalDeviceEvidenceRequired
    case modelLoadFailed
    case structuredOutputFailed
    case cancelled
}

/// Metrics are optional until an actual candidate run exists. Simulator
/// quality/latency results may be recorded only from a real linked runtime and
/// verified artifact; physical-device-only thermal and power fields stay
/// pending rather than being estimated.
nonisolated struct AIBenchmarkTierMetrics: Codable, Equatable, Sendable {
    let modelLoadSeconds: Double?
    let firstTokenSeconds: Double?
    let totalAnalysisSeconds: Double?
    let generatedTokens: Int?
    let tokensPerSecond: Double?
    let structuredOutputSuccessRate: Double?
    let extractionAccuracy: Double?
    let ruleAccuracy: Double?
    let hallucinationRate: Double?
    let peakMemoryBytes: UInt64?
    let thermalStates: [String]
    let batteryAndPowerMeasured: Bool
    let crashOrOOMObserved: Bool
}

nonisolated struct AIBenchmarkTierResult: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let candidate: AIBenchmarkCandidate
    let status: AIBenchmarkTierRunStatus
    /// Conditions that prevent the fixed quality benchmark from running.
    let blockers: [AIBenchmarkBlocker]
    /// Release-only gates that do not prevent simulator or isolated-runtime
    /// quality measurements from being recorded.
    let productionBlockers: [AIBenchmarkBlocker]
    let notes: [String]
    let metrics: AIBenchmarkTierMetrics?

    var isReadyForQualityBenchmark: Bool {
        status == .ready || status == .completed
    }

    var hasComparableMetrics: Bool {
        status == .completed && metrics != nil
    }

    var isEligibleForProductionSelection: Bool {
        hasComparableMetrics && productionBlockers.isEmpty
    }
}

nonisolated struct AIBenchmarkMatrixReport: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let generatedAt: Date
    let datasetCaseCount: Int
    let baselineReportReference: String
    let baselineIsProductionCandidate: Bool
    let candidateResults: [AIBenchmarkTierResult]
    let defaultSelection: AIBenchmarkQualityTier?
    let selectionStatus: String

    var allTiersPresent: Bool {
        Set(candidateResults.map { $0.candidate.tier }) == Set(AIBenchmarkQualityTier.allCases)
    }

    var isComparisonComplete: Bool {
        allTiersPresent && candidateResults.allSatisfy(\.hasComparableMetrics)
    }

    var isProductionSelectionReady: Bool {
        isComparisonComplete && candidateResults.allSatisfy(\.isEligibleForProductionSelection)
    }
}

/// Exact official Qwen GGUF artifacts verified during Phase 8C. The catalog
/// pins remote provenance and integrity metadata; local provisioning is
/// supplied separately by the benchmark environment so the production target
/// never claims that a model or runtime is bundled when it is not.
nonisolated enum AIBenchmarkCandidateCatalog {
    static let candidates: [AIBenchmarkCandidate] = [
        .init(
            id: "qwen3-1.7b-q8_0",
            tier: .efficient,
            modelName: "Qwen3-1.7B",
            quantization: "Q8_0",
            parameterBand: AIBenchmarkQualityTier.efficient.parameterBand,
            repository: "Qwen/Qwen3-1.7B-GGUF",
            revision: "90862c4b9d2787eaed51d12237eafdfe7c5f6077",
            modelLicense: "Apache-2.0",
            licenseReference: "https://huggingface.co/Qwen/Qwen3-1.7B-GGUF/blob/90862c4b9d2787eaed51d12237eafdfe7c5f6077/LICENSE",
            sourceReference: "https://huggingface.co/Qwen/Qwen3-1.7B-GGUF/resolve/90862c4b9d2787eaed51d12237eafdfe7c5f6077/Qwen3-1.7B-Q8_0.gguf",
            artifactFileName: "Qwen3-1.7B-Q8_0.gguf",
            artifactSHA256: "061b54daade076b5d3362dac252678d17da8c68f07560be70818cace6590cb1a",
            artifactBytes: 1_834_426_016
        ),
        .init(
            id: "qwen3-4b-q4_k_m",
            tier: .balanced,
            modelName: "Qwen3-4B",
            quantization: "Q4_K_M",
            parameterBand: AIBenchmarkQualityTier.balanced.parameterBand,
            repository: "Qwen/Qwen3-4B-GGUF",
            revision: "bc640142c66e1fdd12af0bd68f40445458f3869b",
            modelLicense: "Apache-2.0",
            licenseReference: "https://huggingface.co/Qwen/Qwen3-4B-GGUF/blob/bc640142c66e1fdd12af0bd68f40445458f3869b/LICENSE",
            sourceReference: "https://huggingface.co/Qwen/Qwen3-4B-GGUF/resolve/bc640142c66e1fdd12af0bd68f40445458f3869b/Qwen3-4B-Q4_K_M.gguf",
            artifactFileName: "Qwen3-4B-Q4_K_M.gguf",
            artifactSHA256: "7485fe6f11af29433bc51cab58009521f205840f5b4ae3a32fa7f92e8534fdf5",
            artifactBytes: 2_497_280_256
        ),
        .init(
            id: "qwen3-8b-q4_k_m",
            tier: .enhanced,
            modelName: "Qwen3-8B",
            quantization: "Q4_K_M",
            parameterBand: AIBenchmarkQualityTier.enhanced.parameterBand,
            repository: "Qwen/Qwen3-8B-GGUF",
            revision: "7c41481f57cb95916b40956ab2f0b139b296d974",
            modelLicense: "Apache-2.0",
            licenseReference: "https://huggingface.co/Qwen/Qwen3-8B-GGUF/blob/7c41481f57cb95916b40956ab2f0b139b296d974/LICENSE",
            sourceReference: "https://huggingface.co/Qwen/Qwen3-8B-GGUF/resolve/7c41481f57cb95916b40956ab2f0b139b296d974/Qwen3-8B-Q4_K_M.gguf",
            artifactFileName: "Qwen3-8B-Q4_K_M.gguf",
            artifactSHA256: "d98cdcbd03e17ce47681435b5150e34c1417f50b5c0019dd560e4882c5745785",
            artifactBytes: 5_027_783_488
        )
    ]
}

nonisolated struct AIBenchmarkRuntimeCapabilities: Codable, Equatable, Sendable {
    let llamaCppLinked: Bool
    let mlxSwiftLinked: Bool
    /// Candidate IDs whose local files were checked against the catalog's
    /// exact byte count and SHA-256 before this benchmark invocation.
    let verifiedArtifactCandidateIDs: Set<String>
    /// Candidate IDs with actual physical-device thermal and power evidence.
    /// Simulator support is never inserted into this set.
    let physicalDeviceEvidenceCandidateIDs: Set<String>

    init(
        llamaCppLinked: Bool,
        mlxSwiftLinked: Bool,
        verifiedArtifactCandidateIDs: Set<String> = [],
        physicalDeviceEvidenceCandidateIDs: Set<String> = []
    ) {
        self.llamaCppLinked = llamaCppLinked
        self.mlxSwiftLinked = mlxSwiftLinked
        self.verifiedArtifactCandidateIDs = verifiedArtifactCandidateIDs
        self.physicalDeviceEvidenceCandidateIDs = physicalDeviceEvidenceCandidateIDs
    }

    static var current: AIBenchmarkRuntimeCapabilities {
        .init(
            llamaCppLinked: OnDeviceAIRuntimeAvailability.llamaCppLinked,
            mlxSwiftLinked: OnDeviceAIRuntimeAvailability.mlxSwiftLinked,
            verifiedArtifactCandidateIDs: [],
            physicalDeviceEvidenceCandidateIDs: []
        )
    }
}

nonisolated enum AIBenchmarkMatrixPreflight {
    static func run(
        candidates: [AIBenchmarkCandidate] = AIBenchmarkCandidateCatalog.candidates,
        capabilities: AIBenchmarkRuntimeCapabilities
    ) -> [AIBenchmarkTierResult] {
        candidates.map { candidate in
            var blockers: [AIBenchmarkBlocker] = []
            if !capabilities.llamaCppLinked && !capabilities.mlxSwiftLinked {
                blockers.append(.runtimeNotLinked)
            }
            if !candidate.hasPinnedArtifactMetadata
                || !capabilities.verifiedArtifactCandidateIDs.contains(candidate.id) {
                blockers.append(.candidateArtifactNotProvisioned)
            }
            let productionBlockers: [AIBenchmarkBlocker] = capabilities
                .physicalDeviceEvidenceCandidateIDs.contains(candidate.id)
                ? []
                : [.physicalDeviceEvidenceRequired]
            let status: AIBenchmarkTierRunStatus = blockers.isEmpty ? .ready : .blocked
            return AIBenchmarkTierResult(
                id: candidate.id,
                candidate: candidate,
                status: status,
                blockers: blockers,
                productionBlockers: productionBlockers,
                notes: notes(qualityBlockers: blockers, productionBlockers: productionBlockers),
                metrics: nil
            )
        }
    }

    private static func notes(
        qualityBlockers: [AIBenchmarkBlocker],
        productionBlockers: [AIBenchmarkBlocker]
    ) -> [String] {
        guard qualityBlockers.isEmpty else {
            return ["No quality metrics were generated because the benchmark runtime or verified artifact was unavailable."]
        }
        guard productionBlockers.isEmpty else {
            return [
                "Candidate is ready for the fixed 14-case quality run.",
                "Physical-device thermal and power evidence remains required before production selection."
            ]
        }
        return ["Candidate is ready for the fixed 14-case run and its physical-device evidence gate is available."]
    }

    static func report(
        datasetCaseCount: Int,
        baselineReportReference: String,
        capabilities: AIBenchmarkRuntimeCapabilities,
        candidates: [AIBenchmarkCandidate] = AIBenchmarkCandidateCatalog.candidates,
        now: Date = Date()
    ) -> AIBenchmarkMatrixReport {
        let results = run(candidates: candidates, capabilities: capabilities)
        return .init(
            schemaVersion: 2,
            generatedAt: now,
            datasetCaseCount: datasetCaseCount,
            baselineReportReference: baselineReportReference,
            baselineIsProductionCandidate: false,
            candidateResults: results,
            defaultSelection: nil,
            selectionStatus: selectionStatus(for: results)
        )
    }

    private static func selectionStatus(for results: [AIBenchmarkTierResult]) -> String {
        if results.contains(where: { $0.status == .blocked }) {
            return "blocked: quality benchmark runtime or verified candidate artifacts are unavailable"
        }
        if results.contains(where: { $0.productionBlockers.contains(.physicalDeviceEvidenceRequired) }) {
            return "quality benchmark ready: physical-device evidence remains required before production selection"
        }
        return "pending: complete all three comparable candidate runs before selecting a default"
    }
}
