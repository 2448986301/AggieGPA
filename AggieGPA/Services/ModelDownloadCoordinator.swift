import Foundation

/// A durable background URLSession owns model downloads independently of any
/// SwiftUI screen. The coordinator is intentionally single-purpose and
/// lock-protected because URLSession delegate callbacks may arrive after the
/// app has been suspended or relaunched.
struct ModelDownloadResult: @unchecked Sendable {
    let location: URL
    let response: URLResponse
}

struct ModelDownloadPaused: Error, Sendable {
    let resumeData: Data?
}

struct ModelDownloadInterrupted: Error, Sendable {
    let resumeData: Data?
    let message: String
}

final class ModelDownloadCoordinator: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static let shared = ModelDownloadCoordinator()
    static let backgroundSessionIdentifier = "com.easonzhou.aggiegpa.model-download-v1"

    private struct Waiter {
        let continuation: CheckedContinuation<ModelDownloadResult, any Error>
        let progress: @Sendable (ModelDownloadProgress) -> Void
    }

    private struct Operation {
        let descriptorID: String
        var task: URLSessionDownloadTask?
        var waiters: [Waiter]
        var lastProgress: ModelDownloadProgress?
        var isPaused = false
    }

    private let lock = NSLock()
    private let delegateQueue: OperationQueue
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.backgroundSessionIdentifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.waitsForConnectivity = true
        configuration.allowsCellularAccess = true
        configuration.allowsExpensiveNetworkAccess = true
        configuration.allowsConstrainedNetworkAccess = true
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 72 * 60 * 60
        return URLSession(configuration: configuration, delegate: self, delegateQueue: delegateQueue)
    }()

    private var operations: [String: Operation] = [:]
    private var descriptorIDByTaskIdentifier: [Int: String] = [:]
    private var backgroundCompletionHandlers: [() -> Void] = []
    private var pendingBackgroundFinalizations = Set<String>()
    private var backgroundEventsFinished = false

    private override init() {
        let queue = OperationQueue()
        queue.name = "com.easonzhou.aggiegpa.model-download-v1"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .utility
        delegateQueue = queue
        super.init()
    }

    func download(
        descriptorID: String,
        modelName: String,
        url: URL,
        expectedBytes: Int64,
        receivedBytes: Int64,
        resumeData: Data?,
        progress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws -> ModelDownloadResult {
        // There is deliberately no cancellation handler here. Cancellation of
        // a view task detaches its waiter; only the explicit Cancel action
        // cancels the durable URLSession task.
        try await withCheckedThrowingContinuation { continuation in
            progress(.init(receivedBytes: receivedBytes, expectedBytes: expectedBytes))

            var immediateProgress: ModelDownloadProgress?
            var shouldStartActivity = false
            lock.lock()
            if var operation = operations[descriptorID] {
                operation.waiters.append(Waiter(continuation: continuation, progress: progress))
                immediateProgress = operation.lastProgress
                operations[descriptorID] = operation
            } else {
                let task: URLSessionDownloadTask
                if let resumeData, !resumeData.isEmpty {
                    task = session.downloadTask(withResumeData: resumeData)
                } else {
                    task = session.downloadTask(with: url)
                }
                task.taskDescription = descriptorID
                operations[descriptorID] = Operation(
                    descriptorID: descriptorID,
                    task: task,
                    waiters: [Waiter(continuation: continuation, progress: progress)],
                    lastProgress: nil
                )
                descriptorIDByTaskIdentifier[task.taskIdentifier] = descriptorID
                shouldStartActivity = true
                task.resume()
            }
            lock.unlock()

            if let immediateProgress {
                progress(immediateProgress)
            }
            if shouldStartActivity {
                startActivity(
                    descriptorID: descriptorID,
                    modelName: modelName,
                    progress: .init(receivedBytes: receivedBytes, expectedBytes: expectedBytes)
                )
            }
        }
    }

    /// Reattaches to tasks restored by iOS, or starts the one persisted task
    /// again when the previous process ended before URLSession could restore
    /// its task list. Only one model download is allowed at a time.
    func recover(
        descriptorID: String,
        modelName: String,
        url: URL,
        expectedBytes: Int64,
        receivedBytes: Int64,
        resumeData: Data?
    ) {
        session.getAllTasks { [weak self] tasks in
            guard let self else { return }
            let matching = tasks
                .compactMap { $0 as? URLSessionDownloadTask }
                .filter { $0.taskDescription == descriptorID }

            self.lock.lock()
            if let existing = matching.first {
                var operation = self.operations[descriptorID] ?? Operation(
                    descriptorID: descriptorID,
                    task: existing,
                    waiters: [],
                    lastProgress: nil
                )
                operation.task = existing
                self.operations[descriptorID] = operation
                self.descriptorIDByTaskIdentifier[existing.taskIdentifier] = descriptorID
                for duplicate in matching.dropFirst() {
                    duplicate.cancel()
                }
                self.lock.unlock()
                if existing.state == .suspended {
                    existing.resume()
                }
                self.startActivity(
                    descriptorID: descriptorID,
                    modelName: modelName,
                    progress: .init(receivedBytes: receivedBytes, expectedBytes: expectedBytes)
                )
                return
            }

            if self.operations[descriptorID] == nil {
                let task: URLSessionDownloadTask
                if let resumeData, !resumeData.isEmpty {
                    task = self.session.downloadTask(withResumeData: resumeData)
                } else {
                    task = self.session.downloadTask(with: url)
                }
                task.taskDescription = descriptorID
                self.operations[descriptorID] = Operation(
                    descriptorID: descriptorID,
                    task: task,
                    waiters: [],
                    lastProgress: nil
                )
                self.descriptorIDByTaskIdentifier[task.taskIdentifier] = descriptorID
                task.resume()
            }
            self.lock.unlock()
            self.startActivity(
                descriptorID: descriptorID,
                modelName: modelName,
                progress: .init(receivedBytes: receivedBytes, expectedBytes: expectedBytes)
            )
        }
    }

    func pause(descriptorID: String) {
        lock.lock()
        guard var operation = operations[descriptorID], let task = operation.task else {
            lock.unlock()
            return
        }
        operation.isPaused = true
        operations[descriptorID] = operation
        lock.unlock()

        task.cancel(byProducingResumeData: { [weak self] data in
            self?.finishPaused(descriptorID: descriptorID, resumeData: data)
        })
    }

    func cancel(descriptorID: String) {
        lock.lock()
        let operation = operations[descriptorID]
        operations[descriptorID] = nil
        if let task = operation?.task {
            descriptorIDByTaskIdentifier[task.taskIdentifier] = nil
        }
        lock.unlock()

        operation?.task?.cancel()
        if let operation {
            for waiter in operation.waiters {
                waiter.continuation.resume(throwing: CancellationError())
            }
        }
        cancelOrphanedTasks(descriptorID: descriptorID)
        finishActivity(descriptorID: descriptorID, outcome: .cancelled)
    }

    func handleBackgroundEvents(identifier: String, completionHandler: @escaping () -> Void) {
        guard identifier == Self.backgroundSessionIdentifier else {
            completionHandler()
            return
        }
        // Create the delegate-backed session before iOS delivers restored
        // task callbacks when the app was cold-launched for this event.
        _ = session
        lock.lock()
        backgroundCompletionHandlers.append(completionHandler)
        backgroundEventsFinished = false
        lock.unlock()
    }

    /// Called by AIModelStore after the downloaded file has been verified and
    /// atomically installed, so iOS does not receive the app completion signal
    /// while a large SHA-256 verification is still running.
    func backgroundFinalizationCompleted(descriptorID: String) {
        lock.lock()
        pendingBackgroundFinalizations.remove(descriptorID)
        let handlers: [() -> Void]
        if backgroundEventsFinished && pendingBackgroundFinalizations.isEmpty {
            handlers = backgroundCompletionHandlers
            backgroundCompletionHandlers.removeAll()
            backgroundEventsFinished = false
        } else {
            handlers = []
        }
        lock.unlock()
        handlers.forEach { $0() }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let descriptorID = identifier(for: downloadTask) else { return }
        let progress = ModelDownloadProgress(
            receivedBytes: totalBytesWritten,
            expectedBytes: totalBytesExpectedToWrite > 0
                ? totalBytesExpectedToWrite
                : ModelDownloadProgress.starting.expectedBytes
        )

        lock.lock()
        guard var operation = operations[descriptorID] else {
            lock.unlock()
            return
        }
        operation.lastProgress = progress
        let waiters = operation.waiters
        operations[descriptorID] = operation
        lock.unlock()

        for waiter in waiters {
            waiter.progress(progress)
        }
        Task {
            await AIModelStore.shared.recordDownloadProgress(id: descriptorID, progress: progress)
        }
        updateActivity(descriptorID: descriptorID, progress: progress)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let descriptorID = identifier(for: downloadTask), let response = downloadTask.response else {
            if let descriptorID = identifier(for: downloadTask) {
                finishFailure(
                    descriptorID: descriptorID,
                    error: ModelDownloadInterrupted(resumeData: nil, message: "The model download did not return a valid response.")
                )
            }
            return
        }

        do {
            let stableLocation = FileManager.default.temporaryDirectory
                .appendingPathComponent("AggieGPA-\(descriptorID)-\(UUID().uuidString).download")
            // Moving within the temporary volume avoids an unnecessary second
            // full-size copy. The system-owned URL is valid only for this
            // callback, so the move/copy happens before returning.
            do {
                try FileManager.default.moveItem(at: location, to: stableLocation)
            } catch {
                try FileManager.default.copyItem(at: location, to: stableLocation)
            }
            finishSuccess(descriptorID: descriptorID, location: stableLocation, response: response)
        } catch {
            finishFailure(descriptorID: descriptorID, error: error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let error else { return }
        guard let downloadTask = task as? URLSessionDownloadTask,
              let descriptorID = identifier(for: downloadTask) else { return }

        lock.lock()
        let shouldIgnore = operations[descriptorID]?.isPaused == true
        lock.unlock()
        guard !shouldIgnore else { return }

        let nsError = error as NSError
        let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        if nsError.code == NSURLErrorCancelled, resumeData == nil {
            finishFailure(descriptorID: descriptorID, error: CancellationError())
        } else {
            finishFailure(
                descriptorID: descriptorID,
                error: ModelDownloadInterrupted(
                    resumeData: resumeData,
                    message: error.localizedDescription.isEmpty
                        ? "The model download was interrupted."
                        : error.localizedDescription
                )
            )
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        lock.lock()
        backgroundEventsFinished = true
        let handlers: [() -> Void]
        if pendingBackgroundFinalizations.isEmpty {
            handlers = backgroundCompletionHandlers
            backgroundCompletionHandlers.removeAll()
            backgroundEventsFinished = false
        } else {
            handlers = []
        }
        lock.unlock()
        handlers.forEach { $0() }
    }

    private func finishSuccess(descriptorID: String, location: URL, response: URLResponse) {
        lock.lock()
        let operation = operations[descriptorID]
        operations[descriptorID] = nil
        if let task = operation?.task {
            descriptorIDByTaskIdentifier[task.taskIdentifier] = nil
        }
        pendingBackgroundFinalizations.insert(descriptorID)
        lock.unlock()

        let result = ModelDownloadResult(location: location, response: response)
        if let operation, !operation.waiters.isEmpty {
            for waiter in operation.waiters {
                waiter.continuation.resume(returning: result)
            }
        } else {
            Task {
                await AIModelStore.shared.completeBackgroundDownload(
                    id: descriptorID,
                    location: location,
                    response: response
                )
            }
        }
    }

    private func finishPaused(descriptorID: String, resumeData: Data?) {
        lock.lock()
        let operation = operations[descriptorID]
        operations[descriptorID] = nil
        if let task = operation?.task {
            descriptorIDByTaskIdentifier[task.taskIdentifier] = nil
        }
        lock.unlock()

        for waiter in operation?.waiters ?? [] {
            waiter.continuation.resume(throwing: ModelDownloadPaused(resumeData: resumeData))
        }
        if operation?.waiters.isEmpty != false {
            Task {
                await AIModelStore.shared.failBackgroundDownload(
                    id: descriptorID,
                    resumeData: resumeData,
                    message: "The model download was paused."
                )
            }
        }
        finishActivity(descriptorID: descriptorID, outcome: .paused)
    }

    private func finishFailure(descriptorID: String, error: any Error) {
        lock.lock()
        let operation = operations[descriptorID]
        operations[descriptorID] = nil
        if let task = operation?.task {
            descriptorIDByTaskIdentifier[task.taskIdentifier] = nil
        }
        lock.unlock()

        if let operation, !operation.waiters.isEmpty {
            for waiter in operation.waiters {
                waiter.continuation.resume(throwing: error)
            }
        } else if !(error is CancellationError) {
            let interrupted = error as? ModelDownloadInterrupted
            Task {
                await AIModelStore.shared.failBackgroundDownload(
                    id: descriptorID,
                    resumeData: interrupted?.resumeData,
                    message: error.localizedDescription.isEmpty
                        ? "The model download failed."
                        : error.localizedDescription
                )
            }
        }
        finishActivity(
            descriptorID: descriptorID,
            outcome: error is ModelDownloadInterrupted && (error as? ModelDownloadInterrupted)?.resumeData?.isEmpty == false
                ? .paused
                : .failed
        )
    }

    private func identifier(for task: URLSessionTask) -> String? {
        if let description = task.taskDescription, !description.isEmpty {
            return description
        }
        lock.lock()
        let identifier = descriptorIDByTaskIdentifier[task.taskIdentifier]
        lock.unlock()
        return identifier
    }

    private func cancelOrphanedTasks(descriptorID: String) {
        session.getAllTasks { tasks in
            for task in tasks where task.taskDescription == descriptorID {
                task.cancel()
            }
        }
    }

    private func startActivity(descriptorID: String, modelName: String, progress: ModelDownloadProgress) {
        Task { @MainActor in
            ModelDownloadActivityController.shared.start(
                downloadID: descriptorID,
                modelName: modelName,
                progress: progress,
                locale: .current
            )
        }
    }

    private func updateActivity(descriptorID: String, progress: ModelDownloadProgress) {
        Task { @MainActor in
            ModelDownloadActivityController.shared.update(downloadID: descriptorID, progress: progress)
        }
    }

    private func finishActivity(descriptorID: String, outcome: ModelDownloadActivityOutcome) {
        Task { @MainActor in
            ModelDownloadActivityController.shared.finish(downloadID: descriptorID, outcome: outcome)
        }
    }
}
