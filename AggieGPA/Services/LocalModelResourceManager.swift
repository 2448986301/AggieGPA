import Foundation

/// Compatibility facade for the 1.4.1 syllabus-import API. New code uses
/// `AIModelStore` and `OnDeviceAIModelLibrary`; this type intentionally keeps
/// the old symbols so existing migrations/tests do not break, but it never
/// downloads or promotes the old 0.5B prototype.
nonisolated struct ModelDownloadProgress: Equatable, Sendable {
    let receivedBytes: Int64
    let expectedBytes: Int64

    var fraction: Double? {
        guard expectedBytes > 0 else { return nil }
        return min(1, max(0, Double(receivedBytes) / Double(expectedBytes)))
    }

    static let starting = ModelDownloadProgress(
        receivedBytes: 0,
        expectedBytes: AIModelStore.recommendedDescriptor.artifactBytes
    )
}

nonisolated enum LocalModelState: Equatable, Sendable {
    case checking
    case downloadRequired
    case downloading
    case ready
    case failed(String)
}

actor LocalModelResourceManager {
    static let shared = LocalModelResourceManager()

    // Legacy metadata is retained solely for migration/test compatibility.
    // It is not listed in the 2.0 model library and is never selected.
    static let modelName = "Qwen2.5 0.5B Instruct Q4_K_M (legacy benchmark only)"
    static let modelFileName = "qwen2.5-0.5b-instruct-q4_k_m.gguf"
    static let approximateDownloadBytes: Int64 = 491_000_000
    static let pinnedRevision = "9217f5db79a29953eb74d5343926648285ec7e67"
    static let downloadURL = URL(
        string: "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/9217f5db79a29953eb74d5343926648285ec7e67/qwen2.5-0.5b-instruct-q4_k_m.gguf"
    )!

    nonisolated static var modelURL: URL { AIModelStore.modelURL(for: AIModelStore.recommendedDescriptor) }

    nonisolated static var currentState: LocalModelState {
        AIModelStore.quickAvailability() ? .ready : .downloadRequired
    }

    func prepare(
        progress: @escaping @Sendable (ModelDownloadProgress) -> Void = { _ in }
    ) async throws -> URL {
        let record = try await AIModelStore.shared.prepareRecommended(progress: progress)
        return record.localURL
    }

    func installModel(from source: URL) async throws -> URL {
        let record = try await AIModelStore.shared.installImportedModel(from: source)
        return record.localURL
    }

    nonisolated static func validateGGUF(at url: URL) throws {
        guard AIModelStore.descriptors.contains(where: { descriptor in
            (try? AIModelStore.validateArtifact(at: url, descriptor: descriptor)) != nil
        }) else {
            throw ModelResourceError.invalidModel
        }
    }

    enum ModelResourceError: LocalizedError {
        case downloadFailed
        case invalidModel
        case importFailed
        case network(URLError.Code)

        var errorDescription: String? {
            switch self {
            case .downloadFailed: "The local model could not be downloaded."
            case .invalidModel: "The selected local model is invalid or unverified."
            case .importFailed: "The selected GGUF model could not be imported."
            case .network: "The local model download was interrupted."
            }
        }

        func message(locale: Locale) -> String {
            AppLocalization.string(errorDescription ?? "The local model could not be used.", locale: locale)
        }
    }
}
