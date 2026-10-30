import Foundation
import UserNotifications

/// macOS bildirimleri. Alarm bildirimlerinde "Ertele" ve "Şimdi durdur" düğmeleri olur.
enum Notifier {
    static let alarmCategory = "GOZCU_ALARM"

    static func setup() {
        let c = UNUserNotificationCenter.current()
        c.delegate = Delegate.shared
        let snooze = UNNotificationAction(identifier: "snooze", title: "15 dk ertele")
        let stop = UNNotificationAction(identifier: "stop", title: "AI'yı şimdi durdur", options: [.destructive])
        c.setNotificationCategories([UNNotificationCategory(identifier: alarmCategory, actions: [snooze, stop], intentIdentifiers: [])])
        c.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func send(id: String, title: String, body: String, sound: Bool = true) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if sound { content.sound = .default }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    static func alarm(machine: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .defaultCritical
        content.categoryIdentifier = alarmCategory
        content.userInfo = ["machine": machine]
        content.interruptionLevel = .timeSensitive
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "alarm-\(machine)", content: content, trigger: nil))
    }

    final class Delegate: NSObject, UNUserNotificationCenterDelegate {
        static let shared = Delegate()

        func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
            completionHandler([.banner, .sound, .list])
        }

        func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                    withCompletionHandler completionHandler: @escaping () -> Void) {
            let name = response.notification.request.content.userInfo["machine"] as? String
            let act = response.actionIdentifier
            Task { @MainActor in
                if let name, let m = Store.shared.machine(named: name) {
                    if act == "snooze" { await Store.shared.action(m, ["action": "snooze", "minutes": 15]) }
                    if act == "stop" { await Store.shared.action(m, ["action": "stop_ai"]) }
                }
                completionHandler()
            }
        }
    }
}
