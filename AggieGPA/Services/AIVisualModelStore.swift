import CryptoKit
import Foundation

/// The vision model is a complete two-file bundle. The language weights and
/// multimodal projector are versioned together so a half-downloaded projector
/// can never be paired with a different model.
nonisolated struct AIVisualModelArtifact: Codable, Equatable, Hashable, Sendable {
    let fileName: String
    let sourceReference: String
    let sha256: String
    let bytes: Int64

    var sourceURL: URL { URL(string: sourceReference)! }
}

nonisolated struct AIVisualModelDescriptor: Codable, Equatable, Hashable, Sendable, Identifiable {
    let id: String
    let modelName: String
    let quantization: String
    let parameterBand: String
    let repository: String
    let revision: String
    let license: String
    let licenseReference: String
    let model: AIVisualModelArtifact
    let projector: AIVisualModelArtifact

    var modelURL: URL {
        AIVisualModelStore.rootURL.appending(path: model.fileName, directoryHint: .notDirectory)
    }

    var projectorURL: URL {
        AIVisualModelStore.rootURL.appending(path: projector.fileName, directoryHint: .notDirectory)
    }

    var totalBytes: Int64 { model.bytes + projector.bytes }

    var storageLabel: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    func artifact(_ kind: AIVisualArtifactKind) -> AIVisualModelArtifact {
        switch kind {
        case .model: model
        case .projector: projector
        }
    }

    func localURL(for kind: AIVisualArtifactKind) -> URL {
        switch kind {
        case .model: modelURL
        case .projector: projectorURL
        }
    }
}

nonisolated enum AIVisualArtifactKind: String, Codable, Equatable, Sendable {
    case model
    case projector
}

nonisolated enum AIVisualModelInstallState: Codable, Equatable, Sendable {
    case notInstalled
    case downloading
    case paused
    case ready
    case failed(String)
}

nonisolated struct AIVisualModelProgress: Equatable, Sendable {
    let artifact: AIVisualArtifactKind
    let receivedBytes: Int64
    let expectedBytes: Int64
    let totalReceivedBytes: Int64
    let totalExpectedBytes: Int64

    var fraction: Double {
        guard totalExpectedBytes > 0 else { return 0 }
        return min(1, max(0, Double(totalReceivedBytes) / Double(totalExpectedBytes)))
    }

    var asDownloadProgress: ModelDownloadProgress {
        ModelDownloadProgress(
            receivedBytes: totalReceivedBytes,
            expectedBytes: totalExpectedBytes
        )
    }

    static func starting(for descriptor: AIVisualModelDescriptor) -> Self {
        Self(
            artifact: .model,
            receivedBytes: 0,
            expectedBytes: descriptor.model.bytes,
            totalReceivedBytes: 0,
            totalExpectedBytes: descriptor.totalBytes
        )
    }

    static func complete(for descriptor: AIVisualModelDescriptor) -> Self {
        Self(
            artifact: .projector,
            receivedBytes: descriptor.projector.bytes,
            expectedBytes: descriptor.projector.bytes,
            totalReceivedBytes: descriptor.totalBytes,
            totalExpectedBytes: descriptor.totalBytes
        )
    }
}

