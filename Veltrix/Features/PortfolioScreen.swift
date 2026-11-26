import SwiftUI
import UIKit

struct PortfolioScreen: View {
    private enum HomeTab: String, CaseIterable {
        case assets, cards, favorites

        var title: LocalizedStringKey {
            switch self {
            case .assets: return "Assets"
            case .cards: return "Cards"
            case .favorites: return "Favorites"
            }
        }
    }

    private enum HoldingSort: String, CaseIterable {
        case value, name, change
        var label: LocalizedStringKey {
            switch self {
            case .value: return "Portfolio value"
            case .name: return "Name"
            case .change: return "24h change"
            }
        }
    }

    private enum HomeSection: String, CaseIterable {
        case recent, allocation, statistics, popular

        var title: LocalizedStringKey {
            switch self {
            case .allocation: return "Portfolio allocation"
            case .popular: return "Popular assets"
            case .recent: return "Recent activity"
            case .statistics: return "Portfolio statistics"
            }
        }
    }

    @EnvironmentObject private var model: VeltrixModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var homeTab = HomeTab.assets
    @State private var query = ""
    @State private var range = ChartRange.week
    @State private var candles = false
    @State private var trade: TradeIntent?
    @AppStorage("profileName") private var profileName = ""
    @AppStorage("holdingSort") private var sort = HoldingSort.value
    @AppStorage("hideZeroHoldings") private var hideZero = true
    @AppStorage("homeSectionOrder") private var sectionOrder = ""
    @State private var more = false
    @State private var addAsset = false
    @State private var chart = false
    @State private var share = false
    @State private var scanner = false

    private var portfolio: Portfolio { model.portfolio }
    private var value: Decimal? { try? portfolio.value(prices: model.prices) }

