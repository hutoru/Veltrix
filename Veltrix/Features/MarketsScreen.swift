import SwiftUI

private enum MarketSort: String, CaseIterable {
    case cap, change, volume, name
    var title: LocalizedStringKey {
        switch self {
        case .cap: return "Market cap"
        case .change: return "24h change"
        case .volume: return "Volume"
        case .name: return "Name"
        }
    }
}

private enum MarketCategory: String, CaseIterable {
    case trending, favorites, gainers, losers

    var title: LocalizedStringKey {
        switch self {
        case .trending: return "Trending"
        case .favorites: return "Favorites"
        case .gainers: return "Top Gainers"
        case .losers: return "Top Losers"
        }
    }
}

struct MarketsScreen: View {
    @EnvironmentObject private var model: VeltrixModel
    @State private var query = ""
    @State private var sort = MarketSort.cap
    @State private var category = MarketCategory.trending
    @State private var sortOverride = false

    var body: some View {
        let visible = filtered
        PageScroll {
            HStack {
                Text("Explore").font(.largeTitle.weight(.semibold)).accessibilityAddTraits(.isHeader)
                Spacer()
                NavigationLink { CurrencyConverter() } label: {
                    Image(systemName: "arrow.left.arrow.right").frame(width: 44, height: 44)
                        .background(Color.vxCard, in: Circle())
                }.accessibilityLabel(Text("Currency converter"))
            }
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.vxMuted)
                TextField("Search assets", text: $query).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("markets.search")
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .accessibilityLabel(Text("Clear search"))
                }
            }
            .panel(padding: 12)
            HStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(MarketCategory.allCases, id: \.self) { item in
                            Button {
                                category = item
                                sortOverride = false
                                Feedback.tap()
                            } label: {
                                Text(item.title).fixedSize().padding(.vertical, 12)
                                    .foregroundStyle(item == category ? Color.vxText : Color.vxMuted)
                                    .overlay(alignment: .bottom) {
                                        if item == category { Rectangle().fill(Color.vxAccent).frame(height: 2) }
                                    }
                            }.buttonStyle(.plain).accessibilityAddTraits(item == category ? .isSelected : [])
                        }
                    }
                }
                Menu {
                    Picker("Sort by", selection: Binding(get: { effectiveSort }, set: { sort = $0; sortOverride = true })) {
                        ForEach(MarketSort.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down").frame(width: 44, height: 44)
                }
                .accessibilityLabel(Text("Sort by"))
            }
            .font(.caption.weight(.semibold))
            MarketStatus()
            if query.isEmpty && category == .trending && !model.recentAssets.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.recentAssets) { asset in
                            NavigationLink(value: asset) {
                                HStack(spacing: 6) {
                                    CoinIcon(asset: asset, url: model.quotes[asset.id]?.image, size: 20)
                                    Text(verbatim: asset.ticker).font(.caption.weight(.medium))
                                }.padding(8).background(Color.vxCard, in: Capsule())
                            }.buttonStyle(.plain)
                        }
                    }
                }.accessibilityLabel(Text("Recently viewed"))
            }
            if visible.isEmpty {
                EmptyPanel(icon: "magnifyingglass", title: "No assets found", detail: "Try a different search or disable the favorites filter.")
            } else {
                HStack {
                    Text("Asset")
                    Spacer()
                    Text("Price / 24H")
                }.font(.caption).foregroundStyle(Color.vxMuted)
                LazyVStack(spacing: 0) {
                    ForEach(visible) { asset in
                        row(asset)
                        if asset != visible.last { Divider().overlay(Color.vxSeparator) }
                    }
                }
            }
            Link("Market data by CoinGecko", destination: URL(string: "https://www.coingecko.com/")!)
                .font(.caption).foregroundStyle(Color.vxMuted)
        }
        .refreshable { await model.refresh() }
        .scrollDismissesKeyboard(.interactively)
    }

    private var filtered: [Asset] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return Asset.catalog.filter { asset in
            let matches = term.isEmpty || asset.name.localizedCaseInsensitiveContains(term) || asset.ticker.localizedCaseInsensitiveContains(term)
            guard matches else { return false }
            switch category {
            case .trending: return true
            case .favorites: return model.favorites.contains(asset.id)
            case .gainers: return (model.quotes[asset.id]?.change ?? 0) > 0
            case .losers: return (model.quotes[asset.id]?.change ?? 0) < 0
            }
        }.sorted { a, b in
            let left = sortValue(a)
            let right = sortValue(b)
            if left != right {
                if let left, let right { return category == .losers && effectiveSort == .change ? left < right : left > right }
                return left != nil
            }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    private var effectiveSort: MarketSort {
        if sortOverride { return sort }
        switch category {
        case .trending: return .volume
        case .gainers, .losers: return .change
        case .favorites: return .cap
        }
    }

    private func sortValue(_ asset: Asset) -> Decimal? {
        let quote = model.quotes[asset.id]
        switch effectiveSort {
        case .cap: return quote?.marketCap
        case .change: return quote?.change
        case .volume: return quote?.volume
        case .name: return nil
        }
    }

    private func row(_ asset: Asset) -> some View {
        let quote = model.quotes[asset.id]
        let favorite = model.favorites.contains(asset.id)
        return HStack(spacing: 6) {
            NavigationLink(value: asset) {
                HStack(spacing: 10) {
                    CoinIcon(asset: asset, url: quote?.image)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: asset.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(verbatim: asset.ticker + " · " + model.compactMarketValue(quote?.marketCap))
                            .font(.caption2.monospacedDigit()).lineLimit(1).foregroundStyle(Color.vxMuted)
                    }
                    Spacer(minLength: 4)
                    if let values = quote?.sparkline, values.count > 2 {
                        MarketSparkline(values: values).frame(width: 52, height: 21)
                    }
                    if model.loading && quote == nil {
                        Skeleton().frame(width: 62, height: 25)
                    } else {
                        VStack(alignment: .trailing, spacing: 4) {
                            CountValue(text: model.money(quote?.price, privateValue: false, price: true))
                                .font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.55)
                            ChangeText(change: quote?.change)
                        }
                    }
                }
                .frame(minHeight: 56).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("market." + asset.ticker)
            Button {
                if favorite { model.favorites.remove(asset.id) } else { model.favorites.insert(asset.id) }
                Feedback.tap()
            } label: {
                Image(systemName: favorite ? "star.fill" : "star").font(.caption)
                    .foregroundStyle(favorite ? Color.vxHighlight : Color.vxMuted)
                    .frame(width: 39, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(favorite ? "Remove from favorites" : "Add to favorites"))
        }
    }
}

