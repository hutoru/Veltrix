import SwiftUI
import UIKit

enum UITestMode {
    static let enabled: Bool = {
        #if DEBUG
        let process = ProcessInfo.processInfo
        return process.environment["UITEST_MODE"] == "1" || process.arguments.contains("--ui-testing")
        #else
        return false
        #endif
    }()

    static func fixture(_ argument: String) -> Bool {
        enabled && ProcessInfo.processInfo.arguments.contains(argument)
    }
}

@main @MainActor
struct VeltrixApp: App {
    @UIApplicationDelegateAdaptor(NotificationDelegate.self) private var notificationDelegate
    @StateObject private var model: VeltrixModel
    @StateObject private var lock: AuthCoordinator
    private let defaults: UserDefaults

    init() {
        let testing = UITestMode.enabled
        let defaults = testing ? (UserDefaults(suiteName: "Veltrix-UI-Tests") ?? .standard) : .standard
        if testing {
            defaults.removePersistentDomain(forName: "Veltrix-UI-Tests")
            UIView.setAnimationsEnabled(false)
        }
        if UITestMode.fixture("--locked-fixture") {
            defaults.set(true, forKey: "deviceLockEnabled")
        }
        if UITestMode.fixture("--light-fixture") {
            defaults.set("light", forKey: "theme")
        }
        self.defaults = defaults
        let nativeNotifications: VeltrixModel.NotificationSink? =
            UITestMode.fixture("--native-notifications") ? NotificationService.schedule : nil
        _model = StateObject(wrappedValue: VeltrixModel(defaults: defaults, testing: testing, notificationSink: nativeNotifications))
        _lock = StateObject(wrappedValue: AuthCoordinator(defaults: defaults, testing: testing))
    }

    var body: some Scene {
        let theme = VeltrixTheme(model.theme)
        WindowGroup {
            Group {
                if UITestMode.enabled {
                    VeltrixRoot()
                        .transaction {
                            $0.animation = nil
                            $0.disablesAnimations = true
                        }
                } else {
                    VeltrixRoot()
                }
            }
                .environmentObject(model)
                .environmentObject(lock)
                .defaultAppStorage(defaults)
                .environment(\.veltrixTheme, theme)
                .preferredColorScheme(model.theme.colorScheme)
                .tint(theme.accent)
        }
    }
}

private enum Destination: String, CaseIterable {
    case portfolio, markets, operations
    var name: LocalizedStringKey {
        switch self {
        case .portfolio: return "Home"
        case .markets: return "Markets"
        case .operations: return "Operations Center"
        }
    }
    var icon: String {
        switch self {
        case .portfolio: return "house"
        case .markets: return "chart.line.uptrend.xyaxis"
        case .operations: return "infinity"
        }
    }
}

struct VeltrixRoot: View {
    @Environment(\.veltrixTheme) private var theme
    @EnvironmentObject private var model: VeltrixModel
    @EnvironmentObject private var lock: AuthCoordinator
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tab = Destination.portfolio
    @State private var keyboardVisible = false
    @State private var showSplash = !UITestMode.enabled || UITestMode.fixture("--capture-launch")
    @State private var showSearch = false
    @State private var widgetRoute: URL?
    @State private var showEarn = false
    @State private var notificationEntry: Entry?
    @State private var notificationOrder: LimitOrder?
    @State private var showPriceAlerts = false
    @State private var shortcutScanner = false
    @State private var navigationReset = UUID()