nonisolated struct AIVisualModelRecord: Codable, Equatable, Sendable, Identifiable {
    let descriptor: AIVisualModelDescriptor
    var state: AIVisualModelInstallState
    var activeArtifact: AIVisualArtifactKind?
    var modelResumeData: Data?
    var projectorResumeData: Data?
    var modelReceivedBytes: Int64
    var projectorReceivedBytes: Int64
    var verifiedAt: Date?

    var id: String { descriptor.id }

    var storedBytes: Int64 {
        let modelBytes = (try? descriptor.modelURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        let projectorBytes = (try? descriptor.projectorURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        return modelBytes + projectorBytes
    }

    var progress: AIVisualModelProgress? {
        guard state == .downloading || state == .paused else { return nil }
        let kind = activeArtifact ?? .model
        let received = kind == .model ? modelReceivedBytes : projectorReceivedBytes
        let expected = descriptor.artifact(kind).bytes
        return AIVisualModelProgress(
            artifact: kind,
            receivedBytes: max(0, received),
            expectedBytes: max(0, expected),
            totalReceivedBytes: max(0, modelReceivedBytes) + max(0, projectorReceivedBytes),
            totalExpectedBytes: descriptor.totalBytes
        )
    }
}

nonisolated struct AIVisualModelStoreSnapshot: Equatable, Sendable {
    let record: AIVisualModelRecord
    let storageUsedBytes: Int64
    var hasLocalBundle: Bool = false

    var isReady: Bool { record.state == .ready }
    var progress: AIVisualModelProgress? { record.progress }
}

/// Owns the verified Qwen2-VL bundle used for image syllabus import. It uses
/// the same durable background URLSession as text models, but keeps its
/// manifest separate so the existing three-tier text-model contract and
/// migration data remain untouched.
actor AIVisualModelStore {
    static let shared = AIVisualModelStore()
    static let downloadID = "vision-qwen2-vl-2b-bundle"

    /// Qwen2-VL 2B is the smallest verified Chinese-capable vision model in
    /// this release's llama.cpp bundle. Its Q4 language weights and Q8
    /// projector are pinned to one ggml-org revision and must be installed as
    /// a pair.
    static let descriptor = AIVisualModelDescriptor(
        id: "qwen2-vl-2b-q4_k_m-q8_0",
        modelName: "Qwen2-VL 2B",
        quantization: "Q4_K_M + projector Q8_0",
        parameterBand: "~2B",
        repository: "ggml-org/Qwen2-VL-2B-Instruct-GGUF",
        revision: "bb307c036e8a1ed7b663bbd0c35b41c4c9294cfd",
        license: "Apache-2.0",
        licenseReference: "https://huggingface.co/Qwen/Qwen2-VL-2B-Instruct/blob/main/LICENSE",
        model: AIVisualModelArtifact(
            fileName: "Qwen2-VL-2B-Instruct-Q4_K_M.gguf",
            sourceReference: "https://huggingface.co/ggml-org/Qwen2-VL-2B-Instruct-GGUF/resolve/bb307c036e8a1ed7b663bbd0c35b41c4c9294cfd/Qwen2-VL-2B-Instruct-Q4_K_M.gguf",
            sha256: "5745685d2e607a82a0696c1118e56a2a1ae0901da450fd9cd4f161c6b62867d7",
            bytes: 986_046_944
        ),
        projector: AIVisualModelArtifact(
            fileName: "mmproj-Qwen2-VL-2B-Instruct-Q8_0.gguf",
            sourceReference: "https://huggingface.co/ggml-org/Qwen2-VL-2B-Instruct-GGUF/resolve/bb307c036e8a1ed7b663bbd0c35b41c4c9294cfd/mmproj-Qwen2-VL-2B-Instruct-Q8_0.gguf",
            sha256: "a0ad91f00a7a80dcf84d719a61b00ee2e07b71794f4ee2dfa81a254621a8c418",
            bytes: 709_883_360
        )
    )

    nonisolated static var rootURL: URL {
        AIModelStore.rootURL.appending(path: "vision", directoryHint: .isDirectory)
    }

    nonisolated static var manifestURL: URL {
        rootURL.appending(path: "manifest.json", directoryHint: .notDirectory)
    }

    nonisolated static func isVisualDownloadID(_ id: String) -> Bool {
        id == downloadID
    }

    private struct Manifest: Codable {
        let record: AIVisualModelRecord
    }

    private(set) var record: AIVisualModelRecord
    private var activeDownloadTask: Task<AIVisualModelRecord, Error>?
    private var lastProgressPersistence: (date: Date, receivedBytes: Int64)?

    init() {
        self.record = Self.loadManifest()
    }

    func snapshot() -> AIVisualModelStoreSnapshot {
        reconcileInstalledFiles()
        persistManifest()
        return AIVisualModelStoreSnapshot(record: record, storageUsedBytes: record.storedBytes, hasLocalBundle: isInstalled(.model) && isInstalled(.projector))
    }

    /// Refreshes the durable record after a background process or an
    /// integration harness has written the atomic manifest. The production
    /// download path never calls this while a foreground prepare is active.
    func reloadManifest() {
        guard activeDownloadTask == nil else { return }
        record = Self.loadManifest()
        reconcileInstalledFiles()
    }

    func prepare(
        progress: @escaping @Sendable (AIVisualModelProgress) -> Void = { _ in }
    ) async throws -> AIVisualModelRecord {
        if let activeDownloadTask {
            return try await activeDownloadTask.value
        }

        let task = Task { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.performPrepare(progress: progress)
        }
        activeDownloadTask = task
        do {
            let result = try await task.value
            activeDownloadTask = nil
            return result
        } catch {
            activeDownloadTask = nil
            throw error
        }
    }

    func pause() {
        ModelDownloadCoordinator.shared.pause(descriptorID: Self.downloadID)
    }

    func cancel() {
        // Cancelling the import screen is not uninstalling a verified bundle.
        guard activeDownloadTask != nil || record.state == .downloading || record.state == .paused else { return }
        activeDownloadTask?.cancel()
        activeDownloadTask = nil
        ModelDownloadCoordinator.shared.cancel(descriptorID: Self.downloadID)
        record.state = .notInstalled
        record.modelResumeData = nil
        record.projectorResumeData = nil
        record.activeArtifact = nil
        record.verifiedAt = nil
        persistManifest()
        finishActivity(.cancelled)
    }

    /// Reconnect a download after a cold launch. Only a download explicitly
    /// persisted as active is resumed; a paused bundle remains paused until
    /// the user asks to continue it.
    func resumePersistedDownloadsIfNeeded() {
        reconcileInstalledFiles()
        guard record.state == .downloading else { return }
        let kind = record.activeArtifact ?? .model
        record.activeArtifact = kind
        persistManifest()
        ModelDownloadCoordinator.shared.recover(
            descriptorID: Self.downloadID,
            modelName: Self.descriptor.modelName,
            url: Self.descriptor.artifact(kind).sourceURL,
            expectedBytes: Self.descriptor.artifact(kind).bytes,
            receivedBytes: kind == .model ? record.modelReceivedBytes : record.projectorReceivedBytes,
            resumeData: kind == .model ? record.modelResumeData : record.projectorResumeData
        )
    }

    /// Receives progress from the shared background coordinator after the app
    /// may have been suspended. The returned aggregate is what the foreground
    /// UI and Live Activity should display.
    func recordDownloadProgress(id: String, progress: ModelDownloadProgress) -> AIVisualModelProgress? {
        guard id == Self.downloadID,
              record.state == .downloading || record.state == .paused else { return nil }
        let kind = record.activeArtifact ?? .model
        updateProgress(progress, for: kind)
        let aggregate = record.progress
        persistProgressIfNeeded(aggregate)
        if let aggregate {
            updateActivity(aggregate)
        }
        return aggregate
    }

    /// Finalize a file received while no foreground task was waiting. If the
    /// language weights finished first, immediately continue with the
    /// projector so a background download remains an all-or-nothing bundle.
    func completeBackgroundDownload(id: String, location: URL, response: URLResponse) async {
        defer {
            try? FileManager.default.removeItem(at: location)
            ModelDownloadCoordinator.shared.backgroundFinalizationCompleted(descriptorID: id)
        }
        guard id == Self.downloadID, record.state == .downloading else { return }
        let kind = record.activeArtifact ?? .model
        do {
            try finalizeDownloadedArtifact(location: location, response: response, kind: kind)
            if kind == .model {
                record.activeArtifact = .projector
                record.state = .downloading
                persistManifest()
                // Keep the background completion handler open until the next
                // artifact task is registered and finalized. Otherwise iOS
                // can suspend the app after the language file and strand the
                // projector at exactly the half-downloaded state this store
                // is designed to recover from.
                _ = try? await prepare()
            } else {
                finishReady()
            }
        } catch {
            failRecord(error)
        }
    }

    func failBackgroundDownload(id: String, resumeData: Data?, message: String) {
        guard id == Self.downloadID, record.state == .downloading else { return }
        let kind = record.activeArtifact ?? .model
        if let resumeData, !resumeData.isEmpty {
            record.state = .paused
            setResumeData(resumeData, for: kind)
        } else {
            record.state = .failed(message)
            setResumeData(nil, for: kind)
        }
        persistManifest()
        finishActivity(resumeData?.isEmpty == false ? .paused : .failed)
    }

    func verifyReady() throws -> AIVisualModelRecord {
        reconcileInstalledFiles()
        guard activeDownloadTask == nil, record.state != .downloading else { throw AIModelStoreError.modelInUse }
        guard isInstalled(.model), isInstalled(.projector) else { throw AIModelStoreError.modelNotInstalled }
        do {
            _ = try Self.validateArtifact(Self.descriptor.model, at: Self.descriptor.modelURL)
            _ = try Self.validateArtifact(Self.descriptor.projector, at: Self.descriptor.projectorURL)
            record.state = .ready
            record.activeArtifact = nil
            record.modelResumeData = nil
            record.projectorResumeData = nil
            record.modelReceivedBytes = Self.descriptor.model.bytes
            record.projectorReceivedBytes = Self.descriptor.projector.bytes
            record.verifiedAt = .now
            persistManifest()
            return record
        } catch {
            record.state = .failed(error.localizedDescription)
            record.verifiedAt = nil
            persistManifest()
            throw error
        }
    }

    private func performPrepare(
        progress: @escaping @Sendable (AIVisualModelProgress) -> Void
    ) async throws -> AIVisualModelRecord {
        reconcileInstalledFiles()
        let modelInstalled = validateInstalledArtifactIfNeeded(.model)
        let projectorInstalled = validateInstalledArtifactIfNeeded(.projector)
        if record.state == .ready, modelInstalled, projectorInstalled {
            record.verifiedAt = .now
            persistManifest()
            let ready = record
            progress(.complete(for: Self.descriptor))
            return ready
        }
        if record.state == .ready {
            record.state = .notInstalled
            record.activeArtifact = nil
            record.verifiedAt = nil
        }

        try checkStorage()
        record.state = .downloading
        record.verifiedAt = nil
        let next: AIVisualArtifactKind = if !modelInstalled {
            .model
        } else if !projectorInstalled {
            .projector
        } else {
            record.activeArtifact ?? .model
        }
        record.activeArtifact = next
        persistManifest()
        progress(record.progress ?? .starting(for: Self.descriptor))
        startActivity(record.progress ?? .starting(for: Self.descriptor))

        do {
            if !modelInstalled {
                try await downloadArtifact(.model, progress: progress)
            } else {
                record.modelReceivedBytes = Self.descriptor.model.bytes
            }
            if !projectorInstalled {
                try await downloadArtifact(.projector, progress: progress)
            } else {
                record.projectorReceivedBytes = Self.descriptor.projector.bytes
            }
            finishReady()
            return record
        } catch let paused as ModelDownloadPaused {
            record.state = .paused
            setResumeData(paused.resumeData, for: record.activeArtifact ?? .model)
            persistManifest()
            throw paused
        } catch let interrupted as ModelDownloadInterrupted {
            if let resumeData = interrupted.resumeData, !resumeData.isEmpty {
                record.state = .paused
                setResumeData(resumeData, for: record.activeArtifact ?? .model)
            } else {
                record.state = .failed(interrupted.message)
                setResumeData(nil, for: record.activeArtifact ?? .model)
            }
            persistManifest()
            throw interrupted
        } catch is CancellationError {
            // An explicit cancel has already reset the manifest. Preserve a
            // completed first artifact when the task was cancelled by the
            // caller so a later retry need not redownload it.
            if record.state == .downloading {
                record.state = .notInstalled
                record.activeArtifact = nil
                record.modelResumeData = nil
                record.projectorResumeData = nil
                persistManifest()
            }
            throw CancellationError()
        } catch {
            failRecord(error)
            throw error
        }
    }

    private func downloadArtifact(
        _ kind: AIVisualArtifactKind,
        progress: @escaping @Sendable (AIVisualModelProgress) -> Void
    ) async throws {
        record.activeArtifact = kind
        persistManifest()
        let artifact = Self.descriptor.artifact(kind)
        let resumeData = resumeData(for: kind)
        let received = kind == .model ? record.modelReceivedBytes : record.projectorReceivedBytes
        let relay: @Sendable (ModelDownloadProgress) -> Void = { [weak self] raw in
            guard let self else { return }
            Task {
                let aggregate = await self.receive(raw, for: kind)
                if let aggregate { progress(aggregate) }
            }
        }
        let downloaded = try await ModelDownloadCoordinator.shared.download(
            descriptorID: Self.downloadID,
            modelName: Self.descriptor.modelName,
            url: artifact.sourceURL,
            expectedBytes: artifact.bytes,
            receivedBytes: received,
            resumeData: resumeData,
            progress: relay
        )
        defer {
            try? FileManager.default.removeItem(at: downloaded.location)
            ModelDownloadCoordinator.shared.backgroundFinalizationCompleted(descriptorID: Self.downloadID)
        }
        guard record.state == .downloading else { throw CancellationError() }
        try finalizeDownloadedArtifact(location: downloaded.location, response: downloaded.response, kind: kind)
        progress(record.progress ?? .starting(for: Self.descriptor))
    }

    private func receive(_ progress: ModelDownloadProgress, for kind: AIVisualArtifactKind) -> AIVisualModelProgress? {
        guard record.state == .downloading || record.state == .paused else { return nil }
        updateProgress(progress, for: kind)
        let aggregate = record.progress
        persistProgressIfNeeded(aggregate)
        if let aggregate { updateActivity(aggregate) }
        return aggregate
    }

    private func updateProgress(_ progress: ModelDownloadProgress, for kind: AIVisualArtifactKind) {
        switch kind {
        case .model:
            record.modelReceivedBytes = min(Self.descriptor.model.bytes, max(0, progress.receivedBytes))
        case .projector:
            record.projectorReceivedBytes = min(Self.descriptor.projector.bytes, max(0, progress.receivedBytes))
        }
    }

    private func finalizeDownloadedArtifact(
        location: URL,
        response: URLResponse,
        kind: AIVisualArtifactKind
    ) throws {
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw AIModelStoreError.downloadFailed
        }
        let artifact = Self.descriptor.artifact(kind)
        _ = try Self.validateArtifact(artifact, at: location)
        try Self.atomicInstall(source: location, destination: Self.descriptor.localURL(for: kind))
        switch kind {
        case .model:
            record.modelReceivedBytes = artifact.bytes
            record.modelResumeData = nil
        case .projector:
            record.projectorReceivedBytes = artifact.bytes
            record.projectorResumeData = nil
        }
        persistManifest()
    }

    private func finishReady() {
        record.state = .ready
        record.activeArtifact = nil
        record.modelReceivedBytes = Self.descriptor.model.bytes
        record.projectorReceivedBytes = Self.descriptor.projector.bytes
        record.modelResumeData = nil
        record.projectorResumeData = nil
        record.verifiedAt = .now
        lastProgressPersistence = nil
        persistManifest()
        finishActivity(.success)
    }

    private func failRecord(_ error: Error) {
        record.state = .failed(error.localizedDescription)
        record.verifiedAt = nil
        persistManifest()
        finishActivity(.failed)
    }

    private func reconcileInstalledFiles() {
        if record.state == .ready,
           !isInstalled(.model) || !isInstalled(.projector) {
            record.state = .notInstalled
            record.verifiedAt = nil
        }
        if record.state == .notInstalled {
            record.modelReceivedBytes = isInstalled(.model) ? Self.descriptor.model.bytes : 0
            record.projectorReceivedBytes = isInstalled(.projector) ? Self.descriptor.projector.bytes : 0
        }
    }

    private func isInstalled(_ kind: AIVisualArtifactKind) -> Bool {
        let artifact = Self.descriptor.artifact(kind)
        let url = Self.descriptor.localURL(for: kind)
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        return (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) == artifact.bytes
    }

    /// Size alone is not sufficient after an interrupted or externally
    /// truncated transfer. Validate same-sized files before treating them as
    /// completed; invalid files are removed so the next prepare resumes from
    /// a clean, deterministic state.
    private func validateInstalledArtifactIfNeeded(_ kind: AIVisualArtifactKind) -> Bool {
        guard isInstalled(kind) else {
            updateReceivedBytes(0, for: kind)
            return false
        }
        do {
            _ = try Self.validateArtifact(
                Self.descriptor.artifact(kind),
                at: Self.descriptor.localURL(for: kind)
            )
            updateReceivedBytes(Self.descriptor.artifact(kind).bytes, for: kind)
            setResumeData(nil, for: kind)
            return true
        } catch {
            try? FileManager.default.removeItem(at: Self.descriptor.localURL(for: kind))
            updateReceivedBytes(0, for: kind)
            setResumeData(nil, for: kind)
            return false
        }
    }

    private func updateReceivedBytes(_ bytes: Int64, for kind: AIVisualArtifactKind) {
        switch kind {
        case .model:
            record.modelReceivedBytes = max(0, bytes)
        case .projector:
            record.projectorReceivedBytes = max(0, bytes)
        }
    }

    private func checkStorage() throws {
        let values = try Self.rootURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let available = values.volumeAvailableCapacityForImportantUsage,
           available < Self.descriptor.totalBytes {
            throw AIModelStoreError.insufficientStorage(
                required: Self.descriptor.totalBytes,
                available: available
            )
        }
    }

    private func resumeData(for kind: AIVisualArtifactKind) -> Data? {
        switch kind {
        case .model: record.modelResumeData
        case .projector: record.projectorResumeData
        }
    }

    private func setResumeData(_ data: Data?, for kind: AIVisualArtifactKind) {
        switch kind {
        case .model: record.modelResumeData = data
        case .projector: record.projectorResumeData = data
        }
    }

    private func persistProgressIfNeeded(_ progress: AIVisualModelProgress?) {
        guard let progress else { return }
        let now = Date.now
        let previous = lastProgressPersistence
        let shouldPersist = previous == nil
            || now.timeIntervalSince(previous?.date ?? .distantPast) >= 1
            || progress.totalReceivedBytes - (previous?.receivedBytes ?? 0) >= 8 * 1_024 * 1_024
        guard shouldPersist else { return }
        lastProgressPersistence = (now, progress.totalReceivedBytes)
        persistManifest()
    }

    private func startActivity(_ progress: AIVisualModelProgress) {
        Task { @MainActor in
            ModelDownloadActivityController.shared.start(
                downloadID: Self.downloadID,
                modelName: Self.descriptor.modelName,
                progress: progress.asDownloadProgress,
                locale: .current
            )
        }
    }

    private func updateActivity(_ progress: AIVisualModelProgress) {
        Task { @MainActor in
            ModelDownloadActivityController.shared.update(
                downloadID: Self.downloadID,
                progress: progress.asDownloadProgress
            )
        }
    }

    private func finishActivity(_ outcome: ModelDownloadActivityOutcome) {
        Task { @MainActor in
            ModelDownloadActivityController.shared.finish(downloadID: Self.downloadID, outcome: outcome)
        }
    }

    private func persistManifest() {
        do {
            try FileManager.default.createDirectory(at: Self.rootURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(Manifest(record: record)).write(to: Self.manifestURL, options: .atomic)
            Self.excludeFromBackup(Self.rootURL)
            Self.excludeFromBackup(Self.manifestURL)
        } catch {
            // A manifest failure must not bring down import or navigation.
        }
    }

    private static func loadManifest() -> AIVisualModelRecord {
        if let data = try? Data(contentsOf: manifestURL),
           let manifest = try? JSONDecoder().decode(Manifest.self, from: data) {
            return manifest.record
        }
        return AIVisualModelRecord(
            descriptor: descriptor,
            state: .notInstalled,
            activeArtifact: nil,
            modelResumeData: nil,
            projectorResumeData: nil,
            modelReceivedBytes: 0,
            projectorReceivedBytes: 0,
            verifiedAt: nil
        )
    }

    private static func validateArtifact(_ artifact: AIVisualModelArtifact, at url: URL) throws -> String {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize, Int64(size) == artifact.bytes else {
            throw AIModelStoreError.invalidModel
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard try handle.read(upToCount: 4) == Data("GGUF".utf8) else {
            throw AIModelStoreError.invalidModel
        }
        try handle.seek(toOffset: 0)
        var hasher = SHA256()
        // FileHandle's autoreleased read buffers can otherwise retain the
        // entire model on a long-lived executor until its outer pool drains.
        // Keep checksum verification bounded to one chunk without weakening it.
        while try autoreleasepool(invoking: {
            try Task.checkCancellation()
            guard let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty else { return false }
            hasher.update(data: chunk)
            return true
        }) {}
        let hash = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard hash.caseInsensitiveCompare(artifact.sha256) == .orderedSame else {
            throw AIModelStoreError.checksumMismatch
        }
        return hash
    }

    private static func atomicInstall(source: URL, destination: URL) throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: source, to: destination)
        excludeFromBackup(destination)
    }

    private static func excludeFromBackup(_ url: URL) {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(values)
    }
}

/// Runtime-neutral facade for the image-import surface.
nonisolated enum OnDeviceAIVisionModelLibrary {
    static var descriptor: AIVisualModelDescriptor { AIVisualModelStore.descriptor }

    static func snapshot() async -> AIVisualModelStoreSnapshot {
        await AIVisualModelStore.shared.snapshot()
    }

    static func reloadManifest() async {
        await AIVisualModelStore.shared.reloadManifest()
    }

    static func prepare(
        progress: @escaping @Sendable (AIVisualModelProgress) -> Void = { _ in }
    ) async throws -> AIVisualModelRecord {
        try await AIVisualModelStore.shared.prepare(progress: progress)
    }

    static func resumePersistedDownloadsIfNeeded() async {
        await AIVisualModelStore.shared.resumePersistedDownloadsIfNeeded()
    }

    static func pause() async {
        await AIVisualModelStore.shared.pause()
    }

    static func cancel() async {
        await AIVisualModelStore.shared.cancel()
    }

    static func verifyReady() async throws -> AIVisualModelRecord {
        try await AIVisualModelStore.shared.verifyReady()
    }
}
