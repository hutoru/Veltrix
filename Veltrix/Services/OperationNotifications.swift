import SwiftUI
import UserNotifications

final class NotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static let opened = Notification.Name("VeltrixOperationOpened")

    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completion: @escaping (UNNotificationPresentationOptions) -> Void) {
        completion([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completion: @escaping () -> Void) {
        let identifier = response.notification.request.identifier
        DispatchQueue.main.async {
            if let id = UUID(uuidString: identifier) {
                UserDefaults.standard.set(identifier, forKey: "pendingOperationNotification")
                NotificationCenter.default.post(name: Self.opened, object: id)
            }
            completion()
        }
    }
}

@MainActor enum OperationNotifications {
    static func eligible(_ entry: Entry) -> Bool { entry.kind != .adjustment }

    static func authorize() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) == true
    }

    static func schedule(_ entry: Entry, filled: Bool, amounts: String?) {
        let content = UNMutableNotificationContent()
        content.title = "Veltrix"
        let type = filled ? L.text("Limit order filled") : entry.kind.localized
        let operation = L.format("Local operation: %@", type)
        content.body = amounts.map { operation + " · " + $0 } ?? operation
        content.sound = .default
        let request = UNNotificationRequest(identifier: entry.id.uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    static func clear() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    static func schedulePriceAlert(id: UUID, body: String) {
        let content = UNMutableNotificationContent()
        content.title = "Veltrix"
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: "price-\(id.uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }
}
