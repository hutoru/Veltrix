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
    let intent: TradeIntent

    var body: some View {
        if intent.action == .receive {
            ReceiveRequestScreen(initialAsset: intent.asset)
        } else {
            TradeEditor(intent: intent)
        }
    }
}

struct TradeEditor: View {
    private enum Field: Hashable { case amount, limit, counterparty }

    @EnvironmentObject private var model: VeltrixModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    let intent: TradeIntent
    @State private var asset: String
    @State private var target = "ethereum"
    @State private var amount = ""
    @State private var calculatedAmount = false
    @State private var limit = ""
    @State private var label = ""
    @State private var isLimit = false
    @State private var useFiat = false
    @State private var exactMaxUnits: Decimal?
    @State private var review: TradeReview?
    @State private var reviewedAt: Date?
    @State private var error: String?
    @State private var done = false
    @State private var processing = false
    @State private var ringProgress: CGFloat = 0
    @State private var scanner = false
    @State private var network: TransferNetwork?
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { UITestMode.enabled || systemReduceMotion }

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
                            TransactionSuccessView(entry: savedEntry,
                                                   order: model.portfolio.orders.first { $0.id == intent.id },
                                                   summary: confirmedAmount ?? review?.summary ?? "",
                                                   executionPrice: review?.price,
                                                   iconAsset: asset, processing: processing, progress: ringProgress)
                                .task { await animateCompletion() }
                        } else if let review {
                            reviewContent(review)
                        } else {
                            editor
                        }
                        if let error, review != nil && !done && !processing {
                            Text(verbatim: error).font(.footnote).foregroundStyle(Color.vxDown)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, review == nil ? 14 : 8)
                    .frame(maxWidth: 490)
                    .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.vxBackground.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !processing && focusedField == nil { footer }
            }
            .navigationTitle(Text(verbatim: navigationTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(review != nil && !done ? "Edit" : "Close") {
                        if review != nil && !done { review = nil; error = nil }
                        else { dismiss() }
                    }
                    .foregroundStyle(Color.vxText)
                    .tint(.vxText)
                    .disabled(processing)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                        .accessibilityIdentifier("keyboard.done")
                }
            }
            .interactiveDismissDisabled(processing)
            .fullScreenCover(isPresented: $scanner) {
                QRScanner { value in label = value; error = nil }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: review != nil)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: done)
            .tint(.vxHighlight)
            .onChange(of: asset) { _ in amount = ""; exactMaxUnits = nil; error = nil }
        }
    }

    private var editor: some View {
        VStack(spacing: 14) {
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
                        .focused($focusedField, equals: .counterparty)
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

            if let error {
                Text(verbatim: error).font(.footnote).foregroundStyle(Color.vxDown)
            }
        }
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
                        focusedField = nil
                        review = draft
                        reviewedAt = .now
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
        .buttonStyle(PrimaryButtonStyle(tint: done ? .vxText : actionColor,
                                         height: 52))
        .frame(maxWidth: 490)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color.vxBackground)
        .overlay(alignment: .top) { Rectangle().fill(Color.vxSeparator).frame(height: 1).allowsHitTesting(false) }
    }

    private let reviewLifetime: TimeInterval = 15

    private var isTrading: Bool { [.buy, .sell, .swap].contains(intent.action) }
    private var actionColor: Color {
        switch intent.action {
        case .buy: return .vxUp
        case .sell: return .vxDown
        default: return .vxText
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
                        .focused($focusedField, equals: .limit)
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
                calculatedAmount = true
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
        let currentPrices = model.usablePrices
        return LabeledContent {
            AssetPicker(title: title, asset: selection, assets: Asset.catalog.filter { asset in
                !asset.isTokenizedStock || currentPrices[asset.id] != nil
                    || model.portfolio.positions[asset.id] != nil || selection.wrappedValue == asset.id
            })
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(.vxText)
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
        let inputText = displayedAmount
        return VStack(spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                TextField("0", text: Binding(get: { displayedAmount }, set: { input in
                    amount = input
                    calculatedAmount = false
                    exactMaxUnits = nil
                    error = nil
                }))
                .font(.system(size: max(20, (isTrading ? 62 : 51) - CGFloat(max(0, inputText.count - 6)) * 3),
                              weight: .semibold).monospacedDigit())
                .multilineTextAlignment(.trailing)
                .keyboardType(.decimalPad)
                .focused($focusedField, equals: .amount)
                .accessibilityLabel(Text("Amount"))
                .accessibilityIdentifier("trade.amount")
                Text(verbatim: amountUnit)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.vxMuted)
                    .accessibilityIdentifier("trade.amount.unit")
            }
            CountValue(text: equivalent ?? " ")
                .font(.footnote)
                .foregroundStyle(Color.vxMuted)
                .accessibilityHidden(equivalent == nil)
        }
        .frame(maxWidth: .infinity, minHeight: isTrading ? 84 : 72)
    }

    private var amountIsCash: Bool { intent.action == .deposit || useFiat }
    private var amountUnit: String { amountIsCash ? "USD" : Asset.ticker(asset) }

    private var displayedAmount: String {
        guard amountIsCash, calculatedAmount, let value = Display.amount(amount) else { return amount }
        let rounded = MoneyMath.round(value, scale: FinancialFormatter.pricePrecision(value, minimum: 2))
        return rounded > 0 ? Display.input(rounded) : amount
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
        case .buy, .deposit, .receive: return model.money(try? model.portfolio.freeCash(), minimumDigits: 2)
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

    private func fill(_ percent: Int) {
        guard let available else { return }
        do {
            let size = try TradeSizing.preset(available: available, percent: percent,
                                              sourceIsUSD: intent.action == .buy, inputIsUSD: amountIsCash,
                                              price: pricingQuote)
            amount = Display.input(size)
            calculatedAmount = true
            exactMaxUnits = percent == 100 && intent.action != .buy ? available : nil
            error = nil
        } catch {
            self.error = Display.error(error)
        }
    }

    private func reviewContent(_ review: TradeReview) -> some View {
        VStack(spacing: 12) {
            if let coin = Asset.catalog.first(where: { $0.id == asset }), intent.action != .deposit {
                CoinIcon(asset: coin, url: model.quotes[asset]?.image, size: 46)
            }
            Text("Review order").font(.subheadline.weight(.medium)).foregroundStyle(Color.vxMuted)
                .accessibilityIdentifier("trade.review.title")
            Text(verbatim: review.total.map { model.money($0, price: true, minimumDigits: 2) } ?? review.summary)
                .font(.system(size: 38, weight: .semibold).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.4)
            if review.total != nil {
                Text(verbatim: review.summary).font(.subheadline.monospacedDigit()).foregroundStyle(Color.vxMuted)
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
                if let estimate = review.estimate {
                    LabeledContent("Cost", value: model.money(estimate, price: true, minimumDigits: 2))
                }
                if let fee = review.fee {
                    Divider().overlay(Color.vxSeparator)
                    LabeledContent("Fee", value: "≈ " + model.money(fee, price: true, minimumDigits: 2))
                }
                if let total = review.total {
                    Divider().overlay(Color.vxSeparator)
                    LabeledContent("Total ≈", value: model.money(total, price: true, minimumDigits: 2)).fontWeight(.semibold)
                }
                if let quantity = review.received {
                    LabeledContent("Receive asset", value: "\(model.units(quantity)) \(Asset.ticker(target))")
                }
                Divider().overlay(Color.vxSeparator)
                LabeledContent("Balance", value: availableLabel)
            }.font(.subheadline.monospacedDigit()).panel(padding: 12)
            if !review.prices.isEmpty, let reviewedAt {
                QuoteCountdown(expiration: reviewedAt.addingTimeInterval(reviewLifetime))
            }
        }
    }

    private func submit(_ review: TradeReview) {
        guard !processing, !done else { return }
        if !review.prices.isEmpty, reviewedAt.map({ Date().timeIntervalSince($0) >= reviewLifetime }) ?? true {
            do {
                let refreshed = try makeReview()
                try model.validateTrade(refreshed.command, id: intent.id)
                self.review = refreshed
                reviewedAt = .now
                error = L.text("Quote refreshed. Review the new amounts and confirm.")
            } catch {
                self.error = Display.error(error)
            }
            return
        }
        if model.execute(review.command, id: intent.id, showFeedback: false, reviewedPrices: review.prices) {
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
                               summary: unitsText(quantity), estimate: try MoneyMath.quotedUSD(quantity, at: price), fee: 0,
                               price: price, prices: [asset: price])
        case .swap:
            guard asset != target else { throw SimulationError.invalidPair }
            let price = try live(asset)
            let units = try inputUnits(quantity, price: price)
            let gross = try MoneyMath.quotedUSD(units, at: price)
            let fee = try MoneyMath.multiply(gross, model.fee)
            let targetPrice = try live(target)
            let received = try MoneyMath.divide(MoneyMath.subtract(gross, fee), targetPrice)
            return TradeReview(command: .swap(asset, target, units, model.fee), summary: unitsText(units),
                               estimate: gross, fee: fee, received: received, price: price,
                               total: try MoneyMath.subtract(gross, fee), prices: [asset: price, target: targetPrice])
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
                               price: price, total: total, prices: isLimit ? [:] : [asset: price])
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
        var price: Decimal?
        var total: Decimal?
        var prices: [String: Decimal] = [:]
    }
}

