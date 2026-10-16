import Foundation
import UserNotifications

/// No image or source-app information is placed in a notification. The UUID
/// must still match the App Group record before the app can consume it.
enum ShareFloatNotificationPayload {
    static let identifier = "com.josh.cod.latest-shared-image"
    static let category = "com.josh.cod.float-shared-image"
    static let requestKey = "codQuickFloatRequestID"

    static func requestID(identifier: String, category: String, userInfo: [AnyHashable: Any]) -> UUID? {
        guard identifier == self.identifier, category == self.category,
              let value = userInfo[requestKey] as? String else { return nil }
        return UUID(uuidString: value)
    }

    static func request(for id: UUID) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Your image is ready to float"
        content.body = "Tap to open Cod and start Picture in Picture."
        content.categoryIdentifier = category
        content.userInfo = [requestKey: id.uuidString]
        // Do not bypass Focus, request time-sensitive privileges, attach a
        // private photo, or play a sound just to launch an app.
        return UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
    }
}

enum ShareFloatNotificationError: LocalizedError {
    case permissionNeeded

    var errorDescription: String? {
        "Notifications aren't available to this share extension. Your image is saved: open Cod and tap Try Floating Again. You can also check notification permission in iPhone Settings and try sharing again."
    }
}

struct ShareFloatNotifications {
    var center: UNUserNotificationCenter = .current()

    /// Only the containing app asks for permission, following an explicit
    /// Settings action. Never prompt unexpectedly from another app's share UI.
    func requestPermission() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert])
    }

    func schedule(_ id: UUID) async throws {
        let settings = await center.notificationSettings()
        CodDiagnosticLog.record("float notification authorization=\(settings.authorizationStatus.rawValue) bundle=\(Bundle.main.bundleIdentifier ?? "unknown")")
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            throw ShareFloatNotificationError.permissionNeeded
        }
        try await center.add(ShareFloatNotificationPayload.request(for: id))
        CodDiagnosticLog.record("float notification scheduled request=\(id)")
    }

    func remove() {
        center.removePendingNotificationRequests(withIdentifiers: [ShareFloatNotificationPayload.identifier])
        center.removeDeliveredNotifications(withIdentifiers: [ShareFloatNotificationPayload.identifier])
    }
}
