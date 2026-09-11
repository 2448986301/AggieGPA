import SwiftData
import SwiftUI

@main
struct AggieGPAApp: App {
    @UIApplicationDelegateAdaptor(NotificationAppDelegate.self) private var notificationDelegate
    private let container: ModelContainer
    private let storeErrorMessage: String?
    @State private var privacyLock = PrivacyLockService()

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--screenshot-demo") {
            // Preview defaults must not overwrite a student's durable preference.
            var overrides = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
            overrides["showFocusNext"] = true
            UserDefaults.standard.setVolatileDomain(overrides, forName: UserDefaults.argumentDomain)
        }
        let inMemory = AppDataIsolation.isEnabled
        let result = PersistentStoreService.makeContainer(inMemory: inMemory)
        container = result.container
        storeErrorMessage = result.errorMessage
    }

    var body: some Scene {
        WindowGroup {
            RootView(storeErrorMessage: storeErrorMessage)
                .environment(privacyLock)
        }
        .modelContainer(container)
        // Stage Manager keeps the window freely resizable. The default only
        // establishes a comfortable starting canvas; content adapts down to
        // compact widths instead of opting into content-size locking.
        .windowResizability(.automatic)
        .defaultSize(width: 1180, height: 820)
    }
}