    var body: some View {
        PageScroll {
            HStack {
                Menu {
                    ForEach(model.ledger.portfolios) { item in
                        Button { _ = model.execute(.selectPortfolio(item.id), showFeedback: false) } label: {
                            if item.id == portfolio.id { Label(item.name, systemImage: "checkmark") }
                            else { Text(verbatim: item.name) }
                        }
                    }
                } label: {
                    ProfileAvatar(size: 36)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel(Text("Portfolios"))
                Text(verbatim: profileName.isEmpty ? "VELTRIX" : profileName)
                    .font(.headline).lineLimit(1).minimumScaleFactor(0.75)
                Spacer(minLength: 4)
                IconButton(icon: "qrcode.viewfinder", label: "Scan QR code") { Feedback.tap(); scanner = true }
                NavigationLink {
                    NotificationScreen()
                } label: {
                    Image(systemName: "bell").font(.body.weight(.medium))
                        .frame(width: 44, height: 44)
                        .background(Color.vxCard, in: Circle())
                        .overlay(alignment: .topTrailing) {
                            if model.hasUnreadNotifications {
                                Circle().fill(Color.vxAccent).frame(width: 7, height: 7).offset(x: -7, y: 7)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Notifications"))
                IconButton(icon: "plus", label: "Add holding") { addAsset = true }
            }
            VeltrixBalanceCard(range: $range, portfolio: portfolio, value: value) { chart = true }
            actions
            homeTabs
            if homeTab == .cards { cardsSection }
            else { positions }
            ForEach(homeSections, id: \.self) { section in
                homeSection(section)
            }
            MarketStatus()
            if !model.hide {
                IconButton(icon: "square.and.arrow.up", label: "Share portfolio") { share = true }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .dismissibleKeyboard()
        .refreshable { await model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)) { _ in
            if !model.hide, !chart, !scanner, trade == nil,
               !ProcessInfo.processInfo.arguments.contains("--ui-testing") { share = true }
        }
        .sheet(isPresented: $addAsset) { SettingsForm(panel: .positions) }
        .confirmationDialog("More", isPresented: $more, titleVisibility: .visible) {
            ForEach([TradeAction.deposit]) { action in
                Button(action.title) { trade = TradeIntent(action: action) }
            }
        }
        .fullScreenCover(item: $trade) { TradeScreen(intent: $0) }
        .fullScreenCover(isPresented: $scanner) { QRScanner() }
        .sheet(isPresented: $share) { PortfolioShare(portfolio: portfolio) }
        .fullScreenCover(isPresented: $chart) {
            NavigationStack {
                PageScroll {
                    VeltrixChart(samples: samples, range: $range, candles: $candles, allowsCandles: true, height: 320, compareAmounts: true) {
                        model.signedMoney($0)
                    }
                }
                .navigationTitle("Portfolio history")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { chart = false } } }
            }
        }
    }

    private var homeTabs: some View {
        HStack(spacing: 6) {
            ForEach(HomeTab.allCases, id: \.self) { item in
                Button {
                    guard homeTab != item else { return }
                    query = ""
                    homeTab = item
                    Feedback.tap()
                } label: {
                    Text(item.title)
                        .font(.subheadline.weight(homeTab == item ? .semibold : .medium))
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .foregroundStyle(homeTab == item ? Color.vxText : Color.vxMuted)
                        .padding(.horizontal, 9)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(homeTab == item ? Color.vxSurface : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(homeTab == item ? .isSelected : [])
                .accessibilityIdentifier("home.section." + item.rawValue)
            }
        }
    }

    private var samples: [ChartSample] {
        portfolio.chart(range: range, candles: candles, performance: true,
                        liveValue: try? portfolio.value(prices: model.usablePrices))
    }

    private var homeSections: [HomeSection] {
        var sections: [HomeSection] = []
        for id in sectionOrder.split(separator: ",") {
            if let section = HomeSection(rawValue: String(id)), !sections.contains(section) { sections.append(section) }
        }
        return sections + HomeSection.allCases.filter { !sections.contains($0) }
    }

    private var homeCustomization: some View {
        Menu {
            ForEach(Array(homeSections.dropFirst()), id: \.self) { section in
                Button {
                    var sections = homeSections.filter { $0 != section }
                    sections.insert(section, at: 0)
                    sectionOrder = sections.map(\.rawValue).joined(separator: ",")
                    Feedback.tap()
                } label: {
                    Label(section.title, systemImage: "arrow.up.to.line")
                }
            }
            Button("Reset section order") { sectionOrder = "" }
        } label: {
            Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44)
        }.accessibilityLabel(Text("Reorder home sections"))
    }

    private var cardsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink { CardsScreen() } label: {
                Label("Card Studio", systemImage: "creditcard").font(.headline)
                    .frame(minHeight: 44)
            }
            if let card = model.primaryCard {
                NavigationLink { CardsScreen(initialCard: card.id) } label: {
                    HStack(spacing: 12) {
                        CardFace(tier: card.tier, design: card.design ?? card.tier.defaultDesign,
                                 name: card.name, balance: model.money(card.balance), frozen: card.frozen,
                                 flip: 0, tilt: .zero, compact: true)
                            .frame(width: 144).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(verbatim: card.name).font(.subheadline.weight(.semibold))
                            Text(verbatim: model.money(card.balance)).font(.caption.monospacedDigit())
                                .foregroundStyle(Color.vxMuted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.vxMuted)
                    }
                }.buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private func homeSection(_ section: HomeSection) -> some View {
        switch section {
        case .statistics:
            if !model.hide { statistics }
        case .allocation:
            if !model.hide, let value, value > 0, !portfolio.positions.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    Text(section.title).font(.headline)
                    ForEach(allocationAssets) { asset in
                        if let holding = positionValue(asset), holding > 0,
                           let weight = try? MoneyMath.divide(holding, value) {
                            HStack {
                                Text(verbatim: asset.ticker).font(.caption.monospacedDigit()).frame(width: 48, alignment: .leading)
                                ProgressView(value: min(1, max(0, NSDecimalNumber(decimal: weight).doubleValue)))
                                Text(verbatim: Display.percent(weight * 100)).font(.caption.monospacedDigit())
                            }
                        }
                    }
                    if let cashShare = try? MoneyMath.divide(portfolio.cash, value), cashShare > 0 {
                        HStack {
                            Text("Cash").font(.caption)
                            ProgressView(value: NSDecimalNumber(decimal: cashShare).doubleValue)
                            Text(verbatim: Display.percent(cashShare * 100)).font(.caption.monospacedDigit())
                        }
                    }
                }
            }
        case .popular:
            marketSection(section.title, assets: Array(Asset.catalog.filter {
                model.quotes[$0.id]?.price != nil && !model.favorites.contains($0.id)
            }.prefix(4)))
        case .recent:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(section.title).font(.headline)
                    Spacer()
                    NavigationLink("All activity") { ActivityScreen() }.font(.subheadline)
                    homeCustomization
                }
                ForEach(Array(portfolio.entries.suffix(3).reversed())) { entry in
                    NavigationLink { EntryScreen(entry: entry) } label: { EntryRow(entry: entry) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private var statistics: some View {
        let now = Date()
        let current = try? portfolio.value(prices: model.usablePrices)
        let overall = portfolio.performance(since: .distantPast, until: now, liveValue: current).change
        let daily = portfolio.performance(since: now.addingTimeInterval(-86_400), until: now, liveValue: current).change
        let best = Asset.catalog.compactMap { asset -> (Asset, Decimal)? in
            guard let position = portfolio.positions[asset.id], position.basis > 0,
                  let holding = positionValue(asset), let ratio = try? MoneyMath.divide(holding - position.basis, position.basis) else { return nil }
            return (asset, ratio * 100)
        }.max { $0.1 < $1.1 }

        return VStack(alignment: .leading, spacing: 12) {
            Text("Portfolio statistics").font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                statistic("Total return", Display.percent(overall?.percent))
                statistic("24h P&L", model.signedMoney(daily?.value))
                statistic("Best performing asset", best.map { "\($0.0.ticker) · \(Display.percent($0.1))" } ?? "—")
                statistic("Assets held", Display.number(Decimal(portfolio.positions.count), maximum: 0))
                statistic("Realized P&L", model.signedMoney(try? portfolio.realized()))
                statistic("Unrealized P&L", model.signedMoney(try? portfolio.unrealized(prices: model.usablePrices)))
            }
        }
        .padding(.vertical, 6)
    }

    private func statistic(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption).foregroundStyle(Color.vxMuted)
            Text(verbatim: value).font(.subheadline.weight(.semibold).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var allocationAssets: [Asset] {
        let values = Asset.catalog.compactMap { asset -> (Asset, Decimal)? in
            guard portfolio.positions[asset.id] != nil, let value = positionValue(asset), value > 0 else { return nil }
            return (asset, value)
        }
        return values.sorted { $0.1 > $1.1 }.prefix(4).map { $0.0 }
    }

    @ViewBuilder private func marketSection(_ title: LocalizedStringKey, assets: [Asset]) -> some View {
        if !assets.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                ForEach(assets) { asset in
                    NavigationLink(value: asset) {
                        HStack {
                            CoinIcon(asset: asset, url: model.quotes[asset.id]?.image, size: 29)
                            Text(verbatim: asset.name).lineLimit(1)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(verbatim: model.money(model.quotes[asset.id]?.price, privateValue: false, price: true))
                                ChangeText(change: model.quotes[asset.id]?.change)
                            }.lineLimit(1)
                        }.font(.subheadline.monospacedDigit())
                            .frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 6) {
            ForEach(model.quickActions) { action in
                Button { trade = TradeIntent(action: action); Feedback.tap() } label: {
                    shortcut(action.title, action.icon)
                }.accessibilityIdentifier("trade." + action.rawValue)
            }
            Button { more = true; Feedback.tap() } label: {
                shortcut("More", "ellipsis")
            }.accessibilityIdentifier("trade.more")
        }.buttonStyle(HomeActionButtonStyle(animate: !reduceMotion && !UITestMode.enabled))
    }

    private func shortcut(_ title: LocalizedStringKey, _ icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 17, weight: .medium))
                .frame(width: 44, height: 44)
                .foregroundStyle(Color.vxText)
                .background(Color.vxSurface, in: Circle())
            Text(title).font(.caption.weight(.medium)).lineLimit(1).minimumScaleFactor(0.65)
        }.frame(maxWidth: .infinity)
    }

    private var positions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.vxMuted)
                TextField("Search assets", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("home.assets.search")
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .accessibilityLabel(Text("Clear search"))
                }
                Menu {
                    Picker("Sort by", selection: $sort) {
                        ForEach(HoldingSort.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    if homeTab == .assets { Toggle("Hide zero balances", isOn: $hideZero) }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease").frame(width: 44, height: 44)
                }
                .accessibilityLabel(Text("Sort holdings"))
            }
            .padding(.leading, 12)
            .background(Color.vxCard, in: RoundedRectangle(cornerRadius: 12))
            if holdings.isEmpty {
                Text(query.isEmpty ? (homeTab == .favorites ? "No favorites yet" : "No positions yet") : "No matching assets")
                    .font(.subheadline).foregroundStyle(Color.vxMuted).padding(.vertical, 8)
            } else {
                ForEach(holdings) { asset in
                    let units = portfolio.positions[asset.id]?.units ?? 0
                        NavigationLink(value: asset) {
                            HStack(spacing: 10) {
                                CoinIcon(asset: asset, url: model.quotes[asset.id]?.image)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(verbatim: asset.name).font(.subheadline.weight(.semibold))
                                    Text(verbatim: model.units(units) + " " + asset.ticker).font(.caption).foregroundStyle(Color.vxMuted)
                                }
                                Spacer(minLength: 4)
                                VStack(alignment: .trailing, spacing: 4) {
                                    CountValue(text: model.money(positionValue(asset))).font(.subheadline.bold())
                                    ChangeText(change: model.quotes[asset.id]?.change)
                                }
                            }.lineLimit(1).minimumScaleFactor(0.7)
                                .frame(minHeight: 56).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        .contextMenu {
                            Button(model.favorites.contains(asset.id) ? "Remove from favorites" : "Add to favorites") {
                                if model.favorites.contains(asset.id) { model.favorites.remove(asset.id) }
                                else { model.favorites.insert(asset.id) }
                            }
                        }
                    Divider().overlay(Color.vxSeparator)
                }
            }
        }
    }

    private func positionValue(_ asset: Asset) -> Decimal? {
        guard let pos = portfolio.positions[asset.id] else { return 0 }
        guard let price = model.prices[asset.id] else { return nil }
        return try? MoneyMath.multiply(price, pos.units)
    }

    private var holdings: [Asset] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return Asset.catalog.filter {
            let included = homeTab == .favorites ? model.favorites.contains($0.id) : (!hideZero || portfolio.positions[$0.id] != nil)
            return included && (term.isEmpty || $0.name.localizedCaseInsensitiveContains(term) || $0.ticker.localizedCaseInsensitiveContains(term))
        }.sorted { left, right in
            let a = sort == .change ? model.quotes[left.id]?.change : positionValue(left)
            let b = sort == .change ? model.quotes[right.id]?.change : positionValue(right)
            if sort != .name, a != b {
                if let a, let b { return a > b }
                return a != nil
            }
            return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }
    }
}

