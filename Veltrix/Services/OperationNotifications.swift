import SwiftUI
import UserNotifications
import OSLog

final class NotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static let opened = Notification.Name("VeltrixOperationOpened")
    @MainActor static weak var lockState: AppLock?
    private var privacyWindows: [String: UIWindow] = [:]

    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(shield(_:)), name: UIScene.willDeactivateNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(shield(_:)), name: UIScene.didEnterBackgroundNotification, object: nil)
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

    @MainActor @objc private func shield(_ notification: Notification) {
        guard let scene = notification.object as? UIWindowScene else { return }
        if notification.name == UIScene.willDeactivateNotification && Self.lockState?.locked == true { return }
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

@MainActor final class OperationNotifications: ObservableObject {
    static let shared = OperationNotifications()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var alertsEnabled = false
    @Published private(set) var soundsEnabled = false
    @Published private(set) var lastDelivery: Delivery?
    @Published private(set) var error: String?

    enum Delivery { case queued, delivered, noAlerts }

    private let center = UNUserNotificationCenter.current()
    private let logger = Logger(subsystem: "app.veltrix.simulation", category: "Notifications")
    private var authorizationRequest: Task<Bool, Never>?
    private var lastID: String?
    private var generation = 0

    static func eligible(_ entry: Entry) -> Bool { entry.kind != .adjustment }

    func refresh() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
        alertsEnabled = settings.alertSetting == .enabled && settings.alertStyle != .none
        soundsEnabled = settings.soundSetting == .enabled
        if let lastID, await center.deliveredNotifications().contains(where: { $0.request.identifier == lastID }) {
            lastDelivery = .delivered
        }
    }

    func authorize() async -> Bool {
        if let authorizationRequest { return await authorizationRequest.value }
        let request = Task {
            await refresh()
            if authorizationStatus == .notDetermined || authorizationStatus == .provisional {
                do {
                    _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                    error = nil
                } catch {
                    record(error)
                }
            }
            await refresh()
            return canSchedule
        }
        authorizationRequest = request
        defer { authorizationRequest = nil }
        return await request.value
    }

    private var canSchedule: Bool {
        authorizationStatus == .authorized || authorizationStatus == .provisional || authorizationStatus == .ephemeral
    }

    static func request(for entry: Entry, filled: Bool, amounts: String?) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Veltrix"
        let type = filled ? L.text("Limit order filled") : entry.kind.localized
        let operation = L.format("Local operation: %@", type)
        if let amounts {
            let name = Asset.catalog.first { $0.id == entry.asset }?.name ?? entry.asset
            content.body = operation + " · " + name + " · " + amounts
        } else {
            content.body = operation
        }
        content.sound = .default
        return UNNotificationRequest(identifier: entry.id.uuidString, content: content, trigger: nil)
    }

    static func schedule(_ entry: Entry, filled: Bool, amounts: String?) {
        let request = request(for: entry, filled: filled, amounts: amounts)
        shared.enqueue(request, askPermission: [.buy, .sell, .swap].contains(entry.kind))
    }

    static func clear() {
        shared.generation += 1
        shared.lastID = nil
        shared.lastDelivery = nil
        shared.center.removeAllPendingNotificationRequests()
        shared.center.removeAllDeliveredNotifications()
    }

    static func schedulePriceAlert(id: UUID, body: String) {
        let content = UNMutableNotificationContent()
        content.title = "Veltrix"
        content.body = body
        content.sound = .default
        shared.enqueue(UNNotificationRequest(identifier: "price-\(id.uuidString)", content: content, trigger: nil),
                       askPermission: false)
    }

    private func enqueue(_ request: UNNotificationRequest, askPermission: Bool) {
        let version = generation
        Task {
            await refresh()
            if askPermission && authorizationStatus == .notDetermined { _ = await authorize() }
            guard version == generation else { return }
            guard canSchedule else {
                lastDelivery = .noAlerts
                logger.notice("Local notification skipped. Authorization status: \(self.authorizationStatus.rawValue)")
                return
            }
            do {
                try await center.add(request)
                guard version == generation else {
                    center.removePendingNotificationRequests(withIdentifiers: [request.identifier])
                    center.removeDeliveredNotifications(withIdentifiers: [request.identifier])
                    return
                }
                error = nil
                lastID = request.identifier
                lastDelivery = alertsEnabled ? .queued : .noAlerts
                logger.info("iOS accepted a local notification request")
                try? await Task.sleep(nanoseconds: 650_000_000)
                if version == generation { await refresh() }
            } catch {
                if version == generation { record(error) }
            }
        }
    }

    private func record(_ error: Error) {
        let failure = error as NSError
        logger.error("Local notification request failed: \(failure.domain, privacy: .public) (\(failure.code))")
        self.error = L.format("Notification delivery error (%@).", String(failure.code))
    }
}
