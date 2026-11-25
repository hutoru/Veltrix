import SwiftUI
import UIKit

struct PortfolioScreen: View {
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var range = ChartRange.week
    @State private var candles = false
    @State private var trade: TradeIntent?
    @AppStorage("profileName") private var profileName = ""
    @AppStorage("profileUsername") private var username = ""
    @AppStorage("holdingSort") private var sort = HoldingSort.value
    @AppStorage("favoriteHoldings") private var favoriteHoldings = false
    @AppStorage("hideZeroHoldings") private var hideZero = true
    @State private var more = false
    @State private var addAsset = false
    @State private var chart = false
    @State private var share = false
    @State private var scanner = false

    private var portfolio: Portfolio { model.portfolio }
    private var value: Decimal? { try? portfolio.value(prices: model.prices) }
    private var daily: (value: Decimal, percent: Decimal?)? { try? portfolio.daily(now: Date(), prices: model.prices) }

    var body: some View {
        PageScroll {
            HStack {
                Menu {
                    ForEach(model.ledger.portfolios) { item in
                        Button { _ = model.execute(.selectPortfolio(item.id)) } label: {
                            if item.id == portfolio.id { Label(item.name, systemImage: "checkmark") }
                            else { Text(verbatim: item.name) }
                        }
                    }
                } label: {
                    HStack(spacing: 9) {
                        ProfileAvatar(size: 36)
                        VStack(alignment: .leading) {
                            Text(verbatim: profileName.isEmpty ? L.text("My profile") : profileName).font(.subheadline.bold())
                            Text(verbatim: username.isEmpty ? portfolio.name : "@" + username)
                                .font(.caption2).foregroundStyle(Color.vxMuted).lineLimit(1)
                        }
                    }
                }
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
            balanceCard
            actions
            positions
            Divider().overlay(Color.vxSeparator)
            HStack {
                NavigationLink { CardsScreen() } label: { Label("Cards", systemImage: "creditcard") }
                Spacer()
                Button { more = true } label: { Label("More", systemImage: "ellipsis") }
                    .accessibilityIdentifier("trade.more")
            }.font(.subheadline.weight(.medium))
            MarketStatus()
            if !model.hide {
                HStack {
                    Button { chart = true } label: { Label("Portfolio history", systemImage: "chart.xyaxis.line") }
                    Spacer()
                    IconButton(icon: "square.and.arrow.up", label: "Share portfolio") { share = true }
                }
            }
        }
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
                    VeltrixChart(samples: samples, range: $range, candles: $candles, allowsCandles: true, height: 320) {
                        model.money($0)
                    }
                }
                .navigationTitle("Portfolio history")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { chart = false } } }
            }
        }
    }

    private var samples: [ChartSample] { portfolio.chart(range: range, candles: candles) }

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text("Portfolio value").font(.subheadline).foregroundStyle(Color.vxMuted)
                Button {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) { model.hide.toggle() }
                    Feedback.tap()
                } label: {
                    Image(systemName: model.hide ? "eye.slash" : "eye")
                        .font(.footnote).foregroundStyle(Color.vxMuted).frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(model.hide ? "Show balances" : "Hide balances"))
            }
            CountValue(text: model.money(value))
                .font(.system(size: 48, weight: .semibold))
                .tracking(-2).lineLimit(1).minimumScaleFactor(0.4)
            HStack(spacing: 6) {
                Text("24h P&L").foregroundStyle(Color.vxMuted)
                Text(verbatim: model.signedMoney(daily?.value))
                if !model.hide { ChangeText(change: daily?.percent) }
            }.font(.caption.monospacedDigit())
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
    }

    private var actions: some View {
        HStack(spacing: 6) {
            ForEach(model.quickActions) { action in
                Button { trade = TradeIntent(action: action); Feedback.tap() } label: {
                    shortcut(action.title, action.icon)
                }.accessibilityIdentifier("trade." + action.rawValue)
            }
        }.buttonStyle(.plain)
    }

    private func shortcut(_ title: LocalizedStringKey, _ icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 17, weight: .medium))
                .frame(width: 44, height: 44)
                .background(Color.vxCard, in: Circle())
            Text(title).font(.caption.weight(.medium)).lineLimit(1).minimumScaleFactor(0.65)
        }.frame(maxWidth: .infinity)
    }

    private var positions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Holdings").font(.title3.bold())
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("Available cash").font(.caption2).foregroundStyle(Color.vxMuted)
                    Text(verbatim: model.money(try? portfolio.freeCash())).font(.caption.monospacedDigit())
                }
                Menu {
                    Picker("Sort by", selection: $sort) {
                        ForEach(HoldingSort.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Toggle("Favorites", isOn: $favoriteHoldings)
                    Toggle("Hide zero balances", isOn: $hideZero)
                } label: {
                    Image(systemName: "line.3.horizontal.decrease").frame(width: 44, height: 44)
                }
                .accessibilityLabel(Text("Sort holdings"))
            }
            if holdings.isEmpty {
                EmptyPanel(icon: "square.stack.3d.up", title: "No positions yet", detail: "Add a holding to track it here.")
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
                LabeledContent("Realized P&L", value: model.money(try? portfolio.realized()))
                LabeledContent("Unrealized P&L", value: model.money(try? portfolio.unrealized(prices: model.prices)))
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
            (!hideZero || portfolio.positions[$0.id] != nil) && (!favoriteHoldings || model.favorites.contains($0.id))
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

extension Portfolio {
    func chart(range: ChartRange, candles: Bool = false) -> [ChartSample] {
        let cutoff = range.start(from: Date()) ?? .distantPast
        let visible = history.filter { $0.date >= cutoff }
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
            samples = visible.map { ChartSample(date: $0.date, close: $0.value) }
        }
        guard samples.count > 500 else { return samples }
        return (0..<500).map { offset in
            samples[offset * (samples.count - 1) / 499]
        }
    }
}