private struct HomeActionButtonStyle: ButtonStyle {
    let animate: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed && animate ? 0.94 : 1)
            .animation(animate ? .easeOut(duration: 0.15) : nil, value: configuration.isPressed)
    }
}

extension Portfolio {
    func chart(range: ChartRange, candles: Bool = false, performance: Bool = false,
               liveValue: Decimal? = nil, now: Date = .now) -> [ChartSample] {
        let cutoff = range.start(from: now) ?? .distantPast
        let visible = performance ? self.performance(since: cutoff, until: now, liveValue: liveValue).points
            : history.filter { $0.date >= cutoff && $0.date <= now }
        let samples: [ChartSample]
        if candles {
            let interval: TimeInterval
            switch range {
            case .hour: interval = 5 * 60
            case .day: interval = 60 * 60
            case .week: interval = 6 * 3_600
            case .month, .quarter: interval = 86_400
            case .year, .all: interval = 7 * 86_400
            }
            let buckets = Dictionary(grouping: visible) { floor($0.date.timeIntervalSince1970 / interval) }
            samples = buckets.keys.sorted().compactMap { key in
                guard let points = buckets[key], let first = points.first, let last = points.last else { return nil }
                let values = points.map(\.value)
                return ChartSample(date: last.date, close: last.value, open: first.value, high: values.max(), low: values.min())
            }
        } else {
            let observationGap: TimeInterval
            switch range {
            case .hour, .day, .week: observationGap = 3 * 3_600
            case .month, .quarter: observationGap = 12 * 3_600
            case .year, .all: observationGap = 24 * 3_600
            }
            var series = 0
            var previous: Date?
            samples = visible.map { point in
                if let previous, point.date.timeIntervalSince(previous) > observationGap { series += 1 }
                previous = point.date
                return ChartSample(date: point.date, close: point.value, series: series)
            }
        }
        guard samples.count > 500 else { return samples }
        return (0..<500).map { offset in
            samples[offset * (samples.count - 1) / 499]
        }
    }
}
