import SwiftUI
import UserNotifications

final class NotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static let opened = Notification.Name("VeltrixOperationOpened")
    private var privacyWindows: [String: UIWindow] = [:]

    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(shield(_:)), name: UIScene.willDeactivateNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(removeShield(_:)), name: UIScene.didActivateNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(removeShield(_:)), name: UIScene.didDisconnectNotification, object: nil)
        application.shortcutItems = AppShortcut.allCases.map { shortcut in
            UIApplicationShortcutItem(type: shortcut.rawValue, localizedTitle: L.text(shortcut.title),
                                      localizedSubtitle: nil, icon: UIApplicationShortcutIcon(systemImageName: shortcut.icon))
        }
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = connectingSceneSession.configuration
        configuration.delegateClass = ShortcutSceneDelegate.self
        return configuration
    }

    @objc private func shield(_ notification: Notification) {
        guard let scene = notification.object as? UIWindowScene else { return }
        let id = scene.session.persistentIdentifier
        guard privacyWindows[id] == nil else { return }
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        controller.view.backgroundColor = .black
        window.rootViewController = controller
        window.windowLevel = .alert + 1
        window.isUserInteractionEnabled = false
        window.accessibilityElementsHidden = true
        window.isHidden = false
        privacyWindows[id] = window
    }

    @objc private func removeShield(_ notification: Notification) {
        guard let scene = notification.object as? UIWindowScene else { return }
        privacyWindows.removeValue(forKey: scene.session.persistentIdentifier)?.isHidden = true
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

enum AppShortcut: String, CaseIterable {
    case scan, explore

    static let opened = Notification.Name("VeltrixShortcutOpened")
    static let defaultsKey = "pendingAppShortcut"

    var title: String { self == .scan ? "Scan QR code" : "Explore" }
    var icon: String { self == .scan ? "qrcode.viewfinder" : "chart.xyaxis.line" }

    @MainActor static func activate(_ item: UIApplicationShortcutItem) -> Bool {
        guard let shortcut = Self(rawValue: item.type) else { return false }
        UserDefaults.standard.set(shortcut.rawValue, forKey: defaultsKey)
        NotificationCenter.default.post(name: opened, object: nil)
        return true
    }
}

final class ShortcutSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let shortcut = connectionOptions.shortcutItem { _ = AppShortcut.activate(shortcut) }
    }

    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        completionHandler(AppShortcut.activate(shortcutItem))
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
