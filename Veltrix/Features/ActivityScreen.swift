import SwiftUI

extension OperationKind {
    var title: LocalizedStringKey {
        switch self {
        case .buy: return "Buy"
        case .sell: return "Sell"
        case .swap: return "Swap"
        case .send: return "Send"
        case .receive: return "Receive"
        case .deposit: return "Deposit"
        case .adjustment: return "Adjustment"
        case .cardTopUp: return "Card top-up"
        case .cardReturn: return "Card funds returned"
        case .cardPayment: return "Card payment"
        case .refund: return "Refund"
        }
    }

    var icon: String {
        switch self {
        case .buy: return "plus.circle"
        case .sell: return "minus.circle"
        case .swap: return "arrow.left.arrow.right"
        case .send: return "arrow.up.right"
        case .receive: return "arrow.down.left"
        case .deposit: return "tray.and.arrow.down"
        case .adjustment: return "slider.horizontal.3"
        case .cardTopUp: return "creditcard.and.123"
        case .cardReturn: return "arrow.uturn.left"
        case .cardPayment: return "creditcard"
        case .refund: return "arrow.counterclockwise"
        }
    }

    var localized: String {
        switch self {
        case .cardTopUp: return L.text("Card top-up")
        case .cardReturn: return L.text("Card funds returned")
        case .cardPayment: return L.text("Card payment")
        default: return L.text(rawValue.capitalized)
        }
    }
}

struct ActivityScreen: View {
    @EnvironmentObject private var model: VeltrixModel
    @State private var showOrders = false
    @State private var query = ""
    @State private var category: OperationKind?
    @State private var status: OrderStatus?
    @State private var descending = true
    @State private var cancelOrder: LimitOrder?

    var body: some View {
        PageScroll {
            PageHeader(title: "Activity", detail: "Simulation history and open orders") { SimBadge() }
            Picker("Activity view", selection: $showOrders) {
                Text("Transactions").tag(false)
                Text("Orders").tag(true)
            }
            .pickerStyle(.segmented)
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.vxMuted)
                TextField("Search activity", text: $query).textInputAutocapitalization(.never).autocorrectionDisabled()
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel(Text("Clear search"))
                }
            }
            .panel(padding: 12)
            filters
            if showOrders { orders } else { transactions }
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: showOrders) { _ in query = "" }
        .confirmationDialog("Cancel limit order?", isPresented: .init(get: { cancelOrder != nil }, set: { if !$0 { cancelOrder = nil } }),
                            titleVisibility: .visible, presenting: cancelOrder) { order in
            Button("Cancel order", role: .destructive) { _ = model.execute(.cancel(order.id)); cancelOrder = nil }
            Button("Keep order", role: .cancel) { cancelOrder = nil }
        } message: { _ in Text("Reserved funds or assets will become available again.") }
    }

    private var filters: some View {
        HStack {
            Menu {
                if showOrders {
                    Picker("Status", selection: $status) {
                        Text("All").tag(OrderStatus?.none)
                        ForEach([OrderStatus.open, .filled, .cancelled], id: \.self) { value in
                            Text(value.title).tag(Optional(value))
                        }
                    }
                } else {
                    Picker("Category", selection: $category) {
                        Text("All").tag(OperationKind?.none)
                        ForEach(OperationKind.allCases, id: \.self) { value in
                            Text(value.title).tag(Optional(value))
                        }
                    }
                }
            } label: {
                Label(filterTitle, systemImage: "line.3.horizontal.decrease.circle")
                    .font(.caption.weight(.semibold))
                    .frame(minHeight: 35)
            }
            Spacer()
            Button {
                descending.toggle()
            } label: { Label(descending ? "Newest first" : "Oldest first", systemImage: "arrow.up.arrow.down") }
                .font(.caption.weight(.semibold))
        }
    }

    private var filterTitle: LocalizedStringKey {
        if showOrders { return status?.title ?? "All statuses" }
        return category?.title ?? "All categories"
    }

    private var transactions: some View {
        let entries = model.portfolio.entries.filter {
            (category == nil || $0.kind == category) &&
            matches([$0.kind.localized, Asset.ticker($0.asset), $0.note, $0.counterAsset.map(Asset.ticker) ?? ""])
        }
        let groups = Dictionary(grouping: entries) { Calendar.current.startOfDay(for: $0.date) }
        return VStack(alignment: .leading, spacing: 15) {
            if model.portfolio.entries.contains(where: { $0.kind == .cardPayment }) {
                DisclosureGroup("Card spending") { spending }
                    .font(.subheadline.weight(.medium))
            }
            if entries.isEmpty {
                EmptyPanel(icon: "clock.arrow.circlepath", title: "No transactions found",
                           detail: "Completed simulations appear here.")
            } else {
                ForEach(groups.keys.sorted(by: descending ? (>) : (<)), id: \.self) { day in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(day, style: .date).font(.subheadline.weight(.semibold)).foregroundStyle(Color.vxMuted)
                        VStack(spacing: 1) {
                            ForEach(sortedEntries(groups[day] ?? [])) { entry in
                                NavigationLink {
                                    EntryScreen(entry: entry)
                                } label: { EntryRow(entry: entry) }
                                .buttonStyle(.plain)
                                Divider()
                            }
                        }
                        .panel(padding: 12)
                    }
                }
            }
        }
    }

    private var orders: some View {
        let matches = model.portfolio.orders.filter { order in
            (status == nil || order.status == status) && self.matches([Asset.ticker(order.asset), order.side.rawValue, order.status.rawValue])
        }
        return VStack(alignment: .leading, spacing: 13) {
            if matches.isEmpty {
                EmptyPanel(icon: "list.bullet.rectangle", title: "No orders found",
                           detail: "Market trades are in Transactions. Limit orders appear here.")
            }
            ForEach(matches.sorted { descending ? $0.date > $1.date : $0.date < $1.date }) { order in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label(order.side == .buy ? "Buy" : "Sell", systemImage: order.side == .buy ? "plus.circle" : "minus.circle")
                            .font(.headline)
                        Text(verbatim: Asset.ticker(order.asset)).font(.subheadline.monospaced())
                        Spacer()
                        Text(order.status.title).font(.caption.weight(.semibold)).foregroundStyle(Color.vxHighlight)
                    }
                    LabeledContent("Quantity", value: model.units(order.units))
                    LabeledContent("Limit price", value: model.money(order.limit, privateValue: false, price: true))
                    if let filled = order.filledPrice {
                        LabeledContent("Fill price", value: model.money(filled, privateValue: false, price: true))
                    }
                    Text(order.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption).foregroundStyle(Color.vxMuted)
                    if let closed = order.closedAt {
                        Text("Closed · \(closed.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(Color.vxMuted)
                    }
                    if order.status == .open {
                        Button("Cancel order", role: .destructive) { cancelOrder = order }
                            .buttonStyle(.bordered)
                    }
                }
                .font(.footnote)
                .panel()
            }
        }
    }

    private var spending: some View {
        let payments = model.portfolio.entries.filter { $0.kind == .cardPayment }
        let refunds = model.portfolio.entries.filter { $0.kind == .refund }
        let paid = try? payments.map(\.amount).reduce(Decimal.zero, MoneyMath.add)
        let refunded = try? refunds.map(\.amount).reduce(Decimal.zero, MoneyMath.add)
        return VStack(alignment: .leading, spacing: 7) {
            LabeledContent("Payments", value: model.money(paid))
            LabeledContent("Refunds", value: model.money(refunded))
        }
        .font(.footnote)
        .panel()
    }

    private func matches(_ terms: [String]) -> Bool {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || terms.contains { $0.localizedCaseInsensitiveContains(value) }
    }

    private func sortedEntries(_ entries: [Entry]) -> [Entry] {
        entries.sorted { descending ? $0.date > $1.date : $0.date < $1.date }
    }
}

