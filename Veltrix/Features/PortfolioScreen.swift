import SwiftUI
import UIKit

struct PortfolioScreen: View {
    @EnvironmentObject private var model: VeltrixModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var range = ChartRange.week
    @State private var candles = false
    @State private var trade: TradeIntent?
    @AppStorage("profileName") private var profileName = ""
    @AppStorage("profileUsername") private var username = ""
    @State private var more = false
    @State private var addAsset = false
    @State private var chart = false
    @State private var share = false

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
                Spacer()
                IconButton(icon: "plus", label: "Add holding") { addAsset = true }
            }
            balanceCard
            HStack {
                Label(portfolio.name, systemImage: "wallet.bifold")
                    .lineLimit(1)
                Spacer()
                Text(verbatim: L.text("Trades") + " · " + String(tradeCount)).monospacedDigit()
            }.font(.caption).foregroundStyle(Color.vxMuted)
            positions
            actions
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
            if !model.hide, !chart, trade == nil { share = true }
        }
        .sheet(isPresented: $addAsset) { SettingsForm(panel: .positions) }
        .confirmationDialog("More", isPresented: $more, titleVisibility: .visible) {
            ForEach([TradeAction.send, .receive, .deposit]) { action in
                Button(action.title) { trade = TradeIntent(action: action) }
            }
        }
        .fullScreenCover(item: $trade) { TradeScreen(intent: $0) }
        .sheet(isPresented: $share) { PortfolioShare(portfolio: portfolio) }
        .fullScreenCover(isPresented: $chart) {
            NavigationStack {
                PageScroll {
                    ChartPanel(samples: samples, range: $range, candles: $candles, allowsCandles: true, height: 320) {
                        model.money($0)
                    }
                }
                .navigationTitle("Portfolio history")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { chart = false } } }
            }
        }
    }

    private var tradeCount: Int {
        portfolio.entries.filter { [.buy, .sell, .swap].contains($0.kind) }.count
    }

    private var samples: [ChartSample] { portfolio.chart(range: range, candles: candles) }

    private var balanceCard: some View {
        VStack(spacing: 6) {
            Text("Portfolio value").font(.caption).foregroundStyle(Color.vxMuted)
            Button {
                withAnimation(reduceMotion ? nil : .spring(response: 0.28)) { model.hide.toggle() }
                Feedback.tap()
            } label: {
                CountValue(text: model.money(value))
                    .font(.system(size: 42, weight: .semibold, design: .rounded))
                    .lineLimit(1).minimumScaleFactor(0.4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(model.hide ? "Show balances" : "Hide balances"))
            HStack(spacing: 6) {
                Text("24h P&L").foregroundStyle(Color.vxMuted)
                Text(verbatim: model.money(daily?.value))
                if !model.hide { ChangeText(change: daily?.percent) }
            }.font(.caption.monospacedDigit())
        }.frame(maxWidth: .infinity).padding(.vertical, 6)
    }

    private var actions: some View {
        HStack(spacing: 6) {
            ForEach([TradeAction.buy, .sell, .swap]) { action in
                Button { trade = TradeIntent(action: action); Feedback.tap() } label: {
                    shortcut(action.title, action.icon)
                }.accessibilityIdentifier("trade." + action.rawValue)
            }
            Button { more = true; Feedback.tap() } label: { shortcut("More", "ellipsis") }
                .accessibilityIdentifier("trade.more")
        }.buttonStyle(.plain)
    }

    private func shortcut(_ title: LocalizedStringKey, _ icon: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 17, weight: .medium))
            Text(title).font(.caption.weight(.medium))
        }.frame(maxWidth: .infinity, minHeight: 55)
            .background(Color.vxSurface, in: RoundedRectangle(cornerRadius: 14))
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
            }
            if holdings.isEmpty {
                EmptyPanel(icon: "square.stack.3d.up", title: "No positions yet", detail: "Simulate a buy or add holdings in Settings.")
            } else {
                ForEach(holdings) { asset in
                    if let pos = portfolio.positions[asset.id] {
                        NavigationLink(value: asset) {
                            HStack(spacing: 10) {
                                CoinIcon(asset: asset, url: model.quotes[asset.id]?.image)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(verbatim: asset.name).font(.subheadline.weight(.semibold))
                                    Text(verbatim: model.units(pos.units) + " " + asset.ticker).font(.caption).foregroundStyle(Color.vxMuted)
                                }
                                Spacer(minLength: 4)
                                VStack(alignment: .trailing, spacing: 4) {
                                    CountValue(text: model.money(positionValue(asset))).font(.subheadline.bold())
                                    ChangeText(change: model.quotes[asset.id]?.change)
                                }
                            }.lineLimit(1).minimumScaleFactor(0.7).padding(.horizontal, 12)
                                .frame(height: 64).background(Color.vxCard, in: RoundedRectangle(cornerRadius: 15))
                        }.buttonStyle(.plain)
                    }
                }
                LabeledContent("Realized P&L", value: model.money(try? portfolio.realized()))
                LabeledContent("Unrealized P&L", value: model.money(try? portfolio.unrealized(prices: model.prices)))
            }
        }
    }

    private func positionValue(_ asset: Asset) -> Decimal? {
        guard let price = model.prices[asset.id], let pos = portfolio.positions[asset.id] else { return nil }
        return try? MoneyMath.multiply(price, pos.units)
    }

    private var holdings: [Asset] {
        Asset.catalog.filter { portfolio.positions[$0.id] != nil }.sorted {
            let a = positionValue($0) ?? -1
            let b = positionValue($1) ?? -1
            return a == b ? $0.ticker < $1.ticker : a > b
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
