import UIKit
import UserNotifications

final class CodApplicationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Cold-launch notification responses arrive before RootView exists.
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let id = ShareFloatNotificationPayload.requestID(
                identifier: response.notification.request.identifier,
                category: response.notification.request.content.categoryIdentifier,
                userInfo: response.notification.request.content.userInfo
              ) else {
            completionHandler()
            return
        }
        Task { @MainActor in
            IntentInbox.shared.pendingQuickFloatRequestID = id
            completionHandler()
        }
    }
}
