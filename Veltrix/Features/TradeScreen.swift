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
    @State private var exactMaxUnits: Decimal?
    @State private var computedAmount = false
    @State private var review: TradeReview?
    @State private var error: String?
    @State private var done = false
    @State private var processing = false
    @State private var ringProgress: CGFloat = 0
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
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 18) {
                        if processing || done {
                            completion.frame(minHeight: max(0, geometry.size.height - 28))
                                .task { await animateCompletion() }
                        } else if let review {
                            reviewContent(review)
                        } else {
                            editor(minimumHeight: max(0, geometry.size.height - 28))
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
                .scrollDismissesKeyboard(.interactively)
            }
            .background(Color.vxDarkBackground.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !processing { footer }
            }
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
            .environment(\.colorScheme, .dark)
            .tint(.white)
            .onChange(of: asset) { _ in amount = ""; exactMaxUnits = nil; computedAmount = false; error = nil }
        }
    }

    private func editor(minimumHeight: CGFloat) -> some View {
        VStack(spacing: minimumHeight < 510 ? 5 : 8) {
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
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .overlay(alignment: .bottom) { Rectangle().fill(Color.vxSeparator).frame(height: 1) }
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
            if isTrading { Spacer(minLength: 0) }
            NumericPad(keyHeight: 44, digitSize: isTrading ? 31 : 22,
                       rowSpacing: isTrading ? 4 : 7, onInput: append, onDelete: {
                beginEditingAmount()
                if !amount.isEmpty { amount.removeLast() }
                error = nil
                exactMaxUnits = nil
            })
            if let error {
                Text(verbatim: error).font(.footnote).foregroundStyle(Color.vxDown)
            }
        }.frame(minHeight: isTrading ? minimumHeight : nil)
    }

    private var footer: some View {
        Group {
            if done {
                Button("Done") { dismiss() }
            } else if let review {
                Button { submit(review) } label: {
                    Text(intent.action == .deposit ? "Confirm operation" : intent.action.title)
                }
                .accessibilityIdentifier("trade.confirm")
            } else {
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
                .accessibilityIdentifier("trade.review")
            }
        }
        .buttonStyle(PrimaryButtonStyle(tint: done ? .white : actionColor, ink: .black, height: 52))
        .frame(maxWidth: 490)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color.vxDarkBackground)
        .overlay(alignment: .top) { Rectangle().fill(Color.vxSeparator).frame(height: 1).allowsHitTesting(false) }
    }

    private var isTrading: Bool { [.buy, .sell, .swap].contains(intent.action) }
    private var actionColor: Color {
        switch intent.action {
        case .buy: return .vxUp
        case .sell: return .vxDown
        default: return .white
        }
    }

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
                    HStack(spacing: 8) {
                        tradeAssetRow("Receive asset", selection: $target)
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
            .overlay(alignment: .bottom) { Rectangle().fill(Color.vxSeparator).frame(height: 1) }

            if intent.action == .swap {
                HStack {
                    if let source = model.usablePrices[asset], let destination = model.usablePrices[target],
                       let rate = try? MoneyMath.divide(source, destination) {
                        Text(verbatim: "1 \(Asset.ticker(asset)) ≈ \(Display.number(rate)) \(Asset.ticker(target))")
                            .font(.caption.monospacedDigit()).foregroundStyle(Color.vxMuted)
                    }
                    Spacer()
                    unitControl
                }
            } else {
                HStack(spacing: 10) {
                    Picker("Execution", selection: $isLimit) {
                        Text("Market").tag(false)
                        Text("Limit").tag(true)
                    }
                    .pickerStyle(.segmented)

                    unitControl
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

    private var unitControl: some View {
        Button {
            if let value = Display.amount(amount), value > 0 {
                guard let price = pricingQuote, price > 0,
                      let converted = try? TradeSizing.convert(value, fromUSD: useFiat, price: price) else {
                    error = Display.error(SimulationError.missingQuote)
                    return
                }
                if let exactMaxUnits, !useFiat {
                    amount = Display.input((try? MoneyMath.quotedUSD(exactMaxUnits, at: price)) ?? converted)
                } else {
                    amount = Display.input(exactMaxUnits ?? converted)
                }
                computedAmount = true
            }
            useFiat.toggle()
            error = nil
            Feedback.tap()
        } label: {
            HStack(spacing: 6) {
                Text(verbatim: amountUnit).font(.caption.weight(.semibold))
                Image(systemName: "arrow.left.arrow.right").font(.caption2.weight(.semibold))
            }
            .padding(.horizontal, 10).frame(minHeight: 40)
            .background(Color.vxSurface, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Switch amount unit"))
        .accessibilityValue(Text(verbatim: amountUnit))
        .accessibilityIdentifier("trade.unit")
    }

    private func tradeAssetRow(_ title: LocalizedStringKey, selection: Binding<String>) -> some View {
        LabeledContent {
            AssetPicker(title: title, asset: selection)
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(.white)
        } label: {
            HStack(spacing: 8) {
                if let coin = Asset.catalog.first(where: { $0.id == selection.wrappedValue }) {
                    CoinIcon(asset: coin, url: model.quotes[coin.id]?.image, size: 30)
                }
                Text(title).foregroundStyle(Color.vxMuted)
            }
        }
        .font(.subheadline)
        .frame(minHeight: 44)
    }

    private var amountDisplay: some View {
        VStack(spacing: 3) {
            CountValue(text: visibleAmount + " " + amountUnit)
                .font(.system(size: isTrading ? 62 : 51, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.24)
                .accessibilityIdentifier("trade.amount")
            Text(verbatim: equivalent ?? " ")
                .font(.footnote)
                .foregroundStyle(Color.vxMuted)
                .accessibilityHidden(equivalent == nil)
        }
        .frame(maxWidth: .infinity, minHeight: isTrading ? 84 : 72)
    }

    private var visibleAmount: String {
        guard !amount.isEmpty else { return "0" }
        guard computedAmount, let value = Display.amount(amount) else { return amount }
        let rounded = MoneyMath.round(value, scale: FinancialFormatter.pricePrecision(value, minimum: amountIsCash ? 2 : 4))
        return Display.input(rounded == 0 ? value : rounded)
    }

    private func beginEditingAmount() {
        if computedAmount {
            amount = visibleAmount
            computedAmount = false
        }
    }

    private var amountIsCash: Bool { intent.action == .deposit || useFiat }
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
        if intent.action == .swap, let targetPrice = model.usablePrices[target],
           let units = try? inputUnits(number, price: price),
           let gross = try? MoneyMath.quotedUSD(units, at: price),
           let fee = try? MoneyMath.multiply(gross, model.fee),
           let received = try? MoneyMath.divide(MoneyMath.subtract(gross, fee), targetPrice) {
            return "≈ " + model.units(received) + " " + Asset.ticker(target)
        }
        if amountIsCash {
            return (try? MoneyMath.divide(number, price)).map { "≈ " + model.units(exactMaxUnits ?? $0) + " " + Asset.ticker(asset) }
        }
        return (try? MoneyMath.quotedUSD(number, at: price)).map { "≈ " + model.money($0, price: true) }
    }

    private func inputUnits(_ amount: Decimal, price: Decimal) throws -> Decimal {
        if let exactMaxUnits { return exactMaxUnits }
        return amountIsCash ? try TradeSizing.convert(amount, fromUSD: true, price: price) : amount
    }

    private func append(_ value: String) {
        beginEditingAmount()
        let separator = Locale.current.decimalSeparator ?? "."
        guard amount.count < 32, value != separator || !amount.contains(separator) else { return }
        if value == separator && amount.isEmpty { amount = "0" }
        if amount == "0" && value != separator { amount = value }
        else { amount.append(value) }
        exactMaxUnits = nil
        error = nil
    }

    private func fill(_ percent: Int) {
        guard let available else { return }
        do {
            let size = try TradeSizing.preset(available: available, percent: percent,
                                              sourceIsUSD: intent.action == .buy, inputIsUSD: amountIsCash,
                                              price: pricingQuote)
            amount = Display.input(size)
            computedAmount = true
            exactMaxUnits = percent == 100 && intent.action != .buy ? available : nil
            error = nil
        } catch {
            self.error = Display.error(error)
        }
    }

    private func reviewContent(_ review: TradeReview) -> some View {
        VStack(spacing: 12) {
            if let coin = Asset.catalog.first(where: { $0.id == asset }), intent.action != .deposit {
                CoinIcon(asset: coin, url: model.quotes[asset]?.image, size: 68)
            }
            Text("Review order").font(.subheadline.weight(.medium)).foregroundStyle(Color.vxMuted)
            Text(verbatim: review.total.map { model.money($0, price: true) } ?? review.summary)
                .font(.system(size: 45, weight: .semibold).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.4)
            if review.total != nil {
                Text(verbatim: review.summary).font(.subheadline.monospacedDigit()).foregroundStyle(Color.vxMuted)
            }
            if !model.onSet {
                Text("Local operation").font(.caption.weight(.semibold)).foregroundStyle(Color.vxMuted)
            }
            VStack(spacing: 9) {
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
                if let estimate = review.estimate { LabeledContent("Estimated value", value: model.money(estimate, price: true)) }
                if let fee = review.fee {
                    Divider().overlay(Color.vxSeparator)
                    LabeledContent("Estimated fee", value: model.money(fee, price: true))
                }
                if let total = review.total {
                    Divider().overlay(Color.vxSeparator)
                    LabeledContent("Estimated total", value: model.money(total)).fontWeight(.semibold)
                }
                if let quantity = review.received {
                    LabeledContent("Receive asset", value: "\(model.units(quantity)) \(Asset.ticker(target))")
                }
                Divider().overlay(Color.vxSeparator)
                if isTrading {
                    LabeledContent("Funding source", value: intent.action == .buy ? L.text("Cash balance") : Asset.ticker(asset))
                }
                LabeledContent("Available balance", value: availableLabel)
            }.font(.subheadline.monospacedDigit()).padding(.top, 8)
            if review.market {
                Text("The final price uses the latest available quote at confirmation.")
                    .font(.caption).foregroundStyle(Color.vxMuted)
            }
        }
    }

    private func submit(_ review: TradeReview) {
        guard !processing, !done else { return }
        if model.execute(review.command, id: intent.id, showFeedback: false) {
            error = nil
            processing = true
        } else {
            error = model.error
            model.error = nil
        }
    }

    @MainActor private func animateCompletion() async {
        guard processing, !done else { return }
        await Task.yield()
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.68)) { ringProgress = 1 }
        if !reduceMotion { try? await Task.sleep(nanoseconds: 690_000_000) }
        guard !Task.isCancelled else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
            done = true
            processing = false
        }
        Feedback.success()
    }

    private var completion: some View {
        VStack(spacing: 20) {
            completionMark
            if processing {
                Text("Updating portfolio").foregroundStyle(Color.vxMuted)
            } else {
                Text(isLimit && savedEntry == nil ? "Limit order placed" : "Operation saved")
                    .font(.title2.bold()).accessibilityIdentifier("trade.saved")
                if intent.action == .send || intent.action == .receive {
                    Text("Recorded on this device").font(.footnote).foregroundStyle(Color.vxMuted)
                }
                if let review {
                    let summary = confirmedAmount ?? review.summary
                    Text(verbatim: summary).font(.largeTitle.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.4)
                    if let entry = savedEntry, entry.asset != "USD", let value = entry.usd {
                        Text(verbatim: model.money(value, price: true)).font(.subheadline.monospacedDigit())
                            .foregroundStyle(Color.vxMuted)
                    }
                    ShareLink(item: "VELTRIX · \(L.text("Virtual operation")) · \(L.text(intent.action.rawValue.capitalized)) · \(summary)")
                }
            }
        }.padding(.vertical, 44)
    }

    private var completionMark: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle().stroke(Color.vxSeparator, lineWidth: 2)
            Circle().trim(from: 0, to: ringProgress)
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
            TradeCheckmark()
                .trim(from: 0, to: done ? 1 : 0)
                .stroke(Color.black, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(width: 13, height: 10)
                .frame(width: 27, height: 27)
                .background(Color.vxUp, in: Circle())
                .scaleEffect(done || reduceMotion ? 1 : 0.65)
                .opacity(done ? 1 : 0)
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
                               summary: unitsText(quantity), estimate: try MoneyMath.quotedUSD(quantity, at: price), fee: 0)
        case .swap:
            guard asset != target else { throw SimulationError.invalidPair }
            let price = try live(asset)
            let units = try inputUnits(quantity, price: price)
            let gross = try MoneyMath.quotedUSD(units, at: price)
            let fee = try MoneyMath.multiply(gross, model.fee)
            let received = try MoneyMath.divide(MoneyMath.subtract(gross, fee), live(target))
            return TradeReview(command: .swap(asset, target, units, model.fee), summary: unitsText(units),
                               estimate: gross, fee: fee, received: received, market: true, price: price,
                               total: try MoneyMath.subtract(gross, fee))
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
            let units = try inputUnits(quantity, price: price)
            let exactNotional = useFiat && !isLimit && exactMaxUnits == nil
            let gross = exactNotional ? quantity : try MoneyMath.quotedUSD(units, at: price)
            let fee = try MoneyMath.multiply(gross, model.fee)
            let command: Command
            if isLimit { command = .limit(side, asset, units, price, model.fee) }
            else if exactNotional { command = .marketNotional(side, asset, quantity, model.fee) }
            else { command = .market(side, asset, units, model.fee) }
            let total = try side == .buy ? MoneyMath.add(gross, fee) : MoneyMath.subtract(gross, fee)
            return TradeReview(command: command, summary: unitsText(units), estimate: gross, fee: fee,
                               market: !isLimit, price: price, total: total)
        }
    }

    private var confirmedAmount: String? {
        guard let entry = savedEntry else { return nil }
        if let received = entry.counterAmount, let destination = entry.counterAsset {
            return "\(model.units(received)) \(Asset.ticker(destination))"
        }
        return entry.asset == "USD" ? model.money(entry.amount) : "\(model.units(entry.amount)) \(Asset.ticker(entry.asset))"
    }

    private var savedEntry: Entry? { model.portfolio.entries.last(where: { $0.id == intent.id }) }

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
        var total: Decimal?
    }
}

private struct TradeCheckmark: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.width * 0.35, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
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
