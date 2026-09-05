import CryptoKit
import Foundation

/// User-facing quality and power choices are kept separate from the
/// benchmark catalog. A downloaded model is never implicitly treated as the
/// production default; the user explicitly activates it.
nonisolated enum AIPowerPreference: String, Codable, CaseIterable, Sendable, Identifiable {
    case preferBatteryLife
    case balanced
    case preferQuality

    var id: String { rawValue }
}

nonisolated enum AIModelInstallState: Codable, Equatable, Sendable {
    case notInstalled
    case downloading
    case paused
    case ready
    case failed(String)
}

nonisolated struct AIModelDescriptor: Codable, Equatable, Hashable, Sendable, Identifiable {
    let id: String
    let tier: AIBenchmarkQualityTier
    let modelName: String
    let quantization: String
    let parameterBand: String
    let repository: String
    let revision: String
    let license: String
    let licenseReference: String
    let sourceReference: String
    let artifactFileName: String
    let artifactSHA256: String
    let artifactBytes: Int64

    var downloadURL: URL { URL(string: sourceReference)! }

    var storageLabel: String {
        ByteCountFormatter.string(fromByteCount: artifactBytes, countStyle: .file)
    }

    init(candidate: AIBenchmarkCandidate) {
        self.id = candidate.id
        self.tier = candidate.tier
        self.modelName = candidate.modelName
        self.quantization = candidate.quantization
        self.parameterBand = candidate.parameterBand
        self.repository = candidate.repository
        self.revision = candidate.revision
        self.license = candidate.modelLicense
        self.licenseReference = candidate.licenseReference
        self.sourceReference = candidate.sourceReference
        self.artifactFileName = candidate.artifactFileName ?? "(candidate.id).gguf"
        self.artifactSHA256 = candidate.artifactSHA256 ?? ""
        self.artifactBytes = candidate.artifactBytes ?? 0
    }
}

nonisolated struct AIModelRecord: Codable, Equatable, Sendable, Identifiable {
    let descriptor: AIModelDescriptor
    var state: AIModelInstallState
    var resumeData: Data?
    /// The last durable progress checkpoint for a background download. These
    /// values are optional so manifests written by older builds continue to
    /// decode without a migration step.
    var receivedBytes: Int64?
    var expectedBytes: Int64?
    var lastUsedAt: Date?
    var verifiedAt: Date?

    var id: String { descriptor.id }
    var localURL: URL { AIModelStore.modelURL(for: descriptor) }
    var storedBytes: Int64 {
        guard let size = try? localURL.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return 0 }
        return Int64(size)
    }

    var downloadProgress: ModelDownloadProgress? {
        guard state == .downloading || state == .paused else { return nil }
        guard receivedBytes != nil || expectedBytes != nil else { return nil }
        return ModelDownloadProgress(
            receivedBytes: max(0, receivedBytes ?? 0),
            expectedBytes: max(0, expectedBytes ?? descriptor.artifactBytes)
        )
    }
}

nonisolated struct AIModelStoreSnapshot: Equatable, Sendable {
    let records: [AIModelRecord]
    let activeModelID: String?
    let recommendedTier: AIBenchmarkQualityTier
    let powerPreference: AIPowerPreference
    let useEnhancedOnlyWhileCharging: Bool
    let storageUsedBytes: Int64
    let storageBudgetBytes: Int64

    var activeRecord: AIModelRecord? {
        records.first { $0.id == activeModelID && $0.state == .ready }
    }
}

nonisolated enum AIModelStoreError: LocalizedError, Equatable, Sendable {
    case unknownModel
    case invalidModel
    case checksumMismatch
    case insufficientStorage(required: Int64, available: Int64)
    case modelNotInstalled
    case modelInUse
    case downloadFailed
    case importUnsupported
    case runtimeUnavailable
    case thermalCritical
    case resourceConstrained

    var errorDescription: String? {
        switch self {
        case .unknownModel: "This model is not supported by Aggie GPA."
        case .invalidModel: "The selected GGUF file is incomplete or invalid."
        case .checksumMismatch: "The model integrity check failed. Download it again."
        case .insufficientStorage: "There is not enough storage for this model."
        case .modelNotInstalled: "Download a supported on-device model before analyzing."
        case .modelInUse: "Stop the current analysis before removing this model."
        case .downloadFailed: "The model download could not be completed."
        case .importUnsupported: "This GGUF is not one of the verified Aggie GPA models."
        case .runtimeUnavailable: "The local model runtime is not linked in this build."
        case .thermalCritical: "Analysis stopped because the device is too hot."
        case .resourceConstrained: "The device cannot safely load the selected model right now."
        }
    }

    func message(locale: Locale) -> String {
        switch self {
        case .insufficientStorage(let required, let available):
            return String(
                format: AppLocalization.string("Need %@, but only %@ is available for local models.", locale: locale),
                ByteCountFormatter.string(fromByteCount: required, countStyle: .file),
                ByteCountFormatter.string(fromByteCount: available, countStyle: .file)
            )
        default:
            return AppLocalization.string(errorDescription ?? "The local model could not be used.", locale: locale)
        }
    }
}

