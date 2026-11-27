import SwiftUI

struct PriceAlert: Codable, Identifiable {
    var id = UUID()
    var asset: String
    var threshold: Decimal
    var above: Bool
    var triggeredAt: Date?
}

struct PriceAlertsScreen: View {
    @Environment(\.veltrixTheme) private var theme
    @EnvironmentObject private var model: VeltrixModel
    @State private var asset: String
    @State private var threshold = ""
    @State private var above = true
    @State private var validation = false

    init(initialAsset: String = "bitcoin") {
        _asset = State(initialValue: initialAsset)
    }

    var body: some View {
        PageScroll {
            Text("Alerts use the latest market quotes while Veltrix is open.")
                .font(.footnote).foregroundStyle(theme.muted)
            AssetPicker(title: "Asset", asset: $asset)
            TextField("Target price (USD)", text: $threshold).keyboardType(.decimalPad).panel(padding: 12)
            Picker("Trigger", selection: $above) {
                Text("At or above").tag(true)
                Text("At or below").tag(false)
            }.pickerStyle(.segmented)
            Button("Create price alert") {
                guard let price = Display.amount(threshold), (try? MoneyMath.quantity(price)) != nil else {
                    validation = true
                    return
                }
                model.addPriceAlert(PriceAlert(asset: asset, threshold: price, above: above))
                threshold = ""
                validation = false
                Feedback.success()
            }.buttonStyle(PrimaryButtonStyle())
            if validation { Text("Enter a valid amount.").font(.footnote).foregroundStyle(theme.negative) }
            ForEach(model.priceAlerts.reversed()) { alert in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: Asset.ticker(alert.asset)).font(.subheadline.weight(.semibold))
                        Text(verbatim: (alert.above ? "≥ " : "≤ ") + Display.money(alert.threshold, currency: "USD", digits: 8, minimum: 2))
                            .font(.caption.monospacedDigit())
                        if let date = alert.triggeredAt {
                            Text("Triggered · \(date.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption2).foregroundStyle(theme.positive)
                        }
                    }
                    Spacer()
                    IconButton(icon: "trash", label: "Delete price alert") { model.removePriceAlert(alert.id) }
                }
                Divider().overlay(theme.separator)
            }
        }
        .navigationTitle("Price alerts")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .dismissibleKeyboard()
    }
}

struct CurrencyConverter: View {
    @Environment(\.veltrixTheme) private var theme
    @EnvironmentObject private var model: VeltrixModel
    @State private var asset = "bitcoin"
    @State private var currency = "USD"
    @State private var amount = "1"

    var body: some View {
        PageScroll {
            AssetPicker(title: "Asset", asset: $asset)
            TextField("Quantity", text: $amount).keyboardType(.decimalPad).panel(padding: 12)
            Picker("Display currency", selection: $currency) {
                ForEach(Fiat.currencies, id: \.self) { Text(verbatim: $0).tag($0) }
            }
            Divider().overlay(theme.separator)
            CountValue(text: result)
                .font(.system(size: 46, weight: .semibold))
                .lineLimit(1).minimumScaleFactor(0.4)
            MarketStatus()
        }
        .navigationTitle("Currency converter")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .dismissibleKeyboard()
        .refreshable { await model.refresh() }
        .onAppear { currency = model.currency }
    }

    private var result: String {
        guard let units = Display.amount(amount), units >= 0, let price = model.prices[asset],
              let usd = try? MoneyMath.multiply(units, price),
              let value = try? Fiat.convert(usd, currency: currency, rates: model.rates) else { return "—" }
        return Display.money(value, currency: currency, digits: FinancialFormatter.pricePrecision(value, minimum: 2), minimum: 2)
    }
}
