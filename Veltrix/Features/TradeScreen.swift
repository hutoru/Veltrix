import SwiftUI

enum TradeAction: String, CaseIterable, Identifiable {
    case buy, sell, send, receive, swap, deposit

    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .buy: return "Buy"
        case .sell: return "Sell"
        case .send: return "Send"
        case .receive: return "Receive"
        case .swap: return "Swap"
        case .deposit: return "Deposit"
        }
    }
    var icon: String {
        switch self {
        case .buy: return "plus.circle"
        case .sell: return "minus.circle"
        case .send: return "arrow.up.right"
        case .receive: return "arrow.down.left"
        case .swap: return "arrow.left.arrow.right"
        case .deposit: return "tray.and.arrow.down"
        }
    }
}

struct TradeIntent: Identifiable {
    let id = UUID()
    let action: TradeAction
    var asset: String = "bitcoin"
}

struct TradeScreen: View {
    @EnvironmentObject private var model: VeltrixModel
    @Environment(\.dismiss) private var dismiss
    let intent: TradeIntent
    @State private var asset: String
    @State private var target = "ethereum"
    @State private var amount = ""
    @State private var limit = ""
    @State private var label = ""
    @State private var isLimit = false
    @State private var useFiat = false
    @State private var review: TradeReview?
    @State private var error: String?
    @State private var done = false

