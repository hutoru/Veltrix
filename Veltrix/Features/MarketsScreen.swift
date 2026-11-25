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

struct MarketsScreen: View {
    @EnvironmentObject private var model: VeltrixModel
    @State private var query = ""
    @State private var sort = MarketSort.cap
    @State private var onlyFavorites = false

    var body: some View {
        PageScroll {
            PageHeader(title: "Markets", detail: "Crypto prices in your display currency") { SimBadge() }
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
                Toggle(isOn: $onlyFavorites) { Label("Favorites", systemImage: onlyFavorites ? "star.fill" : "star") }
                    .toggleStyle(.button)
                Spacer()
                Menu {
                    Picker("Sort by", selection: $sort) {
                        ForEach(MarketSort.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                } label: {
                    Label(sort.title, systemImage: "arrow.up.arrow.down")
                        .font(.caption.weight(.semibold))
                        .frame(minHeight: 38)
                        .padding(.horizontal, 10)
                        .background(Color.vxSurface, in: RoundedRectangle(cornerRadius: 10))
                }
                .accessibilityLabel(Text("Sort by"))
            }
            .font(.caption.weight(.semibold))
            MarketStatus()
            if filtered.isEmpty {
                EmptyPanel(icon: "magnifyingglass", title: "No assets found", detail: "Try a different search or disable the favorites filter.")
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { asset in
                        row(asset)
                        if asset != filtered.last { Divider() }
                    }
                }
                .panel(padding: 13)
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
            (!onlyFavorites || model.favorites.contains(asset.id)) &&
                (term.isEmpty || asset.name.localizedCaseInsensitiveContains(term) || asset.ticker.localizedCaseInsensitiveContains(term))
        }.sorted { a, b in
            let left = sortValue(a)
            let right = sortValue(b)
            if left != right {
                if let left, let right { return left > right }
                return left != nil
            }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    private func sortValue(_ asset: Asset) -> Decimal? {
        let quote = model.quotes[asset.id]
        switch sort {
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
                        Text(verbatim: asset.ticker).font(.caption2.monospaced()).foregroundStyle(Color.vxMuted)
                    }
                    Spacer(minLength: 4)
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
                SimBadge()
            }
            VStack(alignment: .leading, spacing: 8) {
                CountValue(text: model.money(quote?.price, privateValue: false, price: true))
                    .font(.system(size: 36, weight: .semibold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.45)
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
            .panel()

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Price history").font(.headline)
                    Spacer()
                    IconButton(icon: "arrow.up.left.and.arrow.down.right", label: "Full screen chart") { full = true }
                }
                chartBody(height: 206)
            }
            .panel()

            HStack {
                Button("Buy") { trade = TradeIntent(action: .buy, asset: asset.id) }.buttonStyle(PrimaryButtonStyle())
                Button("Sell") { trade = TradeIntent(action: .sell, asset: asset.id) }.buttonStyle(PrimaryButtonStyle())
            }

            VStack(alignment: .leading, spacing: 13) {
                Text("Market statistics").font(.headline)
                LabeledContent("Market cap", value: model.money(quote?.marketCap, privateValue: false))
                LabeledContent("24h volume", value: model.money(quote?.volume, privateValue: false))
                if let position = model.portfolio.positions[asset.id] {
                    Divider()
                    LabeledContent("Holdings", value: model.units(position.units) + " " + asset.ticker)
                    LabeledContent("Average purchase price", value: model.money(position.average, price: true))
                }
            }
            .font(.subheadline)
            .panel()
        }
        .navigationTitle(Text(verbatim: asset.ticker))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $trade) { TradeScreen(intent: $0) }
        .task(id: LoadKey(range: range, candles: candles, reload: reload)) { await load() }
        .refreshable { await model.refresh(); reload = UUID() }
        .fullScreenCover(isPresented: $full) {
            NavigationStack {
                PageScroll {
                    SimBadge()
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
            ChartPanel(samples: history?.samples ?? [], range: $range, candles: $candles, allowsCandles: true, height: height) {
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
