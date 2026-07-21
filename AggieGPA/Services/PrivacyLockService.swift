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
    private(set) var errorMessage: String?
    private var backgroundedAt: Date?
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
            return
        }
        let elapsed = backgroundedAt.map { Date.now.timeIntervalSince($0) } ?? .infinity
        if elapsed >= preferences.privacyLockDelay.seconds {
            isLocked = true
            await authenticate()
        }
    }

    func lockNow() { isLocked = true }

    func authenticate() async {
        let success = await authenticator.authenticate(reason: "Unlock your private GPA records")
        if success {
            isLocked = false
            errorMessage = nil
        } else {
            errorMessage = "Authentication was not completed. Your GPA data is safe and unchanged."
        }
    }
}
