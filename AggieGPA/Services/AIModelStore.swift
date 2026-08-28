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
    var lastUsedAt: Date?
    var verifiedAt: Date?

    var id: String { descriptor.id }
    var localURL: URL { AIModelStore.modelURL(for: descriptor) }
    var storedBytes: Int64 {
        guard let size = try? localURL.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return 0 }
        return Int64(size)
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
    /// Balanced is the current Phase 8C device-validation candidate based on
    /// the completed simulator matrix. It is not a shipped production default;
    /// the physical iPhone/iPad resource gate must pass before promotion.
    static let recommendedTier: AIBenchmarkQualityTier = .balanced

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
    private var activeDownloads: [String: AIModelDownloadDelegate] = [:]

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
        descriptors.contains { descriptor in
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
              let descriptor = descriptors.first(where: { $0.id == id }) else { return nil }
        return descriptor.modelName
    }

    func snapshot() -> AIModelStoreSnapshot {
        refreshStates()
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
        _ = try Self.validateArtifact(at: record.localURL, descriptor: record.descriptor)
        record.lastUsedAt = .now
        record.verifiedAt = .now
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
        refreshStates()
        if let ready = records[descriptor.id], ready.state == .ready {
            _ = try Self.validateArtifact(at: ready.localURL, descriptor: descriptor)
            if activeModelID == nil { activeModelID = descriptor.id; persistManifest() }
            return ready
        }

        try checkStorage(for: descriptor)
        var record = records[descriptor.id]!
        record.state = .downloading
        record.lastUsedAt = nil
        records[descriptor.id] = record
        persistManifest()

        let delegate = AIModelDownloadDelegate(progress: progress)
        activeDownloads[descriptor.id] = delegate
        defer { activeDownloads[descriptor.id] = nil }
        do {
            let downloaded = try await delegate.download(
                descriptor.downloadURL,
                resumeData: record.resumeData
            )
            defer { try? FileManager.default.removeItem(at: downloaded.location) }
            guard let http = downloaded.response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                throw AIModelStoreError.downloadFailed
            }
            try Task.checkCancellation()
            _ = try Self.validateArtifact(at: downloaded.location, descriptor: descriptor)
            try Self.atomicInstall(source: downloaded.location, descriptor: descriptor)
            record.state = .ready
            record.resumeData = nil
            record.verifiedAt = .now
            record.lastUsedAt = .now
            records[descriptor.id] = record
            if activeModelID == nil { activeModelID = descriptor.id }
            persistManifest()
            return record
        } catch let paused as AIModelDownloadPaused {
            record.state = .paused
            record.resumeData = paused.resumeData
            records[descriptor.id] = record
            persistManifest()
            throw paused
        } catch is CancellationError {
            record.state = .notInstalled
            record.resumeData = nil
            records[descriptor.id] = record
            persistManifest()
            throw CancellationError()
        } catch {
            record.state = .failed(error.localizedDescription)
            records[descriptor.id] = record
            persistManifest()
            throw error
        }
    }

    func pauseDownload(id: String) {
        activeDownloads[id]?.pause()
    }

    func cancelDownload(id: String) {
        activeDownloads[id]?.cancel()
        if var record = records[id], case .paused = record.state {
            record.state = .notInstalled
            record.resumeData = nil
            records[id] = record
            persistManifest()
        }
    }

    func remove(id: String) throws {
        guard var record = records[id] else { throw AIModelStoreError.unknownModel }
        if activeDownloads[id] != nil { throw AIModelStoreError.modelInUse }
        if FileManager.default.fileExists(atPath: record.localURL.path) {
            try FileManager.default.removeItem(at: record.localURL)
        }
        record.state = .notInstalled
        record.resumeData = nil
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
        records[descriptor.id] = record
        if activeModelID == nil { activeModelID = descriptor.id }
        persistManifest()
        return record
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
        let staging = rootURL.appending(path: ".(descriptor.id).(UUID().uuidString).partial", directoryHint: .notDirectory)
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

private struct AIModelDownloadPaused: Error, Sendable {
    let resumeData: Data?
}

private final class AIModelDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let progress: @Sendable (ModelDownloadProgress) -> Void
    private var continuation: CheckedContinuation<(location: URL, response: URLResponse), any Error>?
    private var task: URLSessionDownloadTask?
    private var finished = false
    private var paused = false

    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.easonzhou.aggiegpa.model-download-v2"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    init(progress: @escaping @Sendable (ModelDownloadProgress) -> Void) {
        self.progress = progress
    }

    func download(_ url: URL, resumeData: Data?) async throws -> (location: URL, response: URLResponse) {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                self.continuation = continuation
                let configuration = URLSessionConfiguration.ephemeral
                configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                configuration.waitsForConnectivity = true
                configuration.timeoutIntervalForRequest = 120
                configuration.timeoutIntervalForResource = 60 * 60
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
                self.task = resumeData.map(session.downloadTask(withResumeData:)) ?? session.downloadTask(with: url)
                self.task?.resume()
                lock.unlock()
            }
        } onCancel: {
            self.cancel()
        }
    }

    func pause() {
        lock.lock()
        paused = true
        let task = self.task
        lock.unlock()
        task?.cancel(byProducingResumeData: { [weak self] data in
            self?.finish(error: AIModelDownloadPaused(resumeData: data))
        })
    }

    func cancel() {
        lock.lock()
        let task = self.task
        lock.unlock()
        task?.cancel()
        finish(error: CancellationError())
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        progress(.init(
            receivedBytes: totalBytesWritten,
            expectedBytes: totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : ModelDownloadProgress.starting.expectedBytes
        ))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let response = downloadTask.response else {
            finish(error: AIModelStoreError.downloadFailed)
            return
        }
        do {
            let stable = FileManager.default.temporaryDirectory
                .appending(path: "(UUID().uuidString).gguf", directoryHint: .notDirectory)
            try FileManager.default.copyItem(at: location, to: stable)
            finish(value: (stable, response))
        } catch {
            finish(error: error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let error else { return }
        lock.lock()
        let shouldIgnore = finished || paused
        lock.unlock()
        if !shouldIgnore { finish(error: error) }
    }

    private func finish(value: (URL, URLResponse)) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: (value.0, value.1))
    }

    private func finish(error: any Error) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(throwing: error)
    }
}
