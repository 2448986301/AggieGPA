import Foundation
import LocalAuthentication
import Observation

@MainActor
protocol DeviceAuthenticating {
    func authenticate(reason: String) async -> Bool
}

@MainActor
struct LocalDeviceAuthenticator: DeviceAuthenticating {
    func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "Use Passcode"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}

@MainActor
@Observable
final class PrivacyLockService {
    private(set) var isLocked = false
    private(set) var isAuthenticating = false
    private(set) var errorMessage: String?
    private var backgroundedAt: Date?
    private var hasEvaluatedInitialForeground = false
    private let authenticator: any DeviceAuthenticating

    init(authenticator: any DeviceAuthenticating = LocalDeviceAuthenticator()) {
        self.authenticator = authenticator
    }

    func prepareForBackground() {
        backgroundedAt = .now
    }

    func handleForeground(preferences: UserPreferences?) async {
        guard let preferences, preferences.privacyLockEnabled else {
            isLocked = false
            isAuthenticating = false
            backgroundedAt = nil
            hasEvaluatedInitialForeground = false
            return
        }
        guard !isAuthenticating else { return }

        let shouldAuthenticate: Bool
        if let backgroundedAt {
            let elapsed = Date.now.timeIntervalSince(backgroundedAt)
            self.backgroundedAt = nil
            shouldAuthenticate = elapsed >= preferences.privacyLockDelay.seconds
        } else {
            shouldAuthenticate = !hasEvaluatedInitialForeground
        }

        hasEvaluatedInitialForeground = true
        guard shouldAuthenticate else { return }
        isLocked = true
        await authenticate()
    }

    func lockNow() { isLocked = true }

    func authenticate() async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        hasEvaluatedInitialForeground = true
        defer { isAuthenticating = false }

        let success = await authenticator.authenticate(reason: "Unlock your private GPA records")
        if success {
            isLocked = false
            errorMessage = nil
        } else {
            errorMessage = "Authentication was not completed. Your GPA data is safe and unchanged."
        }
    }
}
