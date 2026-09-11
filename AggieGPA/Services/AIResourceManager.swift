import Foundation
import os
import UIKit

nonisolated enum AIResourceSelectionReason: Equatable, Sendable {
    case userSelected
    case lowPowerMode
    case thermalState
    case chargingPreference
    case memoryPressure

    var messageKey: String {
        switch self {
        case .userSelected: "Using the selected local model."
        case .lowPowerMode, .thermalState, .chargingPreference, .memoryPressure:
            "Using a model better suited to this device."
        }
    }
}

nonisolated struct AIResourceSelection: Equatable, Sendable {
    let model: AIModelDescriptor
    let downgradedFrom: AIModelDescriptor?
    let reason: AIResourceSelectionReason

    var wasDowngraded: Bool { downgradedFrom != nil }
}

nonisolated struct AIResourceInferenceResult: Sendable {
    let generation: LlamaInferenceEngine.Generation
    let selection: AIResourceSelection
    let modelLoadSeconds: Double
}

nonisolated struct AIVisualResourceInferenceResult: Sendable {
    let generation: LlamaInferenceEngine.Generation
    let model: AIVisualModelDescriptor
    let modelLoadSeconds: Double
}

nonisolated struct AIResourceSnapshot: Equatable, Sendable {
    let loadedModelID: String?
    let activeLeaseCount: Int
    let idleUnloadSeconds: Double
    let lowPowerModeEnabled: Bool
    let thermalState: String
    let charging: Bool
    let availableMemoryBytes: UInt64
}

nonisolated struct AISyllabusResources: Equatable, Sendable {
    let text: AIModelStoreSnapshot
    let visual: AIVisualModelStoreSnapshot

    func unavailableReason(for document: SyllabusTextExtractor.Document?) -> String? {
        guard OnDeviceAIRuntimeAvailability.llamaCppLinked else {
            return "The open-source local model runtime is not linked in this build."
        }
        let hasImages = document?.pages.contains { $0.imageData != nil } == true
        let needsText = !hasImages || document?.pages.contains { $0.imageData == nil && $0.text?.isEmpty == false } == true
        if hasImages && !visual.isReady {
            return "The image model and its visual encoder must be installed and verified first."
        }
        if needsText && !text.records.contains(where: { $0.state == .ready && AIModelStore.isProductionSelectable($0.descriptor) }) {
            return hasImages
                ? "This PDF also contains text pages. A verified text model is required for those pages."
                : "Install a text model before analyzing text."
        }
        return nil
    }
}

