import SwiftUI
import UIKit

@main @MainActor
struct VeltrixApp: App {
    @UIApplicationDelegateAdaptor(NotificationDelegate.self) private var notificationDelegate
    @StateObject private var model: VeltrixModel
    @StateObject private var lock: AppLock
    private let defaults: UserDefaults

    init() {
        let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing") && _isDebugAssertConfiguration()
        let defaults = testing ? (UserDefaults(suiteName: "Veltrix-UI-Tests") ?? .standard) : .standard
        if testing { defaults.removePersistentDomain(forName: "Veltrix-UI-Tests") }
        self.defaults = defaults
        _model = StateObject(wrappedValue: VeltrixModel(defaults: defaults, testing: testing))
        _lock = StateObject(wrappedValue: AppLock(defaults: defaults, testing: testing))
    }

    var body: some Scene {
        WindowGroup {
            VeltrixRoot()
                .environmentObject(model)
                .environmentObject(lock)
                .defaultAppStorage(defaults)
                .preferredColorScheme(model.theme == "system" ? nil : (model.theme == "light" ? .light : .dark))
                .tint(.vxHighlight)
        }
    }
}

private enum Destination: String, CaseIterable {
    case portfolio, markets, trade, activity, profile
    var name: LocalizedStringKey {
        switch self {
        case .portfolio: return "Home"
        case .markets: return "Explore"
        case .trade: return "Trade"
        case .activity: return "Activity"
        case .profile: return "Profile"
        }
    }
    var icon: String {
        switch self {
        case .portfolio: return "square.grid.2x2"
        case .markets: return "chart.xyaxis.line"
        case .trade: return "arrow.left.arrow.right"
        case .activity: return "list.bullet.rectangle"
        case .profile: return "person.crop.circle"
        }
    }
}

struct VeltrixRoot: View {
    @EnvironmentObject private var model: VeltrixModel
    @EnvironmentObject private var lock: AppLock
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tab = Destination.portfolio
    @State private var keyboardVisible = false
    @State private var showSplash = !_isDebugAssertConfiguration()
        || !ProcessInfo.processInfo.arguments.contains("--ui-testing")
        || ProcessInfo.processInfo.arguments.contains("--capture-launch")
    @State private var tradeMenu = false
    @State private var trade: TradeIntent?
    @State private var notificationEntry: Entry?
    @State private var shortcutScanner = false
    @State private var navigationReset = UUID()

    var body: some View {
        Group {
            if model.storageError {
                VStack(spacing: 20) {
                    VeltrixMark().fill(Color.vxHighlight).frame(width: 45, height: 45)
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
                        let capture = _isDebugAssertConfiguration() && ProcessInfo.processInfo.arguments.contains("--capture-launch")
                        try? await Task.sleep(nanoseconds: capture ? 3_500_000_000 : (reduceMotion ? 300_000_000 : 950_000_000))
                        guard !Task.isCancelled else { return }
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.24)) { showSplash = false }
                    }
            }
        }
        .animation(reduceMotion || lock.locked ? nil : .easeOut(duration: 0.25), value: lock.locked)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.vxBackground.ignoresSafeArea())
        .overlay {
            if phase != .active {
                Color.vxBackground.ignoresSafeArea()
                    .overlay(VeltrixMark().fill(Color.vxHighlight).frame(width: 52, height: 52))
                    .accessibilityHidden(true)
            }
        }
        .onChange(of: phase) { next in
            switch next {
            case .active: lock.becomeActive(); if !lock.locked { model.start(); openPendingNotification(); openPendingShortcut() }
            case .background: lock.enteredBackground(); model.stop()
            default: break
            }
        }
        .onChange(of: lock.locked) { value in
            if value {
                model.stop()
                trade = nil
                notificationEntry = nil
                shortcutScanner = false
            } else if phase == .active {
                model.start()
                openPendingNotification()
                openPendingShortcut()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
        }
        .onReceive(NotificationCenter.default.publisher(for: NotificationDelegate.opened)) { _ in openPendingNotification() }
        .onReceive(NotificationCenter.default.publisher(for: AppShortcut.opened)) { _ in openPendingShortcut() }
        .onChange(of: showSplash) { visible in if !visible { openPendingShortcut() } }
        .onAppear { if phase == .active && !lock.locked { model.start(); openPendingNotification(); openPendingShortcut() } }
        .task {
            #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--ui-testing") && arguments.contains("--locked-fixture") && !lock.hasPIN {
                if await lock.updatePIN(current: "", new: "2468") { lock.lockNow() }
            }
            #endif
        }
        .sheet(item: $notificationEntry) { entry in
            NavigationStack {
                EntryScreen(entry: entry)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { notificationEntry = nil } } }
            }
        }
        .fullScreenCover(isPresented: $shortcutScanner) { QRScanner() }
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
        guard !lock.locked, phase == .active, !model.storageError, !model.onSet,
              let value = UserDefaults.standard.string(forKey: "pendingOperationNotification"),
              let id = UUID(uuidString: value) else { return }
        UserDefaults.standard.removeObject(forKey: "pendingOperationNotification")
        notificationEntry = model.openNotification(id)
    }

    private var content: some View {
        NavigationStack {
            Group {
                switch tab {
                case .portfolio: PortfolioScreen()
                case .markets: MarketsScreen()
                case .trade: PortfolioScreen()
                case .activity: ActivityScreen()
                case .profile: ProfileScreen()
                }
            }
            .navigationDestination(for: Asset.self) { AssetScreen(asset: $0) }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 7) {
                    if let toast = model.toast {
                        Label(toast, systemImage: "checkmark.circle.fill")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .glass(radius: 15)
                            .transition(.opacity)
                    }
                    if !keyboardVisible { tabBar }
                }
                .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.8), value: model.toast)
            }
        }
        .id(tab.rawValue + String(model.onSet) + navigationReset.uuidString)
        .confirmationDialog("Trade", isPresented: $tradeMenu, titleVisibility: .visible) {
            ForEach(TradeAction.allCases) { action in
                Button(action.title) { trade = TradeIntent(action: action) }
            }
        }
        .fullScreenCover(item: $trade) { TradeScreen(intent: $0) }
        .alert("VELTRIX", isPresented: .init(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK", role: .cancel) { model.error = nil }
        } message: { Text(verbatim: model.error ?? "") }
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(Destination.allCases, id: \.self) { destination in
                Button {
                    if destination == .trade { Feedback.tap(); tradeMenu = true; return }
                    guard destination != tab else { return }
                    Feedback.tap()
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82)) { tab = destination }
                } label: {
                    VStack(spacing: 5) {
                        if destination == .portfolio {
                            VeltrixMark().fill().frame(width: 19, height: 19)
                        } else {
                            Image(systemName: destination.icon).font(.system(size: 17, weight: .regular)).frame(height: 19)
                        }
                        Text(destination.name).font(.system(size: 9, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.65)
                    }
                    .foregroundStyle(tab == destination ? Color.vxText : Color.vxMuted)
                    .frame(maxWidth: .infinity, minHeight: 49)
                    .overlay(alignment: .top) { if tab == destination { Capsule().fill(Color.vxAccent).frame(width: 16, height: 2) } }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tab." + destination.rawValue)
                .accessibilityAddTraits(tab == destination ? .isSelected : [])
            }
        }
        .padding(.top, 4)
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity)
        .background(Color.vxBackground.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Color.vxSeparator).frame(height: 1).allowsHitTesting(false) }
    }
}

