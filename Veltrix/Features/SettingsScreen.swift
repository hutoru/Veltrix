import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct SettingsScreen: View {
    @Environment(\.veltrixTheme) private var theme
    @EnvironmentObject private var model: VeltrixModel
    @EnvironmentObject private var lock: AuthCoordinator
    @Environment(\.scenePhase) private var notificationPhase
    @ObservedObject private var systemNotifications = NotificationService.shared
    @Environment(\.openURL) private var openURL
    @AppStorage("profileName") private var profileName = ""
    @AppStorage("profileUsername") private var username = ""
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @State private var panel: SettingsPanel?
    @State private var export = false
    @State private var search = ""
    @State private var takeFile = false
    @State private var backup = BackupFile()
    @State private var incoming: Data?
    @State private var reset = false
    @State private var notificationPermission = false

    var body: some View {
        List {
            if matches("Account", "Display name", "Username") {
                Section("Account") {
                    TextField("Display name", text: $profileName)
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: username) { value in
                            let cleaned = String(value.filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }.prefix(24))
                            if cleaned != value { username = cleaned }
                        }
                    LabeledContent("Portfolio created", value: model.portfolio.createdAt.formatted(date: .abbreviated, time: .omitted))
                }
            }
            if matches("Preferences", "Display currency", "Theme", "App language", "Haptic feedback", "Hide balances") {
                Section("Preferences") {
                    display.listRowBackground(theme.surface)
                    NavigationLink {
                        AppearanceSettings()
                    } label: {
                        LabeledContent("Theme") { Text(model.theme.title).foregroundStyle(theme.muted) }
                    }
                    .listRowBackground(theme.surface)
                    .accessibilityIdentifier("settings.theme")
                    Link(destination: URL(string: UIApplication.openSettingsURLString)!) {
                        Label("App language", systemImage: "globe")
                    }
                    Toggle("Haptic feedback", isOn: $hapticsEnabled)
                    NavigationLink("Preferred operations") { QuickActionsSettings() }
                }
            }
            if matches("Portfolio controls", "Create portfolio", "Edit holdings") {
                Section { portfolioControls.listRowBackground(theme.surface) }
            }
            if matches("Notifications", "Price alerts", "Live Activities", "Widgets") {
                Section("Notifications") {
                    Toggle("Live Activities", isOn: $model.liveActivities)
                    Toggle("Hide Live Activity amounts", isOn: $model.liveActivityPrivacy)
                    Toggle("Hide widget amounts", isOn: $model.widgetPrivacy)
                    Toggle("iOS notifications", isOn: Binding(get: { model.pushOperations }, set: updateNotifications))
                    Toggle("Hide amounts in notifications", isOn: $model.privateNotifications)
                    Toggle("Hide balance in notifications", isOn: $model.hideNotificationBalance)
                    Text("iOS controls which details appear on the Lock Screen.").font(.footnote).foregroundStyle(theme.muted)
                    if model.pushOperations {
                        if systemNotifications.authorizationStatus == .notDetermined {
                            Button("Allow notifications") { requestNotificationPermission() }
                        } else {
                            settingsButton("Open iOS notification settings", "bell.badge") { openNotificationSettings() }
                            LabeledContent("Show previews", value: previewStatus)
                        }
                        Button("Send test notification") { systemNotifications.sendTest() }
                            .accessibilityIdentifier("notifications.test")
                        Text(notificationStatus).font(.footnote).foregroundStyle(theme.muted)
                            .accessibilityIdentifier("notifications.authorization")
                        if let error = systemNotifications.error {
                            Text(verbatim: error).font(.footnote).foregroundStyle(theme.negative)
                        } else if let delivery = systemNotifications.lastDelivery {
                            Text(delivery == .delivered ? "Last notification delivered" :
                                 (delivery == .queued ? "Last notification accepted by iOS" : "Notification alerts are unavailable"))
                                .font(.caption).foregroundStyle(theme.muted)
                                .accessibilityIdentifier("notifications.delivery")
                        }
                    }
                    NavigationLink("Notification history") { NotificationScreen() }
                    NavigationLink("Price alerts") { PriceAlertsScreen() }
                }.disabled(model.onSet)
            }
            if matches("Cards") {
                Section("Cards") { NavigationLink("Cards") { CardsScreen() } }
            }
            if matches("Security", "Require device authentication", "Lock after leaving the app") {
                Section("Security") { security.listRowBackground(theme.surface) }
            }
            if matches("Data", "Local backup", "Export backup", "Import backup", "Adjustment journal") {
                Section("Data") {
                    backups.listRowBackground(theme.surface)
                    NavigationLink("Adjustment journal") { ActivityScreen(adjustmentsOnly: true) }
                }
            }
            if matches("Support", "App news, updates and announcements.", "Telegram") {
                Section("Support") {
                    Button {
                        guard let url = URL(string: "https://t.me/veltrixlarpwallet") else { return }
                        Feedback.tap()
                        openURL(url)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "paperplane.fill").foregroundStyle(theme.highlight)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: "VELTRIX News").font(.subheadline.weight(.semibold))
                                Text("App news, updates and announcements.").font(.caption).foregroundStyle(theme.muted)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(theme.muted)
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            if matches("Portfolio workspace", "Separate portfolio") {
                Section("Portfolio workspace") {
                    Toggle("Separate portfolio", isOn: Binding(get: { model.onSet }, set: model.setOnSet))
                        .listRowBackground(theme.surface)
                }
            }
            Section {
                NavigationLink("About VELTRIX") {
                    PageScroll {
                        Text(verbatim: "Beyond the balance.").font(.title2.weight(.semibold))
                        sources
                        NavigationLink("What’s new") { changes }
                    }.navigationTitle("About VELTRIX")
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "VELTRIX").font(.footnote.weight(.semibold)).tracking(3)
                    Text(verbatim: "Beyond the balance.")
                    if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                        Text("Version \(version)")
                    }
                    Text(verbatim: "© 2026 VELTRIX")
                }.foregroundStyle(theme.muted)
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $search, prompt: "Search settings")
        .navigationTitle("Settings")
        .task(id: notificationPhase) {
            if notificationPhase == .active { await systemNotifications.refresh() }
        }
        .scrollContentBackground(.hidden)
        .background(theme.background)
        .sheet(item: $panel) { SettingsForm(panel: $0) }
        .alert("Notifications are disabled", isPresented: $notificationPermission) {
            Button("Open Settings") {
                openNotificationSettings()
            }
            Button("Cancel", role: .cancel) {}
        }
        .fileExporter(isPresented: $export, document: backup, contentType: .json, defaultFilename: "VELTRIX-Backup") { result in
            if case let .failure(error) = result { model.error = Display.error(error) }
        }
        .fileImporter(isPresented: $takeFile, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                _ = try SimulationBackup.load(data)
                incoming = data
            } catch { model.error = Display.error(error) }
        }
        .confirmationDialog("Replace portfolio data?", isPresented: .init(get: { incoming != nil }, set: { if !$0 { incoming = nil } }),
                            titleVisibility: .visible, presenting: incoming) { data in
            Button("Replace with backup", role: .destructive) {
                _ = model.importBackup(data)
                incoming = nil
            }
            Button("Cancel", role: .cancel) { incoming = nil }
        } message: { _ in Text("The backup replaces all portfolios, card balances, orders and activity on this device.") }
        .confirmationDialog("Reset selected portfolio?", isPresented: $reset, titleVisibility: .visible) {
            Button("Reset portfolio", role: .destructive) { _ = model.execute(.resetPortfolio) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The selected portfolio’s balance, positions, orders, cards and activity will be cleared.")
        }
    }

    private var changes: some View {
        PageScroll {
            Text(verbatim: "9.3.0 · Experience Update").font(.title2.weight(.semibold))
            Text("Portfolio insights, a redesigned Operations Center, staking, widgets and Live Activities.")
                .font(.subheadline).foregroundStyle(theme.muted)
        }.navigationTitle("What’s new").navigationBarTitleDisplayMode(.inline)
    }

    private func matches(_ terms: String...) -> Bool {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || terms.contains { $0.localizedCaseInsensitiveContains(query) || L.text($0).localizedCaseInsensitiveContains(query) }
    }

    private var previewStatus: String {
        switch systemNotifications.previewSetting {
        case .always: return L.text("Always")
        case .whenAuthenticated: return L.text("When unlocked")
        case .never: return L.text("Never")
        @unknown default: return "—"
        }
    }

    private func updateNotifications(_ enabled: Bool) {
        model.pushOperations = enabled
        if enabled {
            requestNotificationPermission()
        } else {
            NotificationService.clear()
        }
    }

    private func requestNotificationPermission() {
        Task {
            _ = await systemNotifications.authorize()
            notificationPermission = systemNotifications.authorizationStatus == .denied
        }
    }

    private func openNotificationSettings() {
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
    }

    private var notificationStatus: LocalizedStringKey {
        switch systemNotifications.authorizationStatus {
        case .notDetermined: return "Notification permission has not been requested"
        case .denied: return "Notifications are blocked by iOS"
        default:
            if !systemNotifications.alertsEnabled { return "Banners are off in iOS Settings" }
            return systemNotifications.soundsEnabled ? "Alerts and sound enabled" : "Alerts enabled, sound off"
        }
    }

    private var portfolioControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            heading("Portfolio controls")
            Picker("Active portfolio", selection: .init(get: { model.ledger.selected }, set: { _ = model.execute(.selectPortfolio($0)) })) {
                ForEach(model.ledger.portfolios) { Text(verbatim: $0.name).tag($0.id) }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            settingsButton("Create portfolio", "plus.square.on.square") { panel = .newPortfolio }
            settingsButton("Set cash balance", "banknote") { panel = .cash }
            settingsButton("Edit holdings", "chart.pie") { panel = .positions }
            settingsButton("Trading fee", "percent") { panel = .fee }
            settingsButton("Reset portfolio", "arrow.counterclockwise", destructive: true) { reset = true }
        }

    }

    private var display: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Display currency", selection: $model.currency) {
                ForEach(Fiat.currencies, id: \.self) { code in
                    Text(verbatim: code + " · " + (Locale.current.localizedString(forCurrencyCode: code) ?? code)).tag(code)
                }
            }
            .pickerStyle(.navigationLink)
            Stepper("Decimal places · \(model.digits)", value: $model.digits, in: 0...12)
            Button {
                model.hide.toggle()
                Feedback.tap()
            } label: {
                HStack {
                    Text("Hide balances")
                    Spacer()
                    Image(systemName: model.hide ? "eye.slash.fill" : "eye")
                        .foregroundStyle(theme.highlight)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.hide")
            .accessibilityAddTraits(model.hide ? .isSelected : [])
        }

    }

    private var security: some View {
        VStack(alignment: .leading, spacing: 11) {
            Toggle("Require device authentication", isOn: .init(get: { lock.enabled }, set: { next in
                Task { await lock.setEnabled(next) }
            }))
            .disabled(lock.busy)
            Text("Unlock using Face ID, Touch ID or your iPhone passcode.")
                .font(.caption).foregroundStyle(theme.muted)
            Picker("Lock after leaving the app", selection: .init(get: { lock.timeout }, set: { lock.setTimeout($0) })) {
                Text("Immediately").tag(0)
                Text("30 seconds").tag(30)
                Text("1 minute").tag(60)
                Text("5 minutes").tag(300)
                Text("15 minutes").tag(900)
            }
            .pickerStyle(.menu)
            if lock.enabled { settingsButton("Lock now", "lock.fill") { lock.lockNow() } }
            if let error = lock.error { Text(verbatim: error).font(.caption).foregroundStyle(theme.negative) }
        }

    }

    private var backups: some View {
        VStack(alignment: .leading, spacing: 6) {
            heading("Local backup")
            settingsButton("Export backup", "square.and.arrow.up") {
                do { backup = BackupFile(data: try model.exportBackup()); export = true }
                catch { model.error = Display.error(error) }
            }
            settingsButton("Import backup", "square.and.arrow.down") { takeFile = true }
            Text("The backup contains balances and activity. Store it somewhere private.")
                .font(.caption).foregroundStyle(theme.muted)
        }

    }

    private var sources: some View {
        VStack(alignment: .leading, spacing: 9) {
            heading("Data sources")
            settingsButton("Optional CoinGecko API key", "key") { panel = .key }
            Link("Market data by CoinGecko", destination: URL(string: "https://www.coingecko.com/")!)
            Link("Exchange prices and candles by Kraken", destination: URL(string: "https://www.kraken.com/")!)
            Link("Fiat reference rates by Frankfurter", destination: URL(string: "https://frankfurter.dev/")!)
        }
        .font(.footnote)

    }

    private func heading(_ title: LocalizedStringKey) -> some View {
        Text(title).font(.headline).accessibilityAddTraits(.isHeader).padding(.bottom, 3)
    }

    private func settingsButton(_ title: LocalizedStringKey, _ icon: String,
                                destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: icon)
                Spacer()
                Image(systemName: "chevron.right").font(.caption)
            }
            .font(.subheadline.weight(.medium))
            .frame(minHeight: 41)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(destructive ? theme.negative : theme.highlight)
    }
}

