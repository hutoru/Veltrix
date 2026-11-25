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
    @State private var processing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(intent: TradeIntent) {
        self.intent = intent
        _asset = State(initialValue: intent.asset)
        _useFiat = State(initialValue: intent.action == .buy)
        _target = State(initialValue: intent.asset == "ethereum" ? "bitcoin" : "ethereum")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if processing || done {
                        completion
                    } else if let review {
                        reviewContent(review)
                    } else {
                        editor
                    }
                    if let error {
                        Text(verbatim: error).font(.footnote).foregroundStyle(Color.vxDown)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .frame(maxWidth: 490)
                .frame(maxWidth: .infinity)
            }
            .background(Color.vxBackground.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(Text(verbatim: L.text(intent.action.rawValue.capitalized) + (intent.action == .deposit ? "" : " " + Asset.ticker(asset))))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(review != nil && !done ? "Edit" : "Close") {
                        if review != nil && !done { review = nil; error = nil }
                        else { dismiss() }
                    }.disabled(processing)
                }
            }
            .interactiveDismissDisabled(processing)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: review != nil)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: done)
        }
    }

    private var editor: some View {
        VStack(spacing: 13) {
            if intent.action != .deposit {
                AssetPicker(title: "Asset", asset: $asset)
                if intent.action == .swap { AssetPicker(title: "Receive asset", asset: $target) }
            }
            if intent.action == .buy || intent.action == .sell {
                Picker("Execution", selection: $isLimit) {
                    Text("Market").tag(false)
                    Text("Limit").tag(true)
                }.pickerStyle(.segmented)
                if isLimit {
                    TextField("Limit price (USD)", text: $limit)
                        .keyboardType(.decimalPad)
                        .padding(10).background(Color.vxSurface, in: RoundedRectangle(cornerRadius: 10))
                } else {
                    Toggle("Enter amount in USD", isOn: $useFiat).font(.footnote)
                }
            }
            if intent.action == .send || intent.action == .receive {
                TextField(intent.action == .send ? "Recipient label" : "Sender label", text: $label)
                    .textInputAutocapitalization(.never).padding(10)
                    .background(Color.vxSurface, in: RoundedRectangle(cornerRadius: 10))
            }
            VStack(spacing: 4) {
                CountValue(text: (amount.isEmpty ? "0" : amount) + " " + amountUnit)
                    .font(.system(size: 51, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.36)
                    .accessibilityIdentifier("trade.amount")
                if let equivalent { Text(verbatim: equivalent).font(.footnote).foregroundStyle(Color.vxMuted) }
            }.frame(maxWidth: .infinity, minHeight: 72)
            LabeledContent("Virtual funds", value: availableLabel)
                .font(.footnote)
                .foregroundStyle(Color.vxMuted)
            if available != nil {
                HStack(spacing: 8) {
                    ForEach([25, 50, 75, 100], id: \.self) { fraction in
                        Button {
                            fill(fraction)
                            Feedback.tap()
                        } label: {
                            Text(verbatim: fraction == 100 ? "MAX" : "\(fraction)%")
                                .font(.caption.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 32)
                                .background(Color.vxSurface, in: Capsule())
                        }.buttonStyle(.plain)
                    }
                }
            }
            NumericPad(allowsDecimal: true, onInput: append, onDelete: {
                if !amount.isEmpty { amount.removeLast() }
            })
            Button("Continue") {
                do { review = try makeReview(); error = nil; Feedback.tap() }
                catch { self.error = Display.error(error) }
            }
            .buttonStyle(PrimaryButtonStyle(tint: actionColor, ink: [.buy, .sell].contains(intent.action) ? .black : .white))
            .accessibilityIdentifier("trade.review")
        }
    }

    private var amountIsCash: Bool { intent.action == .deposit || (useFiat && !isLimit) }
    private var amountUnit: String { amountIsCash ? "USD" : Asset.ticker(asset) }
    private var actionColor: Color {
        switch intent.action {
        case .buy: return .vxUp
        case .sell: return .vxDown
        default: return .vxAccent
        }
    }

    private var pricingQuote: Decimal? {
        isLimit ? Display.amount(limit) : model.usablePrices[asset]
    }

    private var available: Decimal? {
        switch intent.action {
        case .deposit, .receive: return nil
        case .buy:
            return try? MoneyMath.divide(model.portfolio.freeCash(), MoneyMath.add(1, model.fee))
        default: return try? model.portfolio.freeUnits(asset)
        }
    }

    private var availableLabel: String {
        switch intent.action {
        case .buy, .deposit, .receive: return model.money(try? model.portfolio.freeCash())
        default:
            return available.map { model.units($0) + " " + Asset.ticker(asset) } ?? "—"
        }
    }

    private var equivalent: String? {
        guard intent.action != .deposit, let number = Display.amount(amount),
              let price = pricingQuote, price > 0 else { return nil }
        if amountIsCash {
            return (try? MoneyMath.divide(number, price)).map { "≈ " + Display.number($0, maximum: 8) + " " + Asset.ticker(asset) }
        }
        return (try? MoneyMath.multiply(number, price)).map { "≈ " + model.money($0) }
    }

    private func append(_ value: String) {
        let separator = Locale.current.decimalSeparator ?? "."
        guard amount.count < 28, value != separator || !amount.contains(separator) else { return }
        if value == separator && amount.isEmpty { amount = "0" }
        amount.append(value)
        error = nil
    }

    private func fill(_ percent: Int) {
        guard let available else { return }
        var value = available
        if intent.action == .buy && !amountIsCash {
            guard let price = pricingQuote, price > 0, let units = try? MoneyMath.divide(value, price) else { return }
            value = units
        } else if intent.action == .sell && amountIsCash {
            guard let price = pricingQuote, let total = try? MoneyMath.multiply(value, price) else { return }
            value = total
        }
        guard var fraction = try? MoneyMath.divide(MoneyMath.multiply(value, Decimal(percent)), 100) else { return }
        var rounded = Decimal()
        NSDecimalRound(&rounded, &fraction, 8, .down)
        amount = Display.input(rounded)
        error = nil
    }

    private func reviewContent(_ review: TradeReview) -> some View {
        VStack(spacing: 16) {
            Text("Review order").font(.title2.bold())
            if let coin = Asset.catalog.first(where: { $0.id == asset }), intent.action != .deposit {
                CoinIcon(asset: coin, url: model.quotes[asset]?.image, size: 52)
            }
            Text(verbatim: review.summary).font(.system(size: 38, weight: .semibold).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.4)
            Label("Virtual funds", systemImage: "info.circle").font(.footnote).foregroundStyle(Color.vxMuted)
            VStack(spacing: 12) {
                if [.buy, .sell, .swap].contains(intent.action) {
                    LabeledContent("Execution", value: L.text(isLimit ? "Limit" : "Market"))
                    LabeledContent(isLimit ? "Limit price" : "Market price", value: model.money(pricingQuote, privateValue: false, price: true))
                }
                if let estimate = review.estimate { LabeledContent("Estimated value", value: model.money(estimate)) }
                if let fee = review.fee { LabeledContent("Estimated fee", value: model.money(fee, price: true)) }
                if let estimate = review.estimate, let fee = review.fee,
                   let total = try? (intent.action == .buy ? MoneyMath.add(estimate, fee) : MoneyMath.subtract(estimate, fee)) {
                    LabeledContent("Estimated total", value: model.money(total)).fontWeight(.semibold)
                }
                if let quantity = review.received {
                    LabeledContent("Receive asset", value: "\(model.units(quantity)) \(Asset.ticker(target))")
                }
                LabeledContent("Available balance", value: availableLabel)
            }.font(.subheadline).panel()
            if review.market {
                Text("The final price uses the latest available quote at confirmation.")
                    .font(.caption).foregroundStyle(Color.vxMuted)
            }
            Button { submit(review) } label: { Text(intent.action == .deposit ? "Confirm operation" : intent.action.title) }
                .buttonStyle(PrimaryButtonStyle(tint: actionColor))
                .accessibilityIdentifier("trade.confirm")
        }
    }

    private func submit(_ review: TradeReview) {
        guard !processing, !done else { return }
        if model.execute(review.command, id: intent.id) {
            error = nil
            processing = true
            Task { @MainActor in
                if !reduceMotion { try? await Task.sleep(nanoseconds: 420_000_000) }
                done = true
                processing = false
                Feedback.tap()
            }
        } else {
            error = model.error
            model.error = nil
        }
    }

    private var completion: some View {
        VStack(spacing: 20) {
            if let coin = Asset.catalog.first(where: { $0.id == asset }), intent.action != .deposit {
                CoinIcon(asset: coin, url: model.quotes[asset]?.image, size: 66)
            }
            if processing {
                ProgressView().scaleEffect(1.35).tint(.vxHighlight)
                Text("Updating portfolio").foregroundStyle(Color.vxMuted)
            } else {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 54)).foregroundStyle(Color.vxUp)
                Text("Operation saved").font(.title2.bold()).accessibilityIdentifier("trade.saved")
                Text("Virtual operation").font(.footnote).foregroundStyle(Color.vxMuted)
                if let review {
                    let summary = confirmedAmount ?? review.summary
                    Text(verbatim: summary).font(.title3.monospacedDigit())
                    ShareLink(item: "VELTRIX · \(L.text("Virtual operation")) · \(L.text(intent.action.rawValue.capitalized)) · \(summary)")
                }
                Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle())
            }
        }.padding(.vertical, 44)
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
