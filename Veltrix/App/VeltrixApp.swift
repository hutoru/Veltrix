import SwiftUI
import UIKit

@main @MainActor
struct VeltrixApp: App {
    @StateObject private var model: VeltrixModel
    @StateObject private var lock: AppLock

    init() {
        let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing") && _isDebugAssertConfiguration()
        let defaults = testing ? (UserDefaults(suiteName: "Veltrix-UI-Tests") ?? .standard) : .standard
        if testing { defaults.removePersistentDomain(forName: "Veltrix-UI-Tests") }
        _model = StateObject(wrappedValue: VeltrixModel(defaults: defaults, testing: testing))
        _lock = StateObject(wrappedValue: AppLock(defaults: defaults, testing: testing))
    }

    var body: some Scene {
        WindowGroup {
            VeltrixRoot()
                .environmentObject(model)
                .environmentObject(lock)
                .preferredColorScheme(model.theme == "system" ? nil : (model.theme == "light" ? .light : .dark))
                .tint(.vxHighlight)
        }
    }
}

private enum Destination: String, CaseIterable {
    case portfolio, markets, cards, activity, settings
    var name: LocalizedStringKey {
        switch self {
        case .portfolio: return "Portfolio"
        case .markets: return "Markets"
        case .cards: return "Cards"
        case .activity: return "Activity"
        case .settings: return "Settings"
        }
    }
    var icon: String {
        switch self {
        case .portfolio: return "square.grid.2x2"
        case .markets: return "chart.xyaxis.line"
        case .cards: return "creditcard"
        case .activity: return "list.bullet.rectangle"
        case .settings: return "slider.horizontal.3"
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
            case .active: lock.becomeActive(); if !lock.locked { model.start() }
            case .background: lock.enteredBackground(); model.stop()
            default: break
            }
        }
        .onChange(of: lock.locked) { value in
            if value { model.stop() }
            else if phase == .active { model.start() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
        }
        .onAppear { if phase == .active && !lock.locked { model.start() } }
    }

    private var content: some View {
        NavigationStack {
            Group {
                switch tab {
                case .portfolio: PortfolioScreen()
                case .markets: MarketsScreen()
                case .cards: CardsScreen()
                case .activity: ActivityScreen()
                case .settings: SettingsScreen()
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
        .id(tab)
        .alert("VELTRIX · Simulation", isPresented: .init(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK", role: .cancel) { model.error = nil }
        } message: { Text(verbatim: model.error ?? "") }
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(Destination.allCases, id: \.self) { destination in
                Button {
                    guard destination != tab else { return }
                    Feedback.tap()
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82)) { tab = destination }
                } label: {
                    VStack(spacing: 5) {
                        if destination == .portfolio {
                            VeltrixMark().fill().frame(width: 19, height: 19)
                        } else {
                            Image(systemName: destination.icon).font(.system(size: 17, weight: .medium)).frame(height: 19)
                        }
                        Text(destination.name).font(.system(size: 9, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.65)
                    }
                    .foregroundStyle(tab == destination ? Color.vxHighlight : Color.vxMuted)
                    .frame(maxWidth: .infinity, minHeight: 49)
                    .background(tab == destination ? Color.vxAccent.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 15))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tab." + destination.rawValue)
                .accessibilityAddTraits(tab == destination ? .isSelected : [])
            }
        }
        .padding(5)
        .background {
            Color.clear.glass(radius: 22).allowsHitTesting(false)
        }
        .frame(maxWidth: 600)
        .padding(.horizontal, 13)
        .padding(.bottom, 4)
    }
}

private struct LockScreen: View {
    @EnvironmentObject private var lock: AppLock
    @State private var pin = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            VeltrixMark().fill(Color.vxHighlight).frame(width: 54, height: 54)
            Text("Simulation locked").font(.largeTitle.bold())
            SimBadge()
            if lock.hasPIN {
                SecureField("PIN", text: $pin)
                    .textContentType(.password)
                    .keyboardType(.numberPad)
                    .padding()
                    .background(Color.vxCard, in: RoundedRectangle(cornerRadius: 15))
                Button("Unlock") {
                    Task { await lock.unlock(pin: pin); pin = "" }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(pin.isEmpty || lock.busy)
                if let retryAt = lock.retryAt, retryAt > Date() {
                    Text(retryAt, style: .timer).font(.footnote.monospacedDigit())
                }
            }
            if lock.biometrics {
                Button { Task { await lock.unlockWithDevice() } } label: {
                    Label("Use device authentication", systemImage: "faceid").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(lock.busy)
            }
            if let error = lock.error { Text(verbatim: error).font(.footnote).foregroundStyle(Color.vxDown) }
        }
        .padding(26)
        .frame(maxWidth: 480)
    }
}