private struct AppearanceSettings: View {
    @Environment(\.veltrixTheme) private var theme
    @EnvironmentObject private var model: VeltrixModel

    var body: some View {
        PageScroll(spacing: 10) {
            NavigationLink { AppIconSettings() } label: {
                OperationsRow(title: "App icon", icon: "app").panel(padding: 10)
            }.buttonStyle(.plain)
            ForEach(VeltrixAppearance.allCases) { appearance in
                let selected = model.theme == appearance
                Button {
                    guard !selected else { return }
                    model.theme = appearance
                    Feedback.tap()
                } label: {
                    HStack(spacing: 14) {
                        AppearancePreview(appearance: appearance)
                        Text(appearance.title).font(.body.weight(.medium))
                        Spacer(minLength: 4)
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.body.weight(.medium))
                            .foregroundStyle(selected ? theme.accent : theme.muted)
                            .accessibilityHidden(true)
                    }
                    .padding(10)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("theme." + appearance.rawValue)
            }
        }
        .navigationTitle("Theme")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AppearancePreview: View {
    let appearance: VeltrixAppearance

    var body: some View {
        HStack(spacing: 0) {
            swatch(VeltrixTheme(appearance == .system ? .obsidian : appearance))
            if appearance == .system { swatch(VeltrixTheme(.light)) }
        }
        .frame(width: 76, height: 43)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(true)
    }

    private func swatch(_ palette: VeltrixTheme) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Capsule().fill(palette.text).frame(width: 16, height: 3)
            HStack {
                Circle().fill(palette.accent).frame(width: 5, height: 5)
                Spacer(minLength: 0)
            }
            .padding(3)
            .background(palette.elevated, in: RoundedRectangle(cornerRadius: 3))
        }
        .padding(5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(palette.background)
    }
}

private struct QuickActionsSettings: View {
    @Environment(\.veltrixTheme) private var theme
    @EnvironmentObject private var model: VeltrixModel