private struct QuoteCountdown: View {
    let expiration: Date
    @State private var now = Date()

    var body: some View {
        let seconds = max(0, Int(ceil(expiration.timeIntervalSince(UITestMode.enabled ? expiration.addingTimeInterval(-15) : now))))
        Label {
            Text(verbatim: seconds == 0 ? L.text("Quote expired") : L.format("Quote expires in %d s", seconds))
                .monospacedDigit()
        } icon: {
            Image(systemName: "clock")
        }
        .font(.caption)
        .foregroundStyle(seconds == 0 ? Color.vxDown : Color.vxMuted)
        .accessibilityIdentifier("trade.quote.countdown")
        .task(id: expiration) {
            guard !UITestMode.enabled else { return }
            while !Task.isCancelled {
                now = .now
                let remaining = expiration.timeIntervalSince(now)
                guard remaining > 0 else { return }
                let nextTick = min(remaining, remaining - ceil(remaining) + 1)
                try? await Task.sleep(nanoseconds: UInt64(max(0.01, nextTick) * 1_000_000_000))
            }
        }
    }
}

struct TransactionSuccessView: View {
    @EnvironmentObject private var model: VeltrixModel
    let entry: Entry?
    let order: LimitOrder?
    let summary: String
    let executionPrice: Decimal?
    let iconAsset: String
    let processing: Bool
    let progress: CGFloat

