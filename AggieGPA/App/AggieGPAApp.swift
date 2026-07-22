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
        let inMemory = arguments.contains("--uitest-in-memory") || arguments.contains("--screenshot-demo")
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
    }
}
