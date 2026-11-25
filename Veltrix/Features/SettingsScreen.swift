import SwiftUI
import UniformTypeIdentifiers

struct SettingsScreen: View {
    @EnvironmentObject private var model: VeltrixModel
    @EnvironmentObject private var lock: AppLock
    @AppStorage("profileName") private var profileName = ""
    @State private var panel: SettingsPanel?
    @State private var export = false
    @State private var takeFile = false
    @State private var backup = BackupFile()
    @State private var incoming: Data?
    @State private var reset = false

    var body: some View {
        List {
            Section("My profile") {
                TextField("Display name", text: $profileName)
            }
            Section {
                display
                Link(destination: URL(string: UIApplication.openSettingsURLString)!) {
                    Label("App language", systemImage: "globe")
                }
            }
            Section { simulation }
            Section { security }
            Section { backups }
            Section {
                NavigationLink("About VELTRIX") {
                    PageScroll {
                        Text(verbatim: "Beyond the balance.").font(.title2.bold())
                        Text("VELTRIX uses virtual funds. Trades, transfers and card payments are simulated on this device.")
                        sources
                    }.navigationTitle("About VELTRIX")
                }
            }
        }
        .navigationTitle("Settings")
        .scrollContentBackground(.hidden)
        .background(Color.vxBackground)
        .sheet(item: $panel) { SettingsForm(panel: $0) }
        .fileExporter(isPresented: $export, document: backup, contentType: .json, defaultFilename: "VELTRIX-Simulation") { result in
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
        .confirmationDialog("Replace simulation data?", isPresented: .init(get: { incoming != nil }, set: { if !$0 { incoming = nil } }),
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

    private var simulation: some View {
        VStack(alignment: .leading, spacing: 6) {
            heading("Simulation controls")
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
            heading("Display")
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
            heading("Privacy and lock")
            Toggle("Face ID / Touch ID", isOn: .init(get: { lock.biometrics }, set: { next in
                Task { await lock.changeBiometrics(next) }
            }))
            .disabled(lock.busy)
            settingsButton(lock.hasPIN ? "Change or remove PIN" : "Set PIN", "lock") { panel = .pin }
            Picker("Lock after leaving the app", selection: .init(get: { lock.timeout }, set: { lock.setTimeout($0) })) {
                Text("Immediately").tag(0)
                Text("30 seconds").tag(30)
                Text("1 minute").tag(60)
                Text("5 minutes").tag(300)
                Text("15 minutes").tag(900)
            }
            .pickerStyle(.menu)
            if lock.hasPIN || lock.biometrics { settingsButton("Lock now", "lock.fill") { lock.lockNow() } }
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
            Text("The backup contains virtual balances and activity. Store it somewhere private.")
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

enum SettingsPanel: String, Identifiable {
    case newPortfolio, cash, positions, fee, pin, key
    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .newPortfolio: return "Create portfolio"
        case .cash: return "Set cash balance"
        case .positions: return "Edit holdings"
        case .fee: return "Trading fee"
        case .pin: return "App PIN"
        case .key: return "Optional CoinGecko API key"
        }
    }
}

struct SettingsForm: View {
    @EnvironmentObject private var model: VeltrixModel
    @EnvironmentObject private var lock: AppLock
    @Environment(\.dismiss) private var dismiss
    let panel: SettingsPanel
    @State private var name = ""
    @State private var amount = ""
    @State private var average = ""
    @State private var asset = "bitcoin"
    @State private var current = ""
    @State private var secret = ""
    @State private var confirmation = ""
    @State private var message: String?
    @State private var processing = false
    @State private var removeHolding = false
    @State private var removePIN = false
    @State private var operation = UUID()

    var body: some View {
        NavigationStack {
            Form {
                SimBadge()
                Section { fields }
                if let error = message ?? (panel == .pin ? lock.error : nil) {
                    Text(verbatim: error).font(.footnote).foregroundStyle(Color.vxDown)
                }
                Button("Save") { submit() }
                    .buttonStyle(PrimaryButtonStyle()).listRowBackground(Color.clear)
                    .disabled(processing || (panel == .pin && lock.busy))
            }
            .scrollContentBackground(.hidden).background(Color.vxBackground)
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
        .confirmationDialog("Remove the app PIN?", isPresented: $removePIN, titleVisibility: .visible) {
            Button("Remove PIN", role: .destructive) { changePIN(nil) }
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
        case .pin:
            if lock.hasPIN {
                SecureField("Current PIN", text: $current).keyboardType(.numberPad)
            }
            SecureField("New PIN", text: $secret).keyboardType(.numberPad)
            SecureField("Repeat new PIN", text: $confirmation).keyboardType(.numberPad)
            Text("Use 4–8 digits.").font(.caption).foregroundStyle(Color.vxMuted)
            if lock.hasPIN { Button("Remove PIN", role: .destructive) { removePIN = true }.disabled(lock.busy) }
        case .key:
            SecureField("CoinGecko Demo key", text: $secret).textInputAutocapitalization(.never).autocorrectionDisabled()
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
        case .pin: lock.error = nil
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
        case .pin:
            guard secret == confirmation else { message = L.text("The new PINs do not match."); return }
            changePIN(secret)
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

    private func changePIN(_ next: String?) {
        message = nil
        Task { if await lock.updatePIN(current: current, new: next) { dismiss() } }
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