    var body: some View {
        VStack(spacing: 14) {
            mark
            if processing {
                Text("Updating portfolio").font(.footnote).foregroundStyle(Color.vxMuted)
            } else {
                Text(order != nil && entry == nil ? "Limit order placed" : "Operation saved")
                    .font(.title2.bold()).accessibilityIdentifier("trade.saved")
                CountValue(text: entry?.settlementUSD.map { model.money($0, price: true, minimumDigits: 2) } ?? summary)
                    .font(.largeTitle.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.35)
                if let entry, entry.asset != "USD", entry.settlementUSD != nil {
                    Text(verbatim: summary).font(.subheadline.monospacedDigit())
                        .foregroundStyle(Color.vxMuted).lineLimit(1).minimumScaleFactor(0.55)
                }
                details
                if let entry {
                    NavigationLink("Operation details") { EntryScreen(entry: entry) }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("trade.details")
                } else if let order {
                    NavigationLink("Operation details") {
                        PageScroll { LimitOrderSummary(order: order) }
                            .navigationTitle("Operation details")
                            .navigationBarTitleDisplayMode(.inline)
                    }.buttonStyle(.bordered)
                }
            }
        }
        .frame(maxWidth: .infinity).padding(.top, 6)
    }

    private var mark: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle().strokeBorder(Color.vxSeparator, lineWidth: 2)
            Circle().trim(from: 0, to: progress)
                .stroke(Color.vxHighlight, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Group {
                if let coin = Asset.catalog.first(where: { $0.id == iconAsset }), entry?.asset != "USD" {
                    CoinIcon(asset: coin, url: model.quotes[coin.id]?.image, size: 48)
                } else {
                    VeltrixMark().fill(Color.vxText).frame(width: 31, height: 31)
                }
            }.frame(width: 80, height: 80)
            Image(systemName: "checkmark.circle.fill")
                .font(.title2).foregroundStyle(Color.vxHighlight)
                .background(Color.vxCard, in: Circle())
                .opacity(processing ? 0 : 1)
        }.frame(width: 80, height: 80).accessibilityHidden(true)
    }

    private var details: some View {
        VStack(spacing: 9) {
            if let entry {
                LabeledContent("Type", value: entry.kind.localized)
                if let total = entry.settlementUSD {
                    Divider()
                    LabeledContent("Total", value: model.money(total, price: true, minimumDigits: 2))
                }
                if let price = order?.filledPrice ?? executionPrice, entry.kind != .deposit {
                    Divider()
                    LabeledContent("Fill price", value: model.money(price, price: true, minimumDigits: 2))
                }
                if [.buy, .sell, .swap].contains(entry.kind) {
                    Divider()
                    LabeledContent("Fee", value: model.money(entry.fee, price: true, minimumDigits: 2))
                }
            } else if let order {
                LabeledContent("Limit price", value: model.money(order.limit, price: true, minimumDigits: 2))
            }
            if let date = entry?.date ?? order?.date {
                Divider()
                LabeledContent("Date", value: date.formatted(date: .abbreviated, time: .standard))
            }
            Divider()
            LabeledContent("Available cash", value: model.money(try? model.portfolio.freeCash()))
        }.font(.footnote.monospacedDigit()).panel(padding: 14)
    }

}