    var body: some View {
        Group {
            if model.storageError {
                VStack(spacing: 20) {
                    VeltrixMark().fill(theme.highlight).frame(width: 45, height: 45)
                    EmptyPanel(icon: "externaldrive.badge.exclamationmark", title: "Local storage unavailable",
                               detail: "Reopen VELTRIX to retry. Your saved files have been kept.")
                }
                .padding(24)
            } else if lock.locked {
                LockScreen()
            } else {
                content
            }
        }
        .allowsHitTesting(!showSplash)
        .accessibilityHidden(showSplash)
        .overlay {
            if showSplash {
                LaunchScreen()
                    .allowsHitTesting(false)
                    .transition(reduceMotion ? .identity : .opacity)
                    .accessibilityIdentifier("launch.screen")
                    .task {
                        let capture = UITestMode.fixture("--capture-launch")
                        try? await Task.sleep(nanoseconds: capture ? 3_500_000_000 : 360_000_000)
                        guard !Task.isCancelled else { return }
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.24)) { showSplash = false }
                    }
            }
        }
        .animation(reduceMotion || lock.locked ? nil : .easeOut(duration: 0.25), value: lock.locked)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background.ignoresSafeArea())
        .overlay {
            if phase != .active && !lock.locked {
                theme.background.ignoresSafeArea()
                    .overlay(VeltrixMark().fill(theme.highlight).frame(width: 52, height: 52))
                    .accessibilityHidden(true)
            }
        }
        .onChange(of: phase) { next in
            switch next {
            case .active:
                lock.becomeActive()
                if !lock.locked { model.start(); openPendingNotification(); openPendingShortcut() }
                else { attemptAutomaticUnlock() }
            case .background: lock.enteredBackground(); model.stop()
            default: break
            }
        }
        .onChange(of: lock.locked) { value in
            if value {
                model.stop()
                showSearch = false
                showEarn = false
                notificationEntry = nil
                notificationOrder = nil
                showPriceAlerts = false
                shortcutScanner = false
            } else if phase == .active {
                model.start()
                openPendingNotification()
                openPendingShortcut()
                openWidgetRoute()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in lock.becomeActive() }
        .onReceive(NotificationCenter.default.publisher(for: NotificationDelegate.opened)) { _ in openPendingNotification() }
        .onReceive(NotificationCenter.default.publisher(for: AppShortcut.opened)) { _ in openPendingShortcut() }
        .onChange(of: showSplash) { visible in
            if !visible { openPendingNotification(); openPendingShortcut(); openWidgetRoute(); attemptAutomaticUnlock() }
        }
        .onChange(of: model.onSet) { enabled in if !enabled { openPendingNotification() } }
        .onAppear {
            NotificationDelegate.lockState = lock
            if phase == .active && !lock.locked { model.start(); openPendingNotification(); openPendingShortcut() }
            else { attemptAutomaticUnlock() }
        }
        .onOpenURL { url in
            guard url.scheme == "veltrix" else { return }
            widgetRoute = url
            openWidgetRoute()
        }
        .sheet(isPresented: $showEarn) {
            NavigationStack {
                EarnScreen().toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showEarn = false } } }
            }
        }
        .sheet(item: $notificationEntry) { entry in
            NavigationStack {
                EntryScreen(entry: entry)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { notificationEntry = nil } } }
            }
        }
        .sheet(item: $notificationOrder) { order in
            NavigationStack {
                PageScroll {
                    LimitOrderSummary(order: model.ledger.portfolios.lazy.compactMap {
                        $0.orders.first { $0.id == order.id }
                    }.first ?? order)
                }
                .navigationTitle("Operation details")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { notificationOrder = nil } } }
            }
        }
        .sheet(isPresented: $showPriceAlerts) {
            NavigationStack {
                PriceAlertsScreen()
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { showPriceAlerts = false } } }
            }
        }
        .fullScreenCover(isPresented: $shortcutScanner) { QRScanner() }
    }

    private func openWidgetRoute() {
        guard !showSplash, !lock.locked, !model.storageError, !model.onSet, let url = widgetRoute else { return }
        widgetRoute = nil
        switch url.host {
        case "portfolio": tab = .portfolio; navigationReset = UUID()
        case "markets": tab = .markets; navigationReset = UUID()
        case "earn": showEarn = true
        case "activity":
            guard let id = UUID(uuidString: url.lastPathComponent) else { return }
            if let entry = model.openNotification(id) { notificationEntry = entry }
            else { notificationOrder = model.ledger.portfolios.lazy.compactMap { $0.orders.first { $0.id == id } }.first }
        default: break
        }
    }

    private func attemptAutomaticUnlock() {
        guard !showSplash, phase == .active, lock.locked, lock.enabled, !model.storageError else { return }
        Task {
            if UITestMode.fixture("--capture-lock-background") {
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                guard !Task.isCancelled, UIApplication.shared.applicationState == .active else { return }
            }
            await lock.tryAutomaticUnlock()
        }
    }

    private func openPendingShortcut() {
        guard !showSplash, !lock.locked, phase == .active, !model.storageError,
              let raw = UserDefaults.standard.string(forKey: AppShortcut.defaultsKey),
              let shortcut = AppShortcut(rawValue: raw) else { return }
        UserDefaults.standard.removeObject(forKey: AppShortcut.defaultsKey)
        switch shortcut {
        case .scan: shortcutScanner = true
        case .explore: tab = .markets; navigationReset = UUID()
        }
    }

    private func openPendingNotification() {
        guard !showSplash, !lock.locked, phase == .active, !model.storageError, !model.onSet,
              let value = UserDefaults.standard.string(forKey: "pendingOperationNotification") else { return }
        UserDefaults.standard.removeObject(forKey: "pendingOperationNotification")
        if let id = UUID(uuidString: value) {
            notificationEntry = model.openNotification(id)
        } else if value.hasPrefix("stake-") {
            showEarn = true
        } else if value.hasPrefix("price-") {
            showPriceAlerts = true
        } else if value.hasPrefix("order-"), let id = UUID(uuidString: String(value.dropFirst(6))) {
            notificationOrder = model.ledger.portfolios.lazy.compactMap { $0.orders.first { $0.id == id } }.first
        }
    }

    private var content: some View {
        NavigationStack {
            Group {
                switch tab {
                case .portfolio: PortfolioScreen()
                case .markets: MarketsScreen()
                case .operations: OperationsScreen()
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !keyboardVisible {
                    VeltrixGlassTabBar(selection: $tab) { showSearch = true }
                        .background(alignment: .bottom) {
                            LinearGradient(colors: [theme.background.opacity(0), theme.background.opacity(0.74), theme.background],
                                           startPoint: .top, endPoint: .bottom)
                                .ignoresSafeArea(edges: .bottom).allowsHitTesting(false)
                        }
                }
            }
            .navigationDestination(for: Asset.self) { AssetScreen(asset: $0) }
        }
        .id(String(model.onSet) + navigationReset.uuidString)
        .overlay(alignment: .top) {
            if let toast = model.toast {
                Label(toast, systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .glass(radius: 15)
                    .padding(.top, 6)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion || UITestMode.enabled ? nil : .easeOut(duration: 0.2), value: model.toast)
        .sheet(isPresented: $showSearch) {
            NavigationStack {
                GlobalSearchScreen()
                    .navigationDestination(for: Asset.self) { AssetScreen(asset: $0) }
            }
        }
        .alert("VELTRIX", isPresented: .init(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK", role: .cancel) { model.error = nil }
        } message: { Text(verbatim: model.error ?? "") }
    }

}

private struct VeltrixGlassTabBar: View {
    @Environment(\.veltrixTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selection: Destination
    let openSearch: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            HStack(spacing: 0) {
                ForEach(Destination.allCases, id: \.self) { destination in
                    Button {
                        guard destination != selection else { return }
                        Feedback.tap()
                        selection = destination
                    } label: {
                        Image(systemName: destination.icon)
                            .font(.system(size: 25, weight: .regular))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(destination.name))
                    .accessibilityIdentifier("tab." + destination.rawValue)
                    .accessibilityAddTraits(selection == destination ? .isSelected : [])
                }
            }
            .background {
                GeometryReader { proxy in
                    let destinations = Destination.allCases
                    let slot = proxy.size.width / CGFloat(destinations.count)
                    let index = destinations.firstIndex(of: selection) ?? 0
                    Capsule()
                        .fill(theme.navigationSelection)
                        .frame(width: slot, height: proxy.size.height)
                        .offset(x: CGFloat(index) * slot)
                        .animation(reduceMotion || UITestMode.enabled ? nil : .easeInOut(duration: 0.23),
                                   value: selection)
                }
                .allowsHitTesting(false)
            }
            .padding(4)
            .glass(radius: 28)

            Button {
                Feedback.tap()
                openSearch()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 25, weight: .regular))
                    .frame(width: 56, height: 56)
                    .contentShape(Circle())
                    .glass(radius: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Search"))
            .accessibilityIdentifier("tab.search")
        }
        .foregroundStyle(theme.text)
        .frame(maxWidth: 460)
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
    }
}

private struct LaunchScreen: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image("LaunchMark").resizable().frame(width: 68, height: 68).accessibilityHidden(true)
            Text(verbatim: "VELTRIX").font(.caption.weight(.semibold)).tracking(8).foregroundStyle(.white)
                .offset(y: 67)
        }
    }
}
