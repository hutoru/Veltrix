import SwiftUI
import UIKit

struct PortfolioScreen: View {
    @Environment(\.veltrixTheme) private var theme
    private enum HomeTab: String, CaseIterable {
        case assets, favorites

        var title: LocalizedStringKey {
            switch self {
            case .assets: return "Assets"
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

    @EnvironmentObject private var model: VeltrixModel
    @State private var homeTab = HomeTab.assets
    @State private var trade: TradeIntent?
    @AppStorage("holdingSort") private var sort = HoldingSort.value
    @AppStorage("hideZeroHoldings") private var hideZero = true
    @State private var addAsset = false
    @State private var share = false
    @State private var scanner = false

    private var portfolio: Portfolio { model.portfolio }
    private var value: Decimal? { try? portfolio.value(prices: model.prices) }

    var body: some View {
        PageScroll(spacing: 12) {
            HStack(spacing: 8) {
                NavigationLink {
                    ProfileScreen()
                } label: {
                    ProfileAvatar(size: 34)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Profile"))
                .accessibilityIdentifier("home.profile")
                Text(verbatim: "VELTRIX")
                    .font(.title3.weight(.medium))
                    .tracking(2)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 4)
                IconButton(icon: "qrcode.viewfinder", label: "Scan QR code") { Feedback.tap(); scanner = true }
                NavigationLink {
                    NotificationScreen()
                } label: {
                    Image(systemName: "bell").font(.system(size: 17, weight: .regular))
                        .frame(width: 44, height: 44)
                        .background(theme.surface, in: Circle())
                        .overlay(alignment: .topTrailing) {
                            if model.hasUnreadNotifications {
                                Circle().fill(theme.accent).frame(width: 7, height: 7).offset(x: -7, y: 7)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Notifications"))
            }
            PortfolioBalanceHeader(portfolio: portfolio, value: value)
            actions
            NavigationLink {
                AvailableCashScreen()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: UIImage(systemName: "wallet.pass") == nil ? "creditcard" : "wallet.pass")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(theme.muted)
                        .accessibilityHidden(true)
                    Text("Available").font(.subheadline)
                    Spacer(minLength: 8)
                    CountValue(text: model.money(try? portfolio.freeCash(), fixedDigits: 2))
                        .font(.body.weight(.medium))
                        .lineLimit(1).minimumScaleFactor(0.55)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 54)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 21))
            }
            .buttonStyle(HomeActionButtonStyle())
            .simultaneousGesture(TapGesture().onEnded { Feedback.tap() })
            HStack(spacing: 6) {
                homeTabs
                sortMenu
                IconButton(icon: "plus", label: "Add holding") { Feedback.tap(); addAsset = true }
            }
            positions
            NavigationLink {
                PageScroll { MarketStatus() }
                    .navigationTitle("Market data").navigationBarTitleDisplayMode(.inline)
            } label: {
                HStack(spacing: 5) {
                    MarketStatus(compact: true)
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(theme.muted)
                }
            }.buttonStyle(.plain)
            if !model.hide {
                IconButton(icon: "square.and.arrow.up", label: "Share portfolio") { share = true }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .dismissibleKeyboard()
        .refreshable { await model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)) { _ in
            if !model.hide, !scanner, trade == nil,
               !ProcessInfo.processInfo.arguments.contains("--ui-testing") { share = true }
        }
        .sheet(isPresented: $addAsset) { SettingsForm(panel: .positions) }
        .fullScreenCover(item: $trade) { TradeScreen(intent: $0) }
        .fullScreenCover(isPresented: $scanner) { QRScanner() }
        .sheet(isPresented: $share) { PortfolioShare(portfolio: portfolio) }
    }

    private var homeTabs: some View {
        HStack(spacing: 6) {
            ForEach(HomeTab.allCases, id: \.self) { item in
                Button {
                    guard homeTab != item else { return }
                    homeTab = item
                    Feedback.tap()
                } label: {
                    Text(item.title)
                        .font(.subheadline.weight(homeTab == item ? .semibold : .medium))
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .foregroundStyle(homeTab == item ? theme.text : theme.muted)
                        .padding(.horizontal, 9)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(homeTab == item ? theme.elevated : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(homeTab == item ? .isSelected : [])
                .accessibilityIdentifier("home.section." + item.rawValue)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            shortcut(.send, icon: "paperplane")
            shortcut(.deposit, icon: "plus")
        }
        .buttonStyle(HomeActionButtonStyle())
    }

    private func shortcut(_ action: TradeAction, icon: String) -> some View {
        Button {
            Feedback.tap()
            trade = TradeIntent(action: action)
        } label: {
            Label {
                Text(action.title).font(.subheadline.weight(.medium))
            } icon: {
                Image(systemName: icon).font(.system(size: 17, weight: .medium))
            }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(theme.surface, in: Capsule())
        }
        .accessibilityIdentifier("trade." + action.rawValue)
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort by", selection: $sort) {
                ForEach(HoldingSort.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            if homeTab == .assets { Toggle("Hide zero balances", isOn: $hideZero) }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(theme.text)
                .frame(width: 44, height: 44)
                .background(theme.surface, in: Circle())
        }
        .accessibilityLabel(Text("Sort holdings"))
    }

    private var positions: some View {
        LazyVStack(alignment: .leading, spacing: 7) {
            if holdings.isEmpty {
                Text(homeTab == .favorites ? "No favorites yet" : "No positions yet")
                    .font(.subheadline).foregroundStyle(theme.muted).padding(.vertical, 8)
            } else {
                ForEach(holdings) { asset in
                    holdingRow(asset)
                }
            }
        }
    }

    private func holdingRow(_ asset: Asset) -> some View {
        let position = portfolio.positions[asset.id]
        let units = position?.units ?? 0
        let value = positionValue(asset)
        let profit = position.flatMap { position in
            value.flatMap { try? MoneyMath.subtractValuation($0, position.basis) }
        }
        let profitText = model.signedMoney(profit, fixedDigits: 2)
        let profitColor: Color
        switch profit {
        case let amount? where amount > 0: profitColor = theme.positive
        case let amount? where amount < 0: profitColor = theme.negative
        default: profitColor = theme.muted
        }
        let isFavorite = model.favorites.contains(asset.id)

        return NavigationLink(value: asset) {
            HStack(spacing: 10) {
                CoinIcon(asset: asset, url: model.quotes[asset.id]?.image, size: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: asset.name).font(.body.weight(.medium))
                    Text(verbatim: model.units(units) + " " + asset.ticker)
                        .font(.caption).foregroundStyle(theme.muted)
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 4) {
                    CountValue(text: model.money(value, fixedDigits: 2)).font(.subheadline.weight(.medium))
                    if !model.hide, units > 0 {
                        CountValue(text: profitText)
                            .font(.caption)
                            .foregroundStyle(profitColor)
                            .accessibilityLabel(Text("Unrealized P&L"))
                            .accessibilityValue(Text(verbatim: profitText))
                    }
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: 60)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 22))
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .contextMenu {
            ForEach([TradeAction.buy, .sell, .swap]) { action in
                Button {
                    trade = TradeIntent(action: action, asset: asset.id)
                } label: {
                    Label(action.title, systemImage: action.icon)
                }
            }
            Button(isFavorite ? "Remove from favorites" : "Add to favorites") {
                if isFavorite { model.favorites.remove(asset.id) }
                else { model.favorites.insert(asset.id) }
                Feedback.tap()
            }
        }
    }

    private func positionValue(_ asset: Asset) -> Decimal? {
        guard let pos = portfolio.positions[asset.id] else { return 0 }
        guard let price = model.prices[asset.id] else { return nil }
        return try? MoneyMath.multiply(price, pos.units)
    }

    private var holdings: [Asset] {
        Asset.catalog.filter {
            let held = (portfolio.positions[$0.id]?.units ?? 0) > 0
            let listed = !$0.isTokenizedStock || model.quotes[$0.id]?.price != nil || held
            return homeTab == .favorites ? model.favorites.contains($0.id) : (held || (!hideZero && listed))
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

private struct AvailableCashScreen: View {
    @EnvironmentObject private var model: VeltrixModel
    @State private var deposit: TradeIntent?

    var body: some View {
        let portfolio = model.portfolio
        let available = try? portfolio.freeCash()
        PageScroll {
            CountValue(text: model.money(available, fixedDigits: 2))
                .font(.largeTitle.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.45)
            LabeledContent("Cash balance", value: model.money(portfolio.cash, fixedDigits: 2))
            LabeledContent("Reserved", value: model.money(available.flatMap {
                try? MoneyMath.subtract(portfolio.cash, $0)
            }, fixedDigits: 2))
            Button("Deposit") { deposit = TradeIntent(action: .deposit) }
                .buttonStyle(PrimaryButtonStyle())
        }
        .navigationTitle("Available cash")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $deposit) { TradeScreen(intent: $0) }
    }
}

private struct HomeActionButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let animate = !reduceMotion && !UITestMode.enabled
        return configuration.label
            .opacity(configuration.isPressed ? 0.83 : 1)
            .scaleEffect(configuration.isPressed && animate ? 0.975 : 1)
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