struct AssetScreen: View {
    @EnvironmentObject private var model: VeltrixModel
    let asset: Asset
    @State private var range = ChartRange.day
    @State private var candles = false
    @State private var history: MarketHistory?
    @State private var failure: String?
    @State private var cachedAt: Date?
    @State private var loading = false
    @State private var full = false
    @State private var trade: TradeIntent?
    @State private var reload = UUID()
    @State private var alert = false

    private var quote: Quote? { model.quotes[asset.id] }

    var body: some View {
        PageScroll {
            HStack(alignment: .top, spacing: 12) {
                CoinIcon(asset: asset, url: quote?.image, size: 46)
                VStack(alignment: .leading, spacing: 5) {
                    Text(verbatim: asset.name).font(.title2.bold())
                    Text(verbatim: asset.ticker).font(.caption.monospaced()).foregroundStyle(Color.vxMuted)
                }
                Spacer()
            }
            VStack(alignment: .leading, spacing: 8) {
                CountValue(text: model.money(quote?.price, privateValue: false, price: true))
                    .font(.system(size: 44, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.45)
                HStack {
                    ChangeText(change: quote?.change)
                    Text("CoinGecko · 24H").font(.caption2).foregroundStyle(Color.vxMuted)
                }
                if let quote, let date = quote.updated {
                    let fresh = model.usablePrices[asset.id] != nil
                    Text(quote.exchange ? "Kraken price" : "CoinGecko price").font(.caption2)
                    Text("\(fresh ? L.text("Updated") : L.text("Saved quote")) · \(date.formatted(date: .abbreviated, time: .standard))")
                        .font(.caption2).foregroundStyle(Color.vxMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Price history").font(.headline)
                    Spacer()
                    IconButton(icon: "arrow.up.left.and.arrow.down.right", label: "Full screen chart") { full = true }
                }
                chartBody(height: 206)
            }


            VStack(alignment: .leading, spacing: 13) {
                Text("Market statistics").font(.headline)
                LabeledContent("Market cap", value: model.money(quote?.marketCap, privateValue: false))
                LabeledContent("24h volume", value: model.money(quote?.volume, privateValue: false))
                if let position = model.portfolio.positions[asset.id] {
                    Divider()
                    LabeledContent("Holdings", value: model.units(position.units) + " " + asset.ticker)
                    if let total = try? model.portfolio.value(prices: model.prices), total > 0,
                       let price = quote?.price,
                       let share = try? MoneyMath.multiply(MoneyMath.divide(MoneyMath.multiply(position.units, price), total), 100) {
                        LabeledContent("Portfolio allocation", value: model.hide ? "••••" : Display.number(share, maximum: 2) + "%")
                    }
                    LabeledContent("Average purchase price", value: model.money(position.average, price: true))
                    let positionValue = quote?.price.flatMap { try? MoneyMath.multiply(position.units, $0) }
                    LabeledContent("Position value", value: model.money(positionValue))
                    let pnl = positionValue.flatMap { try? MoneyMath.subtractValuation($0, position.basis) }
                    LabeledContent("Unrealized P&L", value: model.signedMoney(pnl))
                }
            }
            .font(.subheadline)
            .panel()

            VStack(alignment: .leading, spacing: 9) {
                Text("About asset").font(.headline)
                Text(asset.category).font(.subheadline).foregroundStyle(Color.vxMuted)
                Link("Asset profile on CoinGecko", destination: URL(string: "https://www.coingecko.com/en/coins/" + asset.id)!)
                    .font(.footnote.weight(.semibold))
            }
            let trades = model.portfolio.entries.reversed().filter { $0.asset == asset.id || $0.counterAsset == asset.id }
            if !trades.isEmpty {
                Text("Activity").font(.headline)
                ForEach(trades) { entry in
                    NavigationLink { EntryScreen(entry: entry) } label: { EntryRow(entry: entry) }.buttonStyle(.plain)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 10) {
                Button("Sell") { Feedback.tap(); trade = TradeIntent(action: .sell, asset: asset.id) }
                    .buttonStyle(PrimaryButtonStyle(tint: .vxDown, ink: Color.black, height: 54))
                Button("Buy") { Feedback.tap(); trade = TradeIntent(action: .buy, asset: asset.id) }
                    .buttonStyle(PrimaryButtonStyle(tint: .vxUp, ink: Color.black, height: 54))
            }.padding(.horizontal, 18).padding(.vertical, 8).background(Color.vxBackground)
        }
        .navigationTitle(Text(verbatim: asset.name))
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Button { alert = true } label: { Label("Price alerts", systemImage: "bell.badge") }
            }
            ToolbarItem(placement: .primaryAction) {
                let favorite = model.favorites.contains(asset.id)
                Button {
                    if favorite { model.favorites.remove(asset.id) } else { model.favorites.insert(asset.id) }
                    Feedback.tap()
                } label: { Image(systemName: favorite ? "star.fill" : "star") }
                    .accessibilityLabel(Text(favorite ? "Remove from favorites" : "Add to favorites"))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.recordAsset(asset) }
        .sheet(isPresented: $alert) {
            NavigationStack {
                PriceAlertsScreen(initialAsset: asset.id)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { alert = false } } }
            }
        }
        .fullScreenCover(item: $trade) { TradeScreen(intent: $0) }
        .task(id: LoadKey(range: range, candles: candles, reload: reload)) { await load() }
        .refreshable { await model.refresh(); reload = UUID() }
        .fullScreenCover(isPresented: $full) {
            NavigationStack {
                PageScroll {
                    chartBody(height: 345)
                }
                .navigationTitle(Text(verbatim: asset.name))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { full = false } } }
            }
        }
    }

    private func chartBody(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if loading && history == nil { Skeleton().frame(height: 78) }
            VeltrixChart(samples: history?.samples ?? [], range: $range, candles: $candles, allowsCandles: true, height: height) {
                model.money($0, privateValue: false, price: true)
            }
            if let history {
                Text("Source · \(history.source)").font(.caption).foregroundStyle(Color.vxMuted)
                if history.capped {
                    Text("Available all-time data is limited to one year for this asset.")
                        .font(.caption).foregroundStyle(Color.vxMuted)
                }
                if let cachedAt {
                    Text("History saved · \(cachedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(Color.vxMuted)
                }
            }
            if let failure {
                Text(verbatim: failure).font(.caption).foregroundStyle(Color.vxMuted)
                Button("Retry") { reload = UUID() }.font(.caption.weight(.semibold))
            }
        }
    }

    @MainActor private func load() async {
        let chosenRange = range
        let chosenMode = candles
        history = nil
        failure = nil
        cachedAt = nil
        loading = true
        defer { if !Task.isCancelled { loading = false } }
        if let cached = await model.cachedHistory(asset, range: chosenRange, candles: chosenMode), !Task.isCancelled {
            history = cached.value
            cachedAt = cached.saved
        }
        do {
            let result = try await model.loadHistory(asset, range: chosenRange, candles: chosenMode)
            try Task.checkCancellation()
            history = result
            cachedAt = nil
        } catch {
            if !Task.isCancelled { failure = Display.error(error) }
        }
    }

    private struct LoadKey: Equatable {
        let range: ChartRange
        let candles: Bool
        let reload: UUID
    }
}


private extension Asset {
    var category: LocalizedStringKey {
        switch ticker {
        case "BTC": return "Bitcoin is a peer-to-peer network with a fixed issuance schedule."
        case "USDT", "USDC": return "A stablecoin designed to track the US dollar."
        case "LINK": return "Chainlink powers decentralized oracle services for smart contracts."
        case "UNI": return "UNI is the governance token of the Uniswap protocol."
        case "ARB", "OP", "POL": return "A token used in an Ethereum scaling ecosystem."
        case "DOGE", "SHIB", "PEPE": return "A cryptocurrency with origins in internet culture."
        case "XMR": return "Monero is a network designed for private digital payments."
        case "LTC", "BCH", "XRP", "XLM": return "A digital asset designed for payments and transfers."
        default: return "A digital asset used in a network that supports decentralized applications."
        }
    }
}
