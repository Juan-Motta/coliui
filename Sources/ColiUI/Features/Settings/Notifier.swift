import Foundation
import UserNotifications

/// Delivers ColiUI's alerts through Notification Center.
protocol Notifying: AnyObject {
    func requestAuthorization()
    func post(title: String, body: String, identifier: String)
}

final class SystemNotifier: Notifying {
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
}