    var body: some View {
        PageScroll {
            ForEach(TradeAction.allCases) { action in
                let selected = model.quickActions.contains(action)
                Toggle(isOn: Binding(get: { selected }, set: { enabled in
                    var actions = model.quickActions
                    if enabled { actions.append(action) }
                    else { actions.removeAll { $0 == action } }
                    model.quickActionIDs = actions.map(\.rawValue)
                })) {
                    Label(action.title, systemImage: action.icon)
                }
                .disabled(selected ? model.quickActions.count == 1 : model.quickActions.count >= 5)
                Divider().overlay(theme.separator)
            }
            Button("Restore default actions") { model.quickActionIDs = VeltrixModel.standardActions.map(\.rawValue) }
                .buttonStyle(.bordered)
        }
        .navigationTitle("Preferred operations")
        .navigationBarTitleDisplayMode(.inline)
    }
}

enum SettingsPanel: String, Identifiable {
    case newPortfolio, cash, positions, fee, key
    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .newPortfolio: return "Create portfolio"
        case .cash: return "Set cash balance"
        case .positions: return "Edit holdings"
        case .fee: return "Trading fee"
        case .key: return "Optional CoinGecko API key"
        }
    }
}

struct SettingsForm: View {
    @Environment(\.veltrixTheme) private var theme
    @EnvironmentObject private var model: VeltrixModel
    @Environment(\.dismiss) private var dismiss
    let panel: SettingsPanel
    @State private var name = ""
    @State private var amount = ""
    @State private var average = ""
    @State private var asset = "bitcoin"
    @State private var secret = ""
    @State private var message: String?
    @State private var processing = false
    @State private var removeHolding = false
    @State private var operation = UUID()