/// The only service that owns model files. It stores a small manifest beside
/// the files, excludes both from backup, verifies exact bytes and SHA-256, and
/// uses atomic replacement so a cancelled or interrupted download can never
/// become the active model.
actor AIModelStore {
    static let shared = AIModelStore()
    static let storageBudgetBytes: Int64 = 10_000_000_000
    /// The 4B candidate remains in the catalog for migration/removal, but a
    /// physical iPad Jetsam means it cannot be selected by this production
    /// build. Efficient is the strongest tier that remains inside the safe
    /// release policy until a later build passes repeated iPhone+iPad gates.
    static let recommendedTier: AIBenchmarkQualityTier = .efficient

    private struct Manifest: Codable {
        var records: [String: AIModelRecord]
        var activeModelID: String?
        var recommendedTier: AIBenchmarkQualityTier
        var powerPreference: AIPowerPreference
        var useEnhancedOnlyWhileCharging: Bool
    }

    private(set) var records: [String: AIModelRecord]
    private(set) var activeModelID: String?
    private(set) var powerPreference: AIPowerPreference
    private(set) var useEnhancedOnlyWhileCharging: Bool
    private var activeDownloadTasks: [String: Task<AIModelRecord, Error>] = [:]
    private var lastProgressPersistence: [String: (date: Date, receivedBytes: Int64)] = [:]
    private var didReconcileStagingArtifacts = false

    init() {
        let manifest = Self.loadManifest()
        self.records = manifest.records
        self.activeModelID = manifest.activeModelID
        self.powerPreference = manifest.powerPreference
        self.useEnhancedOnlyWhileCharging = manifest.useEnhancedOnlyWhileCharging
        for descriptor in Self.descriptors where records[descriptor.id] == nil {
            records[descriptor.id] = AIModelRecord(
                descriptor: descriptor,
                state: .notInstalled,
                resumeData: nil,
                receivedBytes: nil,
                expectedBytes: nil,
                lastUsedAt: nil,
                verifiedAt: nil
            )
        }
        // Reconciliation and persistence happen on the first actor-isolated
        // snapshot/download call. Actor initializers cannot invoke isolated
        // instance methods before initialization completes.
    }

    static let descriptors: [AIModelDescriptor] =
        AIBenchmarkCandidateCatalog.candidates.map(AIModelDescriptor.init(candidate:))

    static var recommendedDescriptor: AIModelDescriptor {
        descriptors.first { $0.tier == recommendedTier } ?? descriptors[0]
    }

    nonisolated static func isProductionSelectable(_ descriptor: AIModelDescriptor) -> Bool {
        descriptor.id == recommendedDescriptor.id
    }

    nonisolated static var rootURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base
            .appending(path: "OnDeviceModels", directoryHint: .isDirectory)
            .appending(path: "v2", directoryHint: .isDirectory)
    }

    nonisolated static var manifestURL: URL {
        rootURL.appending(path: "manifest.json", directoryHint: .notDirectory)
    }

    nonisolated static func modelURL(for descriptor: AIModelDescriptor) -> URL {
        rootURL.appending(path: descriptor.artifactFileName, directoryHint: .notDirectory)
    }

    nonisolated static func modelURL(for id: String) -> URL? {
        descriptors.first { $0.id == id }.map(modelURL(for:))
    }

    nonisolated static func quickAvailability() -> Bool {
        descriptors.filter(isProductionSelectable).contains { descriptor in
            let url = modelURL(for: descriptor)
            guard FileManager.default.fileExists(atPath: url.path) else { return false }
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return false }
            return Int64(size) == descriptor.artifactBytes
        }
    }

    nonisolated static func activeModelNameSnapshot() -> String? {
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
              let id = manifest.activeModelID,
              let descriptor = descriptors.first(where: { $0.id == id }),
              isProductionSelectable(descriptor) else { return nil }
        return descriptor.modelName
    }

    func snapshot() -> AIModelStoreSnapshot {
        refreshStates()
        reconcileProductionSelection()
        persistManifest()
        return AIModelStoreSnapshot(
            records: records.values.sorted { $0.descriptor.tier.rawValue < $1.descriptor.tier.rawValue },
            activeModelID: activeModelID,
            recommendedTier: Self.recommendedTier,
            powerPreference: powerPreference,
            useEnhancedOnlyWhileCharging: useEnhancedOnlyWhileCharging,
            storageUsedBytes: storageUsedBytes,
            storageBudgetBytes: Self.storageBudgetBytes
        )
    }

    func setPowerPreference(_ preference: AIPowerPreference) {
        powerPreference = preference
        persistManifest()
    }

    func setUseEnhancedOnlyWhileCharging(_ enabled: Bool) {
        useEnhancedOnlyWhileCharging = enabled
        persistManifest()
    }

    func setActiveModel(id: String) async throws -> AIModelRecord {
        guard let record = records[id] else { throw AIModelStoreError.unknownModel }
        guard Self.isProductionSelectable(record.descriptor) else {
            throw AIModelStoreError.resourceConstrained
        }
        guard record.state == .ready else { throw AIModelStoreError.modelNotInstalled }
        _ = try Self.validateArtifact(at: record.localURL, descriptor: record.descriptor)
        activeModelID = id
        records[id]?.lastUsedAt = .now
        records[id]?.verifiedAt = .now
        persistManifest()
        return records[id]!
    }

    /// Verifies a ready artifact immediately before a new runtime engine is
    /// created. Navigation and model-library snapshots remain lightweight;
    /// only an explicit inference load pays the full SHA-256 cost.
    func verifyReadyModel(id: String) throws -> AIModelRecord {
        refreshStates()
        guard var record = records[id], record.state == .ready else {
            throw AIModelStoreError.modelNotInstalled
        }
        do {
            _ = try Self.validateArtifact(at: record.localURL, descriptor: record.descriptor)
            record.verifiedAt = .now
            records[id] = record
            persistManifest()
            return record
        } catch {
            record.state = .failed(error.localizedDescription)
            record.verifiedAt = nil
            record.lastUsedAt = nil
            records[id] = record
            if activeModelID == id { activeModelID = nil }
            persistManifest()
            throw error
        }
    }

    func markUsed(id: String) throws {
        guard var record = records[id], record.state == .ready else { throw AIModelStoreError.modelNotInstalled }
        guard FileManager.default.fileExists(atPath: record.localURL.path) else {
            throw AIModelStoreError.modelNotInstalled
        }
        record.lastUsedAt = .now
        records[id] = record
        persistManifest()
    }

    func prepareRecommended(
        progress: @escaping @Sendable (ModelDownloadProgress) -> Void = { _ in }
    ) async throws -> AIModelRecord {
        try await download(descriptor: Self.recommendedDescriptor, progress: progress)
    }

    func download(
        descriptor: AIModelDescriptor,
        progress: @escaping @Sendable (ModelDownloadProgress) -> Void = { _ in }
    ) async throws -> AIModelRecord {
        guard Self.descriptors.contains(descriptor) else { throw AIModelStoreError.unknownModel }
        if let active = activeDownloadTasks[descriptor.id] {
            // The network operation is deliberately independent from the
            // caller's task. A view disappearing or the app being suspended
            // must not cancel the durable URLSession download.
            return try await active.value
        }

        let task = Task { [descriptor, progress] in
            try await self.performDownload(descriptor: descriptor, progress: progress)
        }
        activeDownloadTasks[descriptor.id] = task
        do {
            let result = try await task.value
            activeDownloadTasks[descriptor.id] = nil
            return result
        } catch {
            activeDownloadTasks[descriptor.id] = nil
            throw error
        }
    }

    func pauseDownload(id: String) {
        ModelDownloadCoordinator.shared.pause(descriptorID: id)
    }

    func cancelDownload(id: String) {
        ModelDownloadCoordinator.shared.cancel(descriptorID: id)
        if var record = records[id], record.state == .downloading || record.state == .paused {
            record.state = .notInstalled
            record.resumeData = nil
            record.receivedBytes = nil
            record.expectedBytes = nil
            records[id] = record
            persistManifest()
        }
    }

    /// Reconnects the actor to a background URLSession task after a cold launch.
    /// A missing task is restarted with the last resume data, if any. The
    /// final file is still validated and atomically promoted before it can be
    /// reported as ready.
    func resumePersistedDownloadsIfNeeded() {
        reconcileStagingArtifactsIfNeeded()
        refreshStates()
        // A pre-release build could have left an unsafe 4B/8B task in the
        // manifest. Cancel it before the background session can restore it;
        // restricted models must never resume implicitly.
        let restrictedPending = records.values.filter {
            $0.state == .downloading && !Self.isProductionSelectable($0.descriptor)
        }
        for restricted in restrictedPending {
            ModelDownloadCoordinator.shared.cancel(descriptorID: restricted.id)
            guard var record = records[restricted.id] else { continue }
            record.state = .notInstalled
            record.resumeData = nil
            record.receivedBytes = nil
            record.expectedBytes = nil
            records[restricted.id] = record
        }

        let pending = records.values
            .filter { $0.state == .downloading && Self.isProductionSelectable($0.descriptor) }
            .sorted { $0.descriptor.artifactBytes < $1.descriptor.artifactBytes }
        guard let record = pending.first else { return }

        for extra in pending.dropFirst() {
            guard var extraRecord = records[extra.id] else { continue }
            extraRecord.state = .paused
            extraRecord.resumeData = nil
            records[extra.id] = extraRecord
        }
        persistManifest()

        ModelDownloadCoordinator.shared.recover(
            descriptorID: record.id,
            modelName: record.descriptor.modelName,
            url: record.descriptor.downloadURL,
            expectedBytes: record.expectedBytes ?? record.descriptor.artifactBytes,
            receivedBytes: record.receivedBytes ?? 0,
            resumeData: record.resumeData
        )
    }

    /// Called by the download coordinator for durable progress checkpoints.
    /// Manifest writes are throttled so a fast server cannot turn every
    /// callback into synchronous file-system work.
    func recordDownloadProgress(id: String, progress: ModelDownloadProgress, forcePersist: Bool = false) {
        guard var record = records[id], record.state == .downloading || record.state == .paused else { return }
        record.receivedBytes = max(0, progress.receivedBytes)
        record.expectedBytes = max(0, progress.expectedBytes)
        records[id] = record

        let now = Date()
        let previous = lastProgressPersistence[id]
        let shouldPersist = forcePersist
            || previous == nil
            || now.timeIntervalSince(previous?.date ?? .distantPast) >= 1
            || progress.receivedBytes - (previous?.receivedBytes ?? 0) >= 8 * 1_024 * 1_024
        guard shouldPersist else { return }
        lastProgressPersistence[id] = (now, progress.receivedBytes)
        persistManifest()
    }

    /// Completes a download received while no caller was waiting on it (for
    /// example after the app was relaunched by a background URLSession event).
    func completeBackgroundDownload(id: String, location: URL, response: URLResponse) {
        defer {
            try? FileManager.default.removeItem(at: location)
            ModelDownloadCoordinator.shared.backgroundFinalizationCompleted(descriptorID: id)
        }
        guard let record = records[id], record.state == .downloading else { return }

        do {
            _ = try finalizeDownloadedArtifact(
                location: location,
                response: response,
                descriptor: record.descriptor
            )
        } catch {
            failRecord(id: id, error: error)
        }
    }

    /// Records a terminal background failure when there is no foreground
    /// caller to receive the error. Resume data is preserved whenever the
    /// system supplied it.
    func failBackgroundDownload(id: String, resumeData: Data?, message: String) {
        guard var record = records[id], record.state == .downloading else { return }
        if let resumeData, !resumeData.isEmpty {
            record.state = .paused
            record.resumeData = resumeData
        } else {
            record.state = .failed(message)
            record.resumeData = nil
        }
        records[id] = record
        persistManifest()
        Task { @MainActor in
            ModelDownloadActivityController.shared.finish(
                downloadID: id,
                outcome: resumeData?.isEmpty == false ? .paused : .failed
            )
        }
    }

    func remove(id: String) throws {
        guard var record = records[id] else { throw AIModelStoreError.unknownModel }
        if record.state == .downloading { throw AIModelStoreError.modelInUse }
        if FileManager.default.fileExists(atPath: record.localURL.path) {
            try FileManager.default.removeItem(at: record.localURL)
        }
        record.state = .notInstalled
        record.resumeData = nil
        record.receivedBytes = nil
        record.expectedBytes = nil
        record.verifiedAt = nil
        record.lastUsedAt = nil
        records[id] = record
        if activeModelID == id { activeModelID = nil }
        persistManifest()
    }

    func installImportedModel(from source: URL) throws -> AIModelRecord {
        let hasScope = source.startAccessingSecurityScopedResource()
        defer { if hasScope { source.stopAccessingSecurityScopedResource() } }
        guard let descriptor = Self.descriptors.first(where: { descriptor in
            (try? Self.validateArtifact(at: source, descriptor: descriptor)) != nil
        }) else { throw AIModelStoreError.importUnsupported }
        try checkStorage(for: descriptor)
        try Self.atomicInstall(source: source, descriptor: descriptor)
        var record = records[descriptor.id]!
        record.state = .ready
        record.verifiedAt = .now
        record.lastUsedAt = .now
        record.resumeData = nil
        record.receivedBytes = nil
        record.expectedBytes = nil
        records[descriptor.id] = record
        if activeModelID == nil, Self.isProductionSelectable(descriptor) {
            activeModelID = descriptor.id
        }
        persistManifest()
        return record
    }

    private func performDownload(
        descriptor: AIModelDescriptor,
        progress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws -> AIModelRecord {
        reconcileStagingArtifactsIfNeeded()
        refreshStates()
        if let ready = records[descriptor.id], ready.state == .ready {
            _ = try Self.validateArtifact(at: ready.localURL, descriptor: descriptor)
            if activeModelID == nil, Self.isProductionSelectable(descriptor) {
                activeModelID = descriptor.id
                persistManifest()
            }
            return ready
        }

        try checkStorage(for: descriptor)
        var record = records[descriptor.id]!
        let resumeData = record.resumeData
        record.state = .downloading
        record.lastUsedAt = nil
        record.receivedBytes = record.receivedBytes ?? 0
        record.expectedBytes = descriptor.artifactBytes
        records[descriptor.id] = record
        lastProgressPersistence[descriptor.id] = nil
        persistManifest()

        let initialProgress = record.downloadProgress ?? .starting
        progress(initialProgress)
        do {
            let downloaded = try await ModelDownloadCoordinator.shared.download(
                descriptorID: descriptor.id,
                modelName: descriptor.modelName,
                url: descriptor.downloadURL,
                expectedBytes: descriptor.artifactBytes,
                receivedBytes: record.receivedBytes ?? 0,
                resumeData: resumeData,
                progress: progress
            )
            defer {
                try? FileManager.default.removeItem(at: downloaded.location)
                ModelDownloadCoordinator.shared.backgroundFinalizationCompleted(descriptorID: descriptor.id)
            }
            guard records[descriptor.id]?.state == .downloading else {
                throw CancellationError()
            }
            return try finalizeDownloadedArtifact(
                location: downloaded.location,
                response: downloaded.response,
                descriptor: descriptor
            )
        } catch let paused as ModelDownloadPaused {
            guard var current = records[descriptor.id], current.state != .notInstalled else {
                throw paused
            }
            current.state = .paused
            current.resumeData = paused.resumeData
            records[descriptor.id] = current
            recordDownloadProgress(
                id: descriptor.id,
                progress: current.downloadProgress ?? initialProgress,
                forcePersist: true
            )
            throw paused
        } catch let interrupted as ModelDownloadInterrupted {
            guard var current = records[descriptor.id], current.state != .notInstalled else {
                throw interrupted
            }
            if let data = interrupted.resumeData, !data.isEmpty {
                current.state = .paused
                current.resumeData = data
            } else {
                current.state = .failed(interrupted.message)
                current.resumeData = nil
            }
            records[descriptor.id] = current
            persistManifest()
            Task { @MainActor in
                ModelDownloadActivityController.shared.finish(
                    downloadID: descriptor.id,
                    outcome: interrupted.resumeData?.isEmpty == false ? .paused : .failed
                )
            }
            throw interrupted
        } catch is CancellationError {
            if var current = records[descriptor.id], current.state != .notInstalled {
                current.state = .notInstalled
                current.resumeData = nil
                current.receivedBytes = nil
                current.expectedBytes = nil
                records[descriptor.id] = current
                persistManifest()
            }
            throw CancellationError()
        } catch {
            failRecord(id: descriptor.id, error: error)
            throw error
        }
    }

    private func finalizeDownloadedArtifact(
        location: URL,
        response: URLResponse,
        descriptor: AIModelDescriptor
    ) throws -> AIModelRecord {
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw AIModelStoreError.downloadFailed
        }
        _ = try Self.validateArtifact(at: location, descriptor: descriptor)
        try Self.atomicInstall(source: location, descriptor: descriptor)

        guard var record = records[descriptor.id], record.state == .downloading else {
            throw CancellationError()
        }
        record.state = .ready
        record.resumeData = nil
        record.receivedBytes = nil
        record.expectedBytes = nil
        record.verifiedAt = .now
        record.lastUsedAt = .now
        records[descriptor.id] = record
        if activeModelID == nil, Self.isProductionSelectable(descriptor) {
            activeModelID = descriptor.id
        }
        lastProgressPersistence[descriptor.id] = nil
        persistManifest()
        Task { @MainActor in
            ModelDownloadActivityController.shared.finish(downloadID: descriptor.id, outcome: .success)
        }
        return record
    }

    private func failRecord(id: String, error: any Error) {
        guard var record = records[id], record.state == .downloading else { return }
        record.state = .failed(error.localizedDescription)
        record.resumeData = nil
        records[id] = record
        lastProgressPersistence[id] = nil
        persistManifest()
        Task { @MainActor in
            ModelDownloadActivityController.shared.finish(downloadID: id, outcome: .failed)
        }
    }

    private func checkStorage(for descriptor: AIModelDescriptor) throws {
        let current = storageUsedBytes - (records[descriptor.id]?.storedBytes ?? 0)
        let required = current + descriptor.artifactBytes
        guard required <= Self.storageBudgetBytes else {
            throw AIModelStoreError.insufficientStorage(required: required, available: Self.storageBudgetBytes)
        }
        let values = try Self.rootURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let available = values.volumeAvailableCapacityForImportantUsage,
           available < descriptor.artifactBytes {
            throw AIModelStoreError.insufficientStorage(required: descriptor.artifactBytes, available: available)
        }
    }

    private var storageUsedBytes: Int64 {
        records.values.reduce(into: Int64(0)) { total, record in
            guard record.state == .ready else { return }
            total += record.storedBytes
        }
    }

    private func refreshStates() {
        for (id, var record) in records {
            if record.state == .ready,
               !FileManager.default.fileExists(atPath: record.localURL.path) {
                record.state = .notInstalled
                record.verifiedAt = nil
                record.lastUsedAt = nil
                records[id] = record
            }
        }
    }

    /// Repairs the staging file left by the pre-release installer. That
    /// installer used a literal filename, so a process termination after the
    /// copy could leave a complete model beside a manifest still marked as
    /// downloading. Only a file that passes the descriptor's exact size,
    /// magic, and SHA-256 checks can be promoted; every other partial is
    /// removed and the persisted download path is allowed to resume safely.
    private func reconcileStagingArtifactsIfNeeded() {
        guard !didReconcileStagingArtifacts else { return }
        didReconcileStagingArtifacts = true

        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: Self.rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: []
        ) else { return }

        var manifestChanged = false
        for url in urls where url.pathExtension == "partial" {
            guard let descriptor = Self.descriptors.first(where: { descriptor in
                (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) == descriptor.artifactBytes
            }) else {
                try? FileManager.default.removeItem(at: url)
                continue
            }

            do {
                _ = try Self.validateArtifact(at: url, descriptor: descriptor)
                let destination = Self.modelURL(for: descriptor)
                if FileManager.default.fileExists(atPath: destination.path) {
                    do {
                        _ = try Self.validateArtifact(at: destination, descriptor: descriptor)
                        try FileManager.default.removeItem(at: url)
                        continue
                    } catch {
                        try? FileManager.default.removeItem(at: destination)
                    }
                }
                try FileManager.default.moveItem(at: url, to: destination)
                Self.excludeFromBackup(destination)

                guard var record = records[descriptor.id] else { continue }
                record.state = .ready
                record.resumeData = nil
                record.receivedBytes = nil
                record.expectedBytes = nil
                record.verifiedAt = .now
                record.lastUsedAt = .now
                records[descriptor.id] = record
                if activeModelID == nil, Self.isProductionSelectable(descriptor) {
                    activeModelID = descriptor.id
                }
                manifestChanged = true
            } catch {
                try? FileManager.default.removeItem(at: url)
            }
        }

        if manifestChanged {
            persistManifest()
        }
    }

    private func reconcileProductionSelection() {
        if let activeModelID,
           let active = records[activeModelID],
           active.state == .ready,
           Self.isProductionSelectable(active.descriptor) {
            return
        }
        activeModelID = records.values
            .filter { $0.state == .ready && Self.isProductionSelectable($0.descriptor) }
            .sorted { $0.descriptor.artifactBytes > $1.descriptor.artifactBytes }
            .first?.id
    }

    private func persistManifest() {
        let manifest = Manifest(
            records: records,
            activeModelID: activeModelID,
            recommendedTier: Self.recommendedTier,
            powerPreference: powerPreference,
            useEnhancedOnlyWhileCharging: useEnhancedOnlyWhileCharging
        )
        do {
            try FileManager.default.createDirectory(at: Self.rootURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(manifest).write(to: Self.manifestURL, options: .atomic)
            Self.excludeFromBackup(Self.rootURL)
            Self.excludeFromBackup(Self.manifestURL)
        } catch {
            // A manifest write must never crash navigation. The next snapshot
            // will reconcile the files and report the model as unverified.
        }
    }

    private static func loadManifest() -> Manifest {
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else {
            return Manifest(
                records: [:],
                activeModelID: nil,
                recommendedTier: recommendedTier,
                powerPreference: .balanced,
                useEnhancedOnlyWhileCharging: true
            )
        }
        return manifest
    }

    private static func excludeFromBackup(_ url: URL) {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(values)
    }

    @discardableResult
    nonisolated static func validateArtifact(at url: URL, descriptor: AIModelDescriptor) throws -> String {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize, Int64(size) == descriptor.artifactBytes else {
            throw AIModelStoreError.invalidModel
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard try handle.read(upToCount: 4) == Data("GGUF".utf8) else {
            throw AIModelStoreError.invalidModel
        }
        try handle.seek(toOffset: 0)
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        let hash = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard hash.caseInsensitiveCompare(descriptor.artifactSHA256) == .orderedSame else {
            throw AIModelStoreError.checksumMismatch
        }
        return hash
    }

    private static func atomicInstall(source: URL, descriptor: AIModelDescriptor) throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let destination = modelURL(for: descriptor)
        let staging = rootURL.appending(path: ".\(descriptor.id).\(UUID().uuidString).partial", directoryHint: .notDirectory)
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.copyItem(at: source, to: staging)
        _ = try validateArtifact(at: staging, descriptor: descriptor)
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging)
        } else {
            try FileManager.default.moveItem(at: staging, to: destination)
        }
        excludeFromBackup(destination)
    }
}

