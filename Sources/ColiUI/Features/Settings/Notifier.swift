import Foundation
import UserNotifications

/// Delivers ColiUI's alerts through Notification Center.
@MainActor
protocol Notifying: AnyObject {
    /// Called with the alert identifier when the user clicks a notification.
    var onOpen: ((String) -> Void)? { get set }
    func requestAuthorization()
    func post(title: String, body: String, identifier: String)
}

@MainActor
final class SystemNotifier: NSObject, Notifying, UNUserNotificationCenterDelegate {
    var onOpen: ((String) -> Void)?

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(title: String, body: String, identifier: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["identifier": identifier]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }

    /// Show banners even while ColiUI is in front.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await open(response.notification.request.identifier)
    }

    private func open(_ identifier: String) {
        onOpen?(identifier)
    }
}
