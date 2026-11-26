import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct SettingsScreen: View {
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
    @State private var takeFile = false
    @State private var backup = BackupFile()
    @State private var incoming: Data?
    @State private var reset = false
    @State private var notificationPermission = false

    var body: some View {
        List {
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
            Section("Preferences") {
                display
                Link(destination: URL(string: UIApplication.openSettingsURLString)!) {
                    Label("App language", systemImage: "globe")
                }
                Toggle("Haptic feedback", isOn: $hapticsEnabled)
                NavigationLink("Preferred operations") { QuickActionsSettings() }
            }
            Section { portfolioControls }
            Section("Filming") {
                Toggle("On-set portfolio", isOn: Binding(get: { model.onSet }, set: model.setOnSet))
                Text("The on-set portfolio has separate balances, cards and activity. Its operations stay in the app.")
                    .font(.caption).foregroundStyle(Color.vxMuted)
            }
            Section("Notifications") {
                Toggle("iOS notifications", isOn: Binding(get: { model.pushOperations }, set: updateNotifications))
                Toggle("Hide amounts in notifications", isOn: $model.privateNotifications)
                Toggle("Hide balance in notifications", isOn: $model.hideNotificationBalance)
                Text("iOS controls which details appear on the Lock Screen.").font(.footnote).foregroundStyle(Color.vxMuted)
                if model.pushOperations {
                    if systemNotifications.authorizationStatus == .notDetermined {
                        Button("Allow notifications") { requestNotificationPermission() }
                    } else {
                        settingsButton("Open iOS notification settings", "bell.badge") { openNotificationSettings() }
                        LabeledContent("Show previews", value: previewStatus)
                    }
                    Button("Send test notification") { systemNotifications.sendTest() }
                        .accessibilityIdentifier("notifications.test")
                    Text(notificationStatus).font(.footnote).foregroundStyle(Color.vxMuted)
                        .accessibilityIdentifier("notifications.authorization")
                    if let error = systemNotifications.error {
                        Text(verbatim: error).font(.footnote).foregroundStyle(Color.vxDown)
                    } else if let delivery = systemNotifications.lastDelivery {
                        Text(delivery == .delivered ? "Last notification delivered" :
                             (delivery == .queued ? "Last notification accepted by iOS" : "Notification alerts are unavailable"))
                            .font(.caption).foregroundStyle(Color.vxMuted)
                            .accessibilityIdentifier("notifications.delivery")
                    }
                }
                NavigationLink("Notification history") { NotificationScreen() }
                NavigationLink("Price alerts") { PriceAlertsScreen() }
            }.disabled(model.onSet)
            Section("Cards") { NavigationLink("Cards") { CardsScreen() } }
            Section("Security") { security }
            Section("Data") {
                backups
                NavigationLink("Adjustment journal") { ActivityScreen(adjustmentsOnly: true) }
            }
            Section("Support") {
                Button {
                    guard let url = URL(string: "https://t.me/veltrixlarpwallet") else { return }
                    Feedback.tap()
                    openURL(url)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "paperplane.fill").foregroundStyle(Color.vxHighlight)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: "VELTRIX News").font(.subheadline.weight(.semibold))
                            Text("App news, updates and announcements.").font(.caption).foregroundStyle(Color.vxMuted)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(Color.vxMuted)
                    }.frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            Section {
                NavigationLink("About VELTRIX") {
                    PageScroll {
                        Text(verbatim: "Beyond the balance.").font(.title2.bold())
                        sources
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
                    Text("VELTRIX is a simulator. Trades, transfers and card payments use virtual funds on this device.")
                        .accessibilityIdentifier("settings.simulatorDisclosure")
                }.foregroundStyle(Color.vxMuted)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Settings")
        .task(id: notificationPhase) {
            if notificationPhase == .active { await systemNotifications.refresh() }
        }
        .scrollContentBackground(.hidden)
        .background(Color.vxBackground)
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
            Picker("Theme", selection: $model.theme) {
                Text("System").tag("system")
                Text("Dark").tag("dark")
                Text("Light").tag("light")
            }
            .pickerStyle(.segmented)
            Button {
                model.hide.toggle()
                Feedback.tap()
            } label: {
                HStack {
                    Text("Hide balances")
                    Spacer()
                    Image(systemName: model.hide ? "eye.slash.fill" : "eye")
                        .foregroundStyle(Color.vxHighlight)
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
                .font(.caption).foregroundStyle(Color.vxMuted)
            Picker("Lock after leaving the app", selection: .init(get: { lock.timeout }, set: { lock.setTimeout($0) })) {
                Text("Immediately").tag(0)
                Text("30 seconds").tag(30)
                Text("1 minute").tag(60)
                Text("5 minutes").tag(300)
                Text("15 minutes").tag(900)
            }
            .pickerStyle(.menu)
            if lock.enabled { settingsButton("Lock now", "lock.fill") { lock.lockNow() } }
            if let error = lock.error { Text(verbatim: error).font(.caption).foregroundStyle(Color.vxDown) }
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
                .font(.caption).foregroundStyle(Color.vxMuted)
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
        .foregroundStyle(destructive ? Color.vxDown : Color.vxHighlight)
    }
}

private struct QuickActionsSettings: View {
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
                Divider().overlay(Color.vxSeparator)
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
                Section { fields }
                if let error = message {
                    Text(verbatim: error).font(.footnote).foregroundStyle(Color.vxDown)
                }
                Button("Save") { submit() }
                    .buttonStyle(PrimaryButtonStyle()).listRowBackground(Color.clear)
                    .disabled(processing)
            }
            .scrollContentBackground(.hidden).background(Color.vxBackground)
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
                .font(.caption).foregroundStyle(Color.vxMuted)
        case .key:
            SecureField("CoinGecko API key", text: $secret).textInputAutocapitalization(.never).autocorrectionDisabled()
            Text("Leave blank and save to use the public feed without a key.")
                .font(.caption).foregroundStyle(Color.vxMuted)
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