struct EntryRow: View {
    @EnvironmentObject private var model: VeltrixModel
    let entry: Entry

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: entry.kind.icon)
                .font(.subheadline.weight(.semibold)).foregroundStyle(Color.vxHighlight)
                .frame(width: 37, height: 37).background(Color.vxAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.kind.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(entry.date, style: .time).font(.caption2).foregroundStyle(Color.vxMuted)
            }
            Spacer(minLength: 5)
            VStack(alignment: .trailing, spacing: 4) {
                Text(verbatim: entry.asset == "USD" ? model.money(entry.amount) :
                      "\(model.units(entry.amount)) \(Asset.ticker(entry.asset))")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                Text("Simulated").font(.caption2).foregroundStyle(Color.vxMuted)
            }
            .lineLimit(1).minimumScaleFactor(0.52)
        }
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .accessibilityIdentifier("activity." + entry.kind.rawValue)
    }
}

struct EntryScreen: View {
    @EnvironmentObject private var model: VeltrixModel
    let entry: Entry
    @State private var refund = false

    var body: some View {
        PageScroll {
            PageHeader(title: entry.kind.title, detail: "Simulated operation") { SimBadge() }
            VStack(alignment: .leading, spacing: 16) {
                LabeledContent("Amount", value: summary)
                LabeledContent("Date", value: entry.date.formatted(date: .abbreviated, time: .standard))
                LabeledContent("Status", value: L.text("Simulated"))
                if let usd = entry.usd, entry.asset != "USD" { LabeledContent("Value", value: model.money(usd)) }
                if entry.fee != 0 { LabeledContent("Fee", value: model.money(entry.fee, price: true)) }
                if let profit = entry.profit { LabeledContent("Realized P&L", value: model.money(profit)) }
                if let other = entry.counterAmount, let asset = entry.counterAsset {
                    LabeledContent("Receive asset", value: "\(model.units(other)) \(Asset.ticker(asset))")
                }
                if !entry.note.isEmpty { LabeledContent("Details", value: entry.note) }
            }
            .font(.subheadline)
            .panel()
            if entry.kind == .cardPayment, let card = entry.cardID, model.cards.contains(where: { $0.id == card }) {
                if model.portfolio.entries.contains(where: { $0.reference == entry.id }) {
                    Label("Refunded", systemImage: "checkmark.circle").foregroundStyle(Color.vxUp)
                } else {
                    Button("Simulate refund") { refund = true }.buttonStyle(PrimaryButtonStyle())
                }
            }
            if !model.hide {
                ShareLink(item: "VELTRIX · Simulation · \(entry.kind.localized) · \(summary) · \(entry.date.formatted())") {
                    Label("Share confirmation", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }
        }
        .navigationTitle("Operation details")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Refund simulated payment?", isPresented: $refund, titleVisibility: .visible) {
            if let card = entry.cardID {
                Button("Refund") { _ = model.execute(.refund(card, entry.id)) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var summary: String {
        entry.asset == "USD" ? model.money(entry.amount) : "\(model.units(entry.amount)) \(Asset.ticker(entry.asset))"
    }
}

extension OrderStatus {
    var title: LocalizedStringKey {
        switch self {
        case .open: return "Open"
        case .filled: return "Filled"
        case .cancelled: return "Cancelled"
        }
    }
}