/// Runtime-neutral facade used by views and import flows. It deliberately does
/// not expose llama.cpp types or model URLs to SwiftUI.
nonisolated enum OnDeviceAIModelLibrary {
    static var recommendedDescriptor: AIModelDescriptor { AIModelStore.recommendedDescriptor }
    static var activeModelName: String { AIModelStore.activeModelNameSnapshot() ?? recommendedDescriptor.modelName }

    static func snapshot() async -> AIModelStoreSnapshot {
        await AIModelStore.shared.snapshot()
    }

    static func prepareRecommended(
        progress: @escaping @Sendable (ModelDownloadProgress) -> Void = { _ in }
    ) async throws -> AIModelRecord {
        try await AIModelStore.shared.prepareRecommended(progress: progress)
    }

    static func resumePersistedDownloadsIfNeeded() async {
        await AIModelStore.shared.resumePersistedDownloadsIfNeeded()
    }

    static func pauseRecommendedDownload() async {
        await AIModelStore.shared.pauseDownload(id: recommendedDescriptor.id)
    }

    static func cancelRecommendedDownload() async {
        await AIModelStore.shared.cancelDownload(id: recommendedDescriptor.id)
    }

    static func importModel(from source: URL) async throws -> AIModelRecord {
        try await AIModelStore.shared.installImportedModel(from: source)
    }

    static func remove(id: String) async throws {
        await AIResourceManager.shared.cancelIfUsingModel(id: id)
        try await AIModelStore.shared.remove(id: id)
    }

    static func setActiveModel(id: String) async throws -> AIModelRecord {
        await AIResourceManager.shared.cancelCurrentInference()
        return try await AIModelStore.shared.setActiveModel(id: id)
    }
}
