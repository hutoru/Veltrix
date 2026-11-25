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
    @State private var scanner = false
    @State private var network: TransferNetwork?
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
                    if let error, review != nil {
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
            .navigationTitle(Text(verbatim: navigationTitle))
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
            .fullScreenCover(isPresented: $scanner) {
                QRScanner { value in label = value; error = nil }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: review != nil)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: done)
        }
    }

    private var editor: some View {
        VStack(spacing: 12) {
            if isTrading {
                tradeControls
            } else if intent.action != .deposit {
                AssetPicker(title: "Asset", asset: $asset)
            }
            if intent.action == .send || intent.action == .receive {
                Picker("Network", selection: $network) {
                    Text("Contact label").tag(nil as TransferNetwork?)
                    ForEach(TransferNetwork.available(for: asset), id: \.self) { network in
                        Text(verbatim: network.rawValue).tag(Optional(network))
                    }
                }.onChange(of: asset) { _ in network = nil }
                HStack {
                    TextField(network == nil ? (intent.action == .send ? "Recipient label" : "Sender label") : "Public address", text: $label)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    IconButton(icon: "qrcode.viewfinder", label: "Scan QR code") { scanner = true }
                }.padding(.horizontal, 12)
                    .background(Color.vxCard, in: RoundedRectangle(cornerRadius: 12))
            }
            amountDisplay
            LabeledContent("Available balance", value: availableLabel)
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
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: isTrading ? 36 : 32)
                                .background(Color.vxSurface, in: RoundedRectangle(cornerRadius: isTrading ? 10 : 16))
                        }.buttonStyle(.plain)
                    }
                }
            }
            NumericPad(allowsDecimal: true, keyHeight: isTrading ? 48 : 44, onInput: append, onDelete: {
                if !amount.isEmpty { amount.removeLast() }
                error = nil
            })
            if let error {
                Text(verbatim: error).font(.footnote).foregroundStyle(Color.vxDown)
            }
            Button("Continue") {
                do {
                    let draft = try makeReview()
                    try model.validateTrade(draft.command, id: intent.id)
                    review = draft
                    error = nil
                    Feedback.tap()
                } catch {
                    self.error = Display.error(error)
                    Feedback.failure()
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("trade.review")
        }
    }

    private var isTrading: Bool { [.buy, .sell, .swap].contains(intent.action) }

    private var navigationTitle: String {
        let title = L.text(intent.action.rawValue.capitalized)
        return isTrading || intent.action == .deposit ? title : title + " " + Asset.ticker(asset)
    }

    private var tradeControls: some View {
        VStack(spacing: 8) {
            VStack(spacing: 0) {
                tradeAssetRow("Asset", selection: $asset)
                if intent.action == .swap {
                    Divider()
                    tradeAssetRow("Receive asset", selection: $target)
                    HStack {
                        if let source = model.usablePrices[asset], let destination = model.usablePrices[target],
                           let rate = try? MoneyMath.divide(source, destination) {
                            Text(verbatim: "1 \(Asset.ticker(asset)) ≈ \(Display.number(rate)) \(Asset.ticker(target))")
                                .font(.caption.monospacedDigit()).foregroundStyle(Color.vxMuted)
                        }
                        Spacer()
                        IconButton(icon: "arrow.up.arrow.down", label: "Reverse swap") {
                            let previous = asset
                            asset = target
                            target = previous
                            amount = ""
                            error = nil
                            Feedback.tap()
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .background(Color.vxCard, in: RoundedRectangle(cornerRadius: 12))

            if intent.action != .swap {
                HStack(spacing: 10) {
                    Picker("Execution", selection: $isLimit) {
                        Text("Market").tag(false)
                        Text("Limit").tag(true)
                    }
                    .pickerStyle(.segmented)

                    if !isLimit {
                        Picker("Amount unit", selection: $useFiat) {
                            Text(verbatim: "USD").tag(true)
                            Text(verbatim: Asset.ticker(asset)).tag(false)
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                        .tint(.vxHighlight)
                    }
                }

                if isLimit {
                    TextField("Limit price (USD)", text: $limit)
                        .keyboardType(.decimalPad)
                        .padding(10)
                        .background(Color.vxSurface, in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private func tradeAssetRow(_ title: LocalizedStringKey, selection: Binding<String>) -> some View {
        LabeledContent {
            AssetPicker(title: title, asset: selection)
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(.vxHighlight)
        } label: {
            HStack(spacing: 8) {
                if let coin = Asset.catalog.first(where: { $0.id == selection.wrappedValue }) {
                    CoinIcon(asset: coin, url: model.quotes[coin.id]?.image, size: 26)
                }
                Text(title).foregroundStyle(Color.vxMuted)
            }
        }
        .font(.subheadline)
        .frame(minHeight: 44)
    }

    private var amountDisplay: some View {
        VStack(spacing: 3) {
            CountValue(text: (amount.isEmpty ? "0" : amount) + " " + amountUnit)
                .font(.system(size: isTrading ? 62 : 51, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.36)
                .accessibilityIdentifier("trade.amount")
            Text(verbatim: equivalent ?? " ")
                .font(.footnote)
                .foregroundStyle(Color.vxMuted)
                .accessibilityHidden(equivalent == nil)
        }
        .frame(maxWidth: .infinity, minHeight: isTrading ? 104 : 72)
    }

    private var amountIsCash: Bool { intent.action == .deposit || (useFiat && !isLimit) }
    private var amountUnit: String { amountIsCash ? "USD" : Asset.ticker(asset) }

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
        guard amount.count < 32, value != separator || !amount.contains(separator) else { return }
        if value == separator && amount.isEmpty { amount = "0" }
        if amount == "0" && value != separator { amount = value }
        else { amount.append(value) }
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
        if percent == 100 && intent.action != .buy && !amountIsCash {
            amount = Display.input(value)
            error = nil
            return
        }
        guard var fraction = try? MoneyMath.multiply(value, Decimal(percent) / 100) else { return }
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
            if !model.onSet {
                Text("Local operation").font(.caption.weight(.semibold)).foregroundStyle(Color.vxMuted)
            }
            VStack(spacing: 12) {
                if isTrading {
                    if intent.action != .swap {
                        LabeledContent("Order type", value: L.text(isLimit ? "Limit" : "Market"))
                        Divider().overlay(Color.vxSeparator)
                    }
                    LabeledContent(isLimit ? "Limit price" : "Market price", value: model.money(review.price, privateValue: false, price: true))
                    Divider().overlay(Color.vxSeparator)
                }
                if intent.action == .send || intent.action == .receive {
                    if let network { LabeledContent("Network", value: network.rawValue) }
                    LabeledContent(network == nil ? (intent.action == .send ? "Recipient label" : "Sender label") : "Public address",
                                   value: label).lineLimit(2)
                    Divider().overlay(Color.vxSeparator)
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
                Divider().overlay(Color.vxSeparator)
                LabeledContent("Available balance", value: availableLabel)
            }.font(.subheadline)
            if review.market {
                Text("The final price uses the latest available quote at confirmation.")
                    .font(.caption).foregroundStyle(Color.vxMuted)
            }
            Button { submit(review) } label: { Text(intent.action == .deposit ? "Confirm operation" : intent.action.title) }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("trade.confirm")
        }
    }

    private func submit(_ review: TradeReview) {
        guard !processing, !done else { return }
        if model.execute(review.command, id: intent.id) {
            error = nil
            processing = true
            Task { @MainActor in
                if !reduceMotion { try? await Task.sleep(nanoseconds: 780_000_000) }
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
            completionMark
            if processing {
                Text("Updating portfolio").foregroundStyle(Color.vxMuted)
            } else {
                Text("Operation saved").font(.title2.bold()).accessibilityIdentifier("trade.saved")
                if intent.action == .send || intent.action == .receive {
                    Text("Recorded on this device").font(.footnote).foregroundStyle(Color.vxMuted)
                }
                if let review {
                    let summary = confirmedAmount ?? review.summary
                    Text(verbatim: summary).font(.largeTitle.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.4)
                    ShareLink(item: "VELTRIX · \(L.text("Virtual operation")) · \(L.text(intent.action.rawValue.capitalized)) · \(summary)")
                }
                Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle())
            }
        }.padding(.vertical, 44)
    }

    private var completionMark: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle().stroke(Color.vxSeparator, lineWidth: 2)
            Circle().trim(from: 0, to: done ? 1 : (processing ? 0.86 : 0))
                .stroke(Color.vxUp, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.68), value: processing)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: done)
            Group {
                if let coin = Asset.catalog.first(where: { $0.id == asset }), intent.action != .deposit {
                    CoinIcon(asset: coin, url: model.quotes[asset]?.image, size: 54)
                } else {
                    VeltrixMark().fill(Color.vxText).frame(width: 34, height: 34)
                }
            }.frame(width: 92, height: 92)
            if done {
                Image(systemName: "checkmark").font(.caption.bold())
                    .foregroundStyle(.black).frame(width: 24, height: 24)
                    .background(Color.vxUp, in: Circle())
                    .transition(reduceMotion ? .identity : .scale.combined(with: .opacity))
            }
        }.frame(width: 92, height: 92).accessibilityHidden(true)
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
            if let network, !network.accepts(name) { throw SimulationError.invalidAddress }
            let price = try live(asset)
            let note = network.map { $0.rawValue + " · " + name } ?? name
            return TradeReview(command: .transfer(receive: intent.action == .receive, asset: asset, units: quantity, label: note),
                               summary: unitsText(quantity), estimate: try MoneyMath.multiply(quantity, price), fee: 0)
        case .swap:
            guard asset != target else { throw SimulationError.invalidPair }
            let price = try live(asset)
            let gross = try MoneyMath.multiply(quantity, price)
            let fee = try MoneyMath.multiply(gross, model.fee)
            let received = try MoneyMath.divide(MoneyMath.subtract(gross, fee), live(target))
            return TradeReview(command: .swap(asset, target, quantity, model.fee), summary: unitsText(quantity),
                               estimate: gross, fee: fee, received: received, market: true, price: price)
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
            return TradeReview(command: command, summary: unitsText(units), estimate: gross, fee: fee, market: !isLimit, price: price)
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
        var price: Decimal?
    }
}

private enum TransferNetwork: String, CaseIterable {
    case bitcoin = "Bitcoin"
    case ethereum = "Ethereum"
    case solana = "Solana"

    static func available(for asset: String) -> [TransferNetwork] {
        switch asset {
        case "bitcoin": return [.bitcoin]
        case "ethereum", "chainlink": return [.ethereum]
        case "solana": return [.solana]
        case "tether", "usd-coin": return [.ethereum, .solana]
        default: return []
        }
    }

    func accepts(_ address: String) -> Bool {
        let expression: String
        switch self {
        case .bitcoin:
            expression = "^(?:[13][1-9A-HJ-NP-Za-km-z]{25,34}|bc1[ac-hj-np-z02-9]{11,87}|BC1[AC-HJ-NP-Z02-9]{11,87})$"
        case .ethereum: expression = "^0x[0-9a-fA-F]{40}$"
        case .solana: expression = "^[1-9A-HJ-NP-Za-km-z]{32,44}$"
        }
        return address.range(of: expression, options: .regularExpression) != nil
    }
}
