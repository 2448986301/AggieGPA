import Foundation

nonisolated enum AIProviderKind: String, Codable, CaseIterable, Sendable {
    case openSourceLocal
    case appleFoundationModels
    case noAI
}

/// Keeps provider selection in one runtime-neutral boundary. Feature views and
/// parsers can request a capability without importing a model runtime.
nonisolated enum AIProviderFactory {
    static func make(
        kind: AIProviderKind,
        resourceManager: AIResourceManager = .shared
    ) -> any AIProvider {
        switch kind {
        case .openSourceLocal:
            OpenSourceLocalProvider(resourceManager: resourceManager)
        case .appleFoundationModels:
            AppleFoundationModelsProvider()
        case .noAI:
            NoAIProvider()
        }
    }

    static func make(
        mode: SyllabusAnalysisMode,
        resourceManager: AIResourceManager = .shared
    ) -> any AIProvider {
        make(
            kind: mode == .onDevice ? .openSourceLocal : .noAI,
            resourceManager: resourceManager
        )
    }
}