    init(intent: TradeIntent) {
        self.intent = intent
        _asset = State(initialValue: intent.asset)
        _target = State(initialValue: intent.asset == "ethereum" ? "bitcoin" : "ethereum")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SimBadge()
                    Text("Virtual funds").font(.footnote).foregroundStyle(Color.vxMuted)
                }
                if done {
                    Section {
                        Label("Simulation saved", systemImage: "checkmark.circle.fill").foregroundStyle(Color.vxUp)
                            .accessibilityIdentifier("trade.saved")
                        if let review {
                            let summary = confirmedAmount ?? review.summary
                            LabeledContent("Amount", value: summary)
                            ShareLink(item: "VELTRIX · Simulation · \(L.text(intent.action.rawValue.capitalized)) · \(summary)")
                        }
                    }
                    Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle()).listRowBackground(Color.clear)
                } else if let review {
                    reviewSection(review)
                } else {
                    fields
                }
                if let error { Text(verbatim: error).foregroundStyle(Color.vxDown).font(.footnote) }
            }
            .scrollContentBackground(.hidden)
            .background(Color.vxBackground)
            .navigationTitle(intent.action.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }

    private var fields: some View {
        Group {
            Section("Order details") {
                if intent.action != .deposit {
                    AssetPicker(title: "Asset", asset: $asset)
                }
                if intent.action == .buy || intent.action == .sell {
                    Picker("Execution", selection: $isLimit) {
                        Text("Market").tag(false)
                        Text("Limit").tag(true)
                    }
                    .pickerStyle(.segmented)
                    if isLimit {
                        TextField("Limit price (USD)", text: $limit).keyboardType(.decimalPad)
                    } else {
                        Toggle("Enter amount in USD", isOn: $useFiat)
                    }
                }
                if intent.action == .swap { AssetPicker(title: "Receive asset", asset: $target) }
                if intent.action == .send || intent.action == .receive {
                    TextField(intent.action == .send ? "Simulated recipient" : "Simulated sender", text: $label)
                        .textInputAutocapitalization(.never)
                    Text("Transfers are recorded locally in this simulation.")
                        .font(.caption).foregroundStyle(Color.vxMuted)
                }
                if intent.action == .deposit || (useFiat && !isLimit) {
                    TextField("Amount (USD)", text: $amount).keyboardType(.decimalPad).accessibilityIdentifier("trade.amount")
                } else {
                    TextField("Quantity", text: $amount).keyboardType(.decimalPad).accessibilityIdentifier("trade.amount")
                }
                if intent.action != .deposit {
                    LabeledContent("Market price", value: model.money(model.quotes[asset]?.price, privateValue: false, price: true))
                }
                if intent.action == .sell || intent.action == .swap || intent.action == .send {
                    LabeledContent("Available units", value: (try? model.portfolio.freeUnits(asset)).map(model.units) ?? "—")
                } else {
                    LabeledContent("Available cash", value: model.money(try? model.portfolio.freeCash()))
                }
            }
            Button {
                do { review = try makeReview(); error = nil }
                catch { self.error = Display.error(error) }
            } label: { Text("Review simulation") }
                .buttonStyle(PrimaryButtonStyle())
                .listRowBackground(Color.clear)
                .accessibilityIdentifier("trade.review")
        }
    }

    private func reviewSection(_ review: TradeReview) -> some View {
        Group {
            Section("Review simulation") {
                LabeledContent("Amount", value: review.summary)
                if let estimate = review.estimate {
                    LabeledContent("Estimated value", value: model.money(estimate))
                }
                if let fee = review.fee { LabeledContent("Estimated fee", value: model.money(fee, price: true)) }
                if let quantity = review.received {
                    LabeledContent("Receive asset", value: "\(model.units(quantity)) \(Asset.ticker(target))")
                }
                if review.market {
                    Text("The final price uses the latest available quote at confirmation.")
                        .font(.caption).foregroundStyle(Color.vxMuted)
                }
            }
            Button {
                if model.execute(review.command, id: intent.id) {
                    done = true
                    error = nil
                } else {
                    error = model.error
                    model.error = nil
                }
            } label: { Text("Confirm simulation") }
                .buttonStyle(PrimaryButtonStyle())
                .listRowBackground(Color.clear)
                .accessibilityIdentifier("trade.confirm")
            Button("Edit") { self.review = nil; error = nil }
        }
    }

    private func makeReview() throws -> TradeReview {
        guard let quantity = Display.amount(amount) else { throw SimulationError.invalidAmount }
        try MoneyMath.quantity(quantity)
        let ticker = Asset.ticker(asset)
        let unitsText: (Decimal) -> String = { "\(self.model.units($0)) \(ticker)" }
        switch intent.action {
        case .deposit:
            return TradeReview(command: .deposit(quantity), summary: model.money(quantity))
        case .send, .receive:
            let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { throw SimulationError.invalidName }
            let price = try live(asset)
            return TradeReview(command: .transfer(receive: intent.action == .receive, asset: asset, units: quantity, label: name),
                               summary: unitsText(quantity), estimate: try MoneyMath.multiply(quantity, price), market: true)
        case .swap:
            guard asset != target else { throw SimulationError.invalidPair }
            let gross = try MoneyMath.multiply(quantity, live(asset))
            let fee = try MoneyMath.multiply(gross, model.fee)
            let received = try MoneyMath.divide(MoneyMath.subtract(gross, fee), live(target))
            return TradeReview(command: .swap(asset, target, quantity, model.fee), summary: unitsText(quantity),
                               estimate: gross, fee: fee, received: received, market: true)
        case .buy, .sell:
            let side: OrderSide = intent.action == .buy ? .buy : .sell
            let price: Decimal
            if isLimit {
                guard let entered = Display.amount(limit) else { throw SimulationError.invalidAmount }
                try MoneyMath.quantity(entered)
                price = entered
            } else {
                price = try live(asset)
            }
            let units = useFiat && !isLimit ? try MoneyMath.divide(quantity, price) : quantity
            let gross = useFiat && !isLimit ? quantity : try MoneyMath.multiply(units, price)
            let fee = try MoneyMath.multiply(gross, model.fee)
            let command: Command
            if isLimit { command = .limit(side, asset, units, price, model.fee) }
            else if useFiat { command = .marketNotional(side, asset, quantity, model.fee) }
            else { command = .market(side, asset, units, model.fee) }
            return TradeReview(command: command, summary: unitsText(units), estimate: gross, fee: fee, market: !isLimit)
        }
    }

    private var confirmedAmount: String? {
        guard let entry = model.portfolio.entries.last(where: { $0.id == intent.id }) else { return nil }
        return entry.asset == "USD" ? model.money(entry.amount) : "\(model.units(entry.amount)) \(Asset.ticker(entry.asset))"
    }

    private func live(_ asset: String) throws -> Decimal {
        guard let price = model.usablePrices[asset] else { throw SimulationError.missingQuote }
        return price
    }

    private struct TradeReview {
        let command: Command
        let summary: String
        var estimate: Decimal?
        var fee: Decimal?
        var received: Decimal?
        var market = false
    }
}