    var body: some View {
        NavigationStack {
            Form {
                Section { fields.listRowBackground(theme.surface) }
                if let error = message {
                    Text(verbatim: error).font(.footnote).foregroundStyle(theme.negative)
                }
                Button("Save") { submit() }
                    .buttonStyle(PrimaryButtonStyle()).listRowBackground(Color.clear)
                    .disabled(processing)
            }
            .scrollContentBackground(.hidden).background(theme.background)
            .scrollDismissesKeyboard(.interactively)
            .dismissibleKeyboard()
            .navigationTitle(panel.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .onAppear(perform: fill)
        .onChange(of: asset) { _ in fillHolding() }
        .confirmationDialog("Remove this holding?", isPresented: $removeHolding, titleVisibility: .visible) {
            Button("Remove holding", role: .destructive) { execute(.setPosition(asset, 0, 0)) }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder private var fields: some View {
        switch panel {
        case .newPortfolio:
            TextField("Portfolio name", text: $name)
            TextField("Initial balance (USD)", text: $amount).keyboardType(.decimalPad)
        case .cash:
            TextField("Cash balance (USD)", text: $amount).keyboardType(.decimalPad)
        case .positions:
            AssetPicker(title: "Asset", asset: $asset)
            TextField("Quantity", text: $amount).keyboardType(.decimalPad)
            TextField("Average purchase price (USD)", text: $average).keyboardType(.decimalPad)
            if model.portfolio.positions[asset] != nil {
                Button("Remove holding", role: .destructive) { removeHolding = true }
            }
        case .fee:
            TextField("Fee (%)", text: $amount).keyboardType(.decimalPad)
            Text("The fee applies to market and limit orders and swaps.")
                .font(.caption).foregroundStyle(theme.muted)
        case .key:
            SecureField("CoinGecko API key", text: $secret).textInputAutocapitalization(.never).autocorrectionDisabled()
            Text("Leave blank and save to use the public feed without a key.")
                .font(.caption).foregroundStyle(theme.muted)
        }
    }

    private func fill() {
        switch panel {
        case .newPortfolio: amount = "10000"
        case .cash: amount = Display.input(model.portfolio.cash)
        case .positions: fillHolding()
        case .fee: amount = Display.input(model.fee * 100)
        case .key: break
        }
    }

    private func fillHolding() {
        let position = model.portfolio.positions[asset]
        amount = Display.input(position?.units ?? 0)
        average = Display.input(position?.average ?? 0)
    }

    private func submit() {
        message = nil
        switch panel {
        case .key:
            processing = true
            Task {
                if await model.setDemoKey(secret) {
                    dismiss()
                    await model.refresh()
                } else {
                    message = model.error
                    model.error = nil
                }
                processing = false
            }
        case .fee:
            if model.setFee(Display.amount(amount)) { dismiss() }
            else { message = model.error; model.error = nil }
        case .newPortfolio, .cash, .positions:
            guard let value = Display.amount(amount) else { message = Display.error(SimulationError.invalidAmount); return }
            switch panel {
            case .newPortfolio: execute(.createPortfolio(name, value))
            case .cash: execute(.setCash(value))
            case .positions:
                guard let average = Display.amount(average) else { message = Display.error(SimulationError.invalidAmount); return }
                execute(.setPosition(asset, value, average))
            default: break
            }
        }
    }

    private func execute(_ command: Command) {
        if model.execute(command, id: operation) { dismiss() }
        else { message = model.error; model.error = nil }
    }
}

private struct BackupFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data = Data()) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else { throw SimulationError.invalidBackup }
        data = contents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
