import UIKit
import UserNotifications

extension Notification.Name {
    static let openGradeItemFromNotification = Notification.Name("openGradeItemFromNotification")
}

final class NotificationAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Task {
            await OnDeviceAIModelLibrary.resumePersistedDownloadsIfNeeded()
        }
        return true
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        ModelDownloadCoordinator.shared.handleBackgroundEvents(
            identifier: identifier,
            completionHandler: completionHandler
        )
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let courseID = info["courseID"] as? String else { return }
        await MainActor.run {
            NotificationCenter.default.post(name: .openGradeItemFromNotification, object: courseID)
        }
    }
}
