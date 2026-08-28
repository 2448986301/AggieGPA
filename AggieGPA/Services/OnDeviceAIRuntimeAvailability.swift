import Foundation

/// Describes which optional on-device AI pieces are actually present in the
/// current build. This is deliberately a capability report, not a promise
/// that a model has been downloaded or that a runtime is production-ready.
nonisolated enum OnDeviceAIRuntimeAvailability: Sendable {
    static var llamaCppLinked: Bool {
        #if canImport(llama)
        true
        #else
        false
        #endif
    }

    static var mlxSwiftLinked: Bool {
        #if canImport(MLX) || canImport(MLXLLM) || canImport(MLXLMCommon)
        true
        #else
        false
        #endif
    }

    static var appleFoundationModelsAvailable: Bool {
        // The provider is intentionally an explicit unavailable placeholder
        // until a supported Foundation Models API is adopted and benchmarked.
        false
    }

    static var modelInstalled: Bool {
        AIModelStore.quickAvailability()
    }

    static var modelFileBytes: Int64? {
        guard modelInstalled else { return nil }
        return AIModelStore.descriptors
            .compactMap { descriptor -> Int64? in
                let url = AIModelStore.modelURL(for: descriptor)
                guard let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return nil }
                return Int64(fileSize)
            }
            .max()
    }
}