private struct LaunchScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 24) {
                VeltrixMark().fill(.white).frame(width: 68, height: 68)
                    .scaleEffect(appeared || reduceMotion ? 1 : 0.85)
                Text(verbatim: "VELTRIX").font(.caption.weight(.semibold)).tracking(8).foregroundStyle(.white)
            }
            .opacity(appeared || reduceMotion ? 1 : 0)
        }
        .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.5)) { appeared = true } }
    }
}

private struct LockScreen: View {
    @EnvironmentObject private var lock: AppLock
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("profileName") private var name = ""
    @State private var pin = ""
    @State private var shake = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ProfileAvatar(size: 72)
                Text("Welcome back").font(.largeTitle.weight(.semibold))
                Text(verbatim: name.isEmpty ? L.text("My profile") : name).font(.headline).foregroundStyle(Color.vxMuted)
                if lock.hasPIN {
                    HStack(spacing: 12) {
                        ForEach(0..<max(4, pin.count), id: \.self) { index in
                            Circle().fill(index < pin.count ? Color.vxText : Color.vxSeparator).frame(width: 9, height: 9)
                        }
                    }
                    .frame(height: 28)
                    .offset(x: shake && !reduceMotion ? 8 : 0)
                    .accessibilityElement()
                    .accessibilityLabel(Text("PIN"))
                    .accessibilityValue(Text(verbatim: String(pin.count)))
                    NumericPad(allowsDecimal: false, onInput: { digit in
                        if pin.count < 8 { pin.append(digit) }
                    }, onDelete: { if !pin.isEmpty { pin.removeLast() } }).disabled(lock.busy)
                    Button("Unlock") {
                        Task {
                            await lock.unlock(pin: pin)
                            pin = ""
                            if !lock.locked { Feedback.success() }
                            else {
                                Feedback.failure()
                                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.08)) { shake = true }
                                try? await Task.sleep(nanoseconds: 80_000_000)
                                withAnimation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.36)) { shake = false }
                            }
                        }
                    }.buttonStyle(PrimaryButtonStyle()).disabled(pin.count < 4 || lock.busy)
                    if let retryAt = lock.retryAt, retryAt > Date() {
                        Text(retryAt, style: .timer).font(.footnote.monospacedDigit())
                    }
                }
                if lock.biometrics {
                    Button {
                        Task { await lock.unlockWithDevice(); if !lock.locked { Feedback.success() } }
                    } label: { Label("Use device authentication", systemImage: "faceid") }
                    .buttonStyle(.bordered).disabled(lock.busy)
                }
                if let error = lock.error { Text(verbatim: error).font(.footnote).foregroundStyle(Color.vxDown) }
            }
            .frame(maxWidth: 370).padding(24)
            .frame(maxWidth: .infinity)
        }
    }
}
