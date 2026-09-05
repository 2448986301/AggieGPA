@preconcurrency import ActivityKit
import Foundation

/// The Live Activity is intentionally small: model downloads expose real
/// percentage progress, while indeterminate AI work continues to use the
/// existing ThinkingOrbsKit capsule inside the app.
nonisolated struct ModelDownloadActivityAttributes: ActivityAttributes, Hashable, Sendable {
    struct ContentState: Codable, Hashable, Sendable {
        enum Phase: String, Codable, Hashable, Sendable {
            case downloading
            case paused
            case finishing
            case failed
        }

        var receivedBytes: Int64
        var expectedBytes: Int64
        var phase: Phase

        var fraction: Double {
            guard expectedBytes > 0 else { return 0 }
            return min(1, max(0, Double(receivedBytes) / Double(expectedBytes)))
        }
    }

    let downloadID: String
    let title: String
    let modelName: String
    let languageCode: String
}

enum ModelDownloadActivityOutcome: Sendable {
    case success
    case paused
    case failed
    case cancelled
}

@MainActor
final class ModelDownloadActivityController {
    static let shared = ModelDownloadActivityController()

    private var activity: Activity<ModelDownloadActivityAttributes>?
    private var activeDownloadID: String?
    private var endingActivities: [UUID: Activity<ModelDownloadActivityAttributes>] = [:]
    private var lastUpdateAt = Date.distantPast
    private var lastFraction: Double = -1

    func start(
        downloadID: String,
        modelName: String,
        progress: ModelDownloadProgress,
        locale: Locale
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        if activeDownloadID == downloadID, activity != nil {
            update(downloadID: downloadID, progress: progress)
            return
        }
        if activeDownloadID != downloadID {
            endCurrentActivity()
        }

        let languageCode = locale.identifier.lowercased().hasPrefix("zh") ? "zh-Hans" : "en"
        let attributes = ModelDownloadActivityAttributes(
            downloadID: downloadID,
            title: languageCode == "zh-Hans" ? "正在下载模型" : "Downloading model",
            modelName: modelName,
            languageCode: languageCode
        )
        let state = ModelDownloadActivityAttributes.ContentState(
            receivedBytes: max(0, progress.receivedBytes),
            expectedBytes: max(0, progress.expectedBytes),
            phase: .downloading
        )
        let content = ActivityContent(state: state, staleDate: Date(timeIntervalSinceNow: 3_600))

        do {
            activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
            activeDownloadID = downloadID
            lastUpdateAt = .now
            lastFraction = state.fraction
        } catch {
            // Live Activities are an optional presentation surface. A denied
            // permission or unsupported device must never affect downloading.
            activity = nil
            activeDownloadID = nil
        }
    }

    func update(downloadID: String, progress: ModelDownloadProgress) {
        guard activeDownloadID == downloadID, activity != nil else { return }
        let state = ModelDownloadActivityAttributes.ContentState(
            receivedBytes: max(0, progress.receivedBytes),
            expectedBytes: max(0, progress.expectedBytes),
            phase: .downloading
        )
        let now = Date.now
        guard now.timeIntervalSince(lastUpdateAt) >= 0.35 || abs(state.fraction - lastFraction) >= 0.01 else { return }
        lastUpdateAt = now
        lastFraction = state.fraction
        let content = ActivityContent(state: state, staleDate: Date(timeIntervalSinceNow: 3_600))
        Task { @MainActor [weak self] in
            await self?.updateActivity(content)
        }
    }

    func finish(downloadID: String, outcome: ModelDownloadActivityOutcome) {
        guard activeDownloadID == downloadID, let activity else { return }
        let phase: ModelDownloadActivityAttributes.ContentState.Phase = switch outcome {
        case .success: .finishing
        case .paused: .paused
        case .failed, .cancelled: .failed
        }
        let state = ModelDownloadActivityAttributes.ContentState(
            receivedBytes: phase == .finishing ? 1 : 0,
            expectedBytes: phase == .finishing ? 1 : 0,
            phase: phase
        )
        let content = ActivityContent(state: state, staleDate: Date(timeIntervalSinceNow: 5))
        let token = UUID()
        endingActivities[token] = activity
        self.activity = nil
        self.activeDownloadID = nil
        Task { @MainActor [weak self] in
            await self?.endActivity(token: token, content: content, dismissalPolicy: .default)
        }
    }

    private func endCurrentActivity() {
        guard let activity else { return }
        let token = UUID()
        endingActivities[token] = activity
        self.activity = nil
        self.activeDownloadID = nil
        Task { @MainActor [weak self] in
            await self?.endActivity(token: token, content: nil, dismissalPolicy: .immediate)
        }
    }

    private func updateActivity(_ content: ActivityContent<ModelDownloadActivityAttributes.ContentState>) async {
        guard let activity else { return }
        // Activity's async API is imported as a concurrent operation in the
        // Swift 6 SDK. ActivityKit owns its synchronization; this local
        // escape keeps the controller's MainActor state from being treated as
        // a second mutable owner.
        nonisolated(unsafe) let currentActivity = activity
        await currentActivity.update(content)
    }

    private func endActivity(
        token: UUID,
        content: ActivityContent<ModelDownloadActivityAttributes.ContentState>?,
        dismissalPolicy: ActivityUIDismissalPolicy
    ) async {
        guard let activity = endingActivities.removeValue(forKey: token) else { return }
        nonisolated(unsafe) let currentActivity = activity
        await currentActivity.end(content, dismissalPolicy: dismissalPolicy)
    }
}