/// Owns the one runtime engine used by the app. It intentionally does not
/// download models and it is never touched by Today/Courses/GPA navigation.
/// A model is loaded only after an explicit AI operation requests an active,
/// verified model.
actor AIResourceManager {
    static let shared = AIResourceManager()

    private let modelStore: AIModelStore
    private let idleUnloadDuration: Duration
    private var engine: LlamaInferenceEngine?
    private var loadedModelID: String?
    private var loadedProjectorID: String?
    private var activeLeaseCount = 0
    private var activeInferenceID: UUID?
    private var activeInferenceCancelled = false
    private var idleUnloadTask: Task<Void, Never>?
    private var engineLoadHeadroom: UInt64?
    private var retirementTask: Task<Bool, Never>?
    private var retirementTarget: UInt64 = 0
    private let visionUsesGPU: Bool

    init(modelStore: AIModelStore = .shared, idleUnloadDuration: Duration = .seconds(90), visionUsesGPU: Bool = true) {
        self.modelStore = modelStore
        self.idleUnloadDuration = idleUnloadDuration
        self.visionUsesGPU = visionUsesGPU
    }

    func syllabusResources() async -> AISyllabusResources {
        let text = await modelStore.snapshot()
        let visual = await OnDeviceAIVisionModelLibrary.snapshot()
        return AISyllabusResources(text: text, visual: visual)
    }

    func snapshot() async -> AIResourceSnapshot {
        AIResourceSnapshot(
            loadedModelID: loadedModelID,
            activeLeaseCount: activeLeaseCount,
            idleUnloadSeconds: idleUnloadDuration.secondsValue,
            lowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
            thermalState: ProcessInfo.processInfo.thermalState.metricName,
            charging: await Self.isCharging,
            availableMemoryBytes: Self.availableMemoryBytes
        )
    }

    func generateJSON(
        prompt: String,
        maximumTokens: Int = 1_536
    ) async throws -> AIResourceInferenceResult {
        let selection = try await selectModel()
        try Task.checkCancellation()
        guard activeInferenceID == nil else { throw AIModelStoreError.modelInUse }
        let inferenceID = UUID()
        activeInferenceID = inferenceID
        activeInferenceCancelled = false
        activeLeaseCount += 1
        idleUnloadTask?.cancel()
        defer {
            activeLeaseCount -= 1
            if activeInferenceID == inferenceID { activeInferenceID = nil }
            if activeLeaseCount == 0 { scheduleIdleUnload() }
        }

        do {
            return try await runInference(
                selection: selection,
                prompt: prompt,
                maximumTokens: maximumTokens
            )
        } catch is CancellationError {
            await unloadNow()
            throw CancellationError()
        } catch {
            await unloadNow()
            if activeInferenceCancelled || Task.isCancelled { throw CancellationError() }
            if let fallback = await fallbackSelection(after: selection) {
                return try await runInference(
                    selection: fallback,
                    prompt: prompt,
                    maximumTokens: maximumTokens
                )
            }
            throw error
        }
    }

    /// Runs one bounded image request through the verified vision bundle. The
    /// resource manager intentionally shares one engine slot with text
    /// inference, so switching modes releases the previous model before the
    /// replacement is loaded.
    func generateVisualJSON(
        prompt: String,
        imageData: Data,
        maximumTokens: Int = 1_024
    ) async throws -> AIVisualResourceInferenceResult {
        try Task.checkCancellation()
        guard !imageData.isEmpty else { throw SyllabusTextExtractor.ExtractionError.noReadableContent }
        guard activeInferenceID == nil else { throw AIModelStoreError.modelInUse }
        let inferenceID = UUID()
        activeInferenceID = inferenceID
        activeInferenceCancelled = false
        activeLeaseCount += 1
        idleUnloadTask?.cancel()
        defer {
            activeLeaseCount -= 1
            if activeInferenceID == inferenceID { activeInferenceID = nil }
            if activeLeaseCount == 0 { scheduleIdleUnload() }
        }

        do {
            return try await runVisualInference(
                prompt: prompt,
                imageData: imageData,
                maximumTokens: maximumTokens
            )
        } catch is CancellationError {
            await unloadNow()
            throw CancellationError()
        } catch {
            // A failed visual load must not leave a partially initialized
            // projector or stale engine resident for the OCR fallback.
            await unloadNow()
            if activeInferenceCancelled || Task.isCancelled { throw CancellationError() }
            throw error
        }
    }

    func syllabusVisionProgress() -> SyllabusVisionProgress? {
        guard activeInferenceID != nil, loadedProjectorID != nil else { return nil }
        return engine?.visualWorkProgress
    }

    /// Called by scene/background and thermal observers. Critical thermal state
    /// cancels the engine and keeps the rest of the app available.
    func handleThermalState(_ state: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState) async {
        if state == .critical {
            await cancelCurrentInference()
        }
    }

    func cancelCurrentInference() async {
        activeInferenceCancelled = true
        engine?.cancelGeneration()
        let deadline = ContinuousClock.now + .seconds(5)
        while activeInferenceID != nil, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        await unloadNow()
    }

    func cancelIfUsingModel(id: String) async {
        guard loadedModelID == id else { return }
        await cancelCurrentInference()
    }

    func unloadIfIdle() async {
        guard activeLeaseCount == 0 else { return }
        idleUnloadTask = nil
        _ = await retireEngine()
    }

    private func unloadNow() async {
        idleUnloadTask?.cancel()
        idleUnloadTask = nil
        _ = await retireEngine()
    }

    /// Native buffers are released immediately, but physical-device memory
    /// accounting can take a few seconds to settle. Never overlap a new cold
    /// load with that retiring allocation or weaken the cold-load budget.
    private func retireEngine() async -> Bool {
        if engine != nil {
            let target = Self.retirementHeadroomTarget(loadHeadroom: engineLoadHeadroom ?? 0)
            engine = nil
            loadedModelID = nil
            loadedProjectorID = nil
            engineLoadHeadroom = nil
            retirementTarget = target
            retirementTask = Task.detached(priority: .utility) {
                let deadline = ContinuousClock.now + .seconds(5)
                repeat {
                    if Self.availableMemoryBytes >= target { return true }
                    try? await Task.sleep(for: .milliseconds(100))
                } while ContinuousClock.now < deadline
                return Self.availableMemoryBytes >= target
            }
        }
        guard let retirementTask else { return true }
        let settled = await retirementTask.value
        return settled || Self.availableMemoryBytes >= retirementTarget
    }

    private func engine(for descriptor: AIModelDescriptor) async throws -> LlamaInferenceEngine {
        if let engine, loadedModelID == descriptor.id { return engine }
        guard ProcessInfo.processInfo.thermalState != .critical else {
            throw AIModelStoreError.thermalCritical
        }
        _ = try await modelStore.verifyReadyModel(id: descriptor.id)
        guard await retireEngine() else { throw AIModelStoreError.resourceConstrained }
        try Task.checkCancellation()
        let loadHeadroom = Self.availableMemoryBytes
        let loaded = try await LlamaInferenceEngine.load(
            modelURL: AIModelStore.modelURL(for: descriptor),
            tier: descriptor.tier
        )
        guard !activeInferenceCancelled else {
            loaded.cancelGeneration()
            throw CancellationError()
        }
        engine = loaded
        engineLoadHeadroom = loadHeadroom
        retirementTask = nil
        loadedModelID = descriptor.id
        return loaded
    }

    private func visualEngine() async throws -> LlamaInferenceEngine {
        let descriptor = OnDeviceAIVisionModelLibrary.descriptor
        guard ProcessInfo.processInfo.thermalState != .critical else {
            throw AIModelStoreError.thermalCritical
        }
        if let engine, loadedModelID == descriptor.id, loadedProjectorID == descriptor.id {
            return engine
        }
        guard await retireEngine() else { throw AIModelStoreError.resourceConstrained }
        try Task.checkCancellation()
        // This is a cold-load budget, not a second reservation for an engine
        // already resident. Keep the same 3 GB gate for every new visual load.
        guard Self.canSafelyLoadVision(availableMemoryBytes: Self.availableMemoryBytes) else {
            throw AIModelStoreError.resourceConstrained
        }
        _ = try await OnDeviceAIVisionModelLibrary.verifyReady()
        let loadHeadroom = Self.availableMemoryBytes
        let loaded = try await LlamaInferenceEngine.load(
            modelURL: descriptor.modelURL,
            tier: .efficient,
            projectorURL: descriptor.projectorURL,
            // The SHA-pinned Qwen2-VL projector has 32 vision blocks.
            visionEncoderLayerCount: 32,
            visionUsesGPU: visionUsesGPU
        )
        guard !activeInferenceCancelled else {
            loaded.cancelGeneration()
            throw CancellationError()
        }
        engine = loaded
        engineLoadHeadroom = loadHeadroom
        retirementTask = nil
        loadedModelID = descriptor.id
        loadedProjectorID = descriptor.id
        return loaded
    }

    private func runInference(
        selection: AIResourceSelection,
        prompt: String,
        maximumTokens: Int
    ) async throws -> AIResourceInferenceResult {
        let loadStarted = ContinuousClock.now
        let engine = try await engine(for: selection.model)
        let modelLoadSeconds = seconds(from: loadStarted, to: .now)
        let generation = try await engine.generateJSON(prompt: prompt, maximumTokens: maximumTokens)
        try Task.checkCancellation()
        guard !activeInferenceCancelled else { throw CancellationError() }
        try await modelStore.markUsed(id: selection.model.id)
        return AIResourceInferenceResult(
            generation: generation,
            selection: selection,
            modelLoadSeconds: modelLoadSeconds
        )
    }

    private func runVisualInference(
        prompt: String,
        imageData: Data,
        maximumTokens: Int
    ) async throws -> AIVisualResourceInferenceResult {
        let loadStarted = ContinuousClock.now
        let engine = try await visualEngine()
        let modelLoadSeconds = seconds(from: loadStarted, to: .now)
        let generation = try await engine.generateJSON(
            prompt: prompt,
            maximumTokens: maximumTokens,
            imageData: imageData
        )
        try Task.checkCancellation()
        guard !activeInferenceCancelled else { throw CancellationError() }
        return AIVisualResourceInferenceResult(
            generation: generation,
            model: OnDeviceAIVisionModelLibrary.descriptor,
            modelLoadSeconds: modelLoadSeconds
        )
    }

    private func fallbackSelection(after failed: AIResourceSelection) async -> AIResourceSelection? {
        let snapshot = await modelStore.snapshot()
        let availableMemory = Self.availableMemoryBytes
        guard let record = snapshot.records
            .filter({
                $0.state == .ready
                    && Self.rank($0.descriptor.tier) < Self.rank(failed.model.tier)
                    && Self.canSafelyLoad($0.descriptor.tier, availableMemoryBytes: availableMemory)
            })
            .sorted(by: { Self.rank($0.descriptor.tier) > Self.rank($1.descriptor.tier) })
            .first else { return nil }
        return AIResourceSelection(
            model: record.descriptor,
            downgradedFrom: failed.model,
            reason: .memoryPressure
        )
    }

    private func selectModel() async throws -> AIResourceSelection {
        let state = ProcessInfo.processInfo.thermalState
        if state == .critical { throw AIModelStoreError.thermalCritical }
        let storeSnapshot = await modelStore.snapshot()
        guard let active = storeSnapshot.activeRecord else {
            throw AIModelStoreError.modelNotInstalled
        }

        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let charging = await Self.isCharging
        let availableMemory = Self.availableMemoryBytes
        let mustUseSmaller: (AIResourceSelectionReason?) = {
            if lowPower && active.descriptor.tier == .enhanced { return .lowPowerMode }
            if state == .serious && active.descriptor.tier == .enhanced { return .thermalState }
            if storeSnapshot.useEnhancedOnlyWhileCharging,
               !charging,
               active.descriptor.tier == .enhanced { return .chargingPreference }
            if storeSnapshot.powerPreference == .preferBatteryLife,
               active.descriptor.tier != .efficient { return .lowPowerMode }
            if availableMemory > 0,
               availableMemory < Self.requiredMemoryHeadroomBytes(for: active.descriptor.tier) {
                return .memoryPressure
            }
            return nil
        }()

        guard let reason = mustUseSmaller else {
            return AIResourceSelection(model: active.descriptor, downgradedFrom: nil, reason: .userSelected)
        }
        let fallback = storeSnapshot.records
            .filter {
                $0.state == .ready
                    && Self.rank($0.descriptor.tier) < Self.rank(active.descriptor.tier)
                    && Self.canSafelyLoad($0.descriptor.tier, availableMemoryBytes: availableMemory)
            }
            .sorted { Self.rank($0.descriptor.tier) > Self.rank($1.descriptor.tier) }
            .first
        guard let fallback else { throw AIModelStoreError.resourceConstrained }
        return AIResourceSelection(model: fallback.descriptor, downgradedFrom: active.descriptor, reason: reason)
    }

    private func scheduleIdleUnload() {
        idleUnloadTask?.cancel()
        let duration = idleUnloadDuration
        idleUnloadTask = Task { [weak self] in
            do {
                try await Task.sleep(for: duration)
                guard !Task.isCancelled else { return }
                await self?.unloadIfIdle()
            } catch {
                // Cancellation is expected when another inference starts.
            }
        }
    }

    @MainActor private static var isCharging: Bool {
        UIDevice.current.isBatteryMonitoringEnabled = true
        return switch UIDevice.current.batteryState {
        case .charging, .full: true
        default: false
        }
    }

    private static func rank(_ tier: AIBenchmarkQualityTier) -> Int {
        switch tier {
        case .efficient: 0
        case .balanced: 1
        case .enhanced: 2
        }
    }

    /// Conservative headroom floors derived from the measured Phase 8C peak
    /// footprints, rounded up to leave room for SwiftUI, SwiftData, and the
    /// host process. A zero value means the platform did not expose a useful
    /// estimate, so selection remains governed by the other safety policies.
    static func requiredMemoryHeadroomBytes(for tier: AIBenchmarkQualityTier) -> UInt64 {
        switch tier {
        case .efficient: 3_500_000_000
        case .balanced: 5_500_000_000
        case .enhanced: 6_500_000_000
        }
    }

    private static func canSafelyLoad(
        _ tier: AIBenchmarkQualityTier,
        availableMemoryBytes: UInt64
    ) -> Bool {
        availableMemoryBytes == 0
            || availableMemoryBytes >= requiredMemoryHeadroomBytes(for: tier)
    }

    static func retirementHeadroomTarget(loadHeadroom: UInt64) -> UInt64 {
        let tolerance: UInt64 = 128 * 1_024 * 1_024
        return loadHeadroom > tolerance ? loadHeadroom - tolerance : 0
    }

    private static func canSafelyLoadVision(availableMemoryBytes: UInt64) -> Bool {
        // The Qwen2-VL 2B Q4 + Q8 projector bundle is deliberately given its
        // own floor. The zero case is the simulator/older platform path where
        // iOS did not expose a useful available-memory estimate.
        availableMemoryBytes == 0 || availableMemoryBytes >= 3_000_000_000
    }

    private static var availableMemoryBytes: UInt64 {
        UInt64(os_proc_available_memory())
    }
}

private extension Duration {
    nonisolated var secondsValue: Double {
        let components = components
        return Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
