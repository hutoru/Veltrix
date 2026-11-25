import SwiftUI
import UIKit

struct PortfolioScreen: View {
    @EnvironmentObject private var model: VeltrixModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var range = ChartRange.week
    @State private var candles = false
    @State private var trade: TradeIntent?
    @State private var chart = false
    @State private var share = false

    private var portfolio: Portfolio { model.portfolio }
    private var value: Decimal? { try? portfolio.value(prices: model.prices) }
    private var daily: (value: Decimal, percent: Decimal?)? { try? portfolio.daily(now: Date(), prices: model.prices) }

    var body: some View {
        PageScroll {
            HStack(spacing: 10) {
                VeltrixMark().fill(Color.vxHighlight).frame(width: 24, height: 24)
                Text(verbatim: "VELTRIX").font(.system(size: 17, weight: .heavy, design: .rounded)).tracking(3)
                Spacer()
                Menu {
                    ForEach(model.ledger.portfolios) { item in
                        Button {
                            _ = model.execute(.selectPortfolio(item.id))
                        } label: {
                            if model.ledger.selected == item.id {
                                Label(item.name, systemImage: "checkmark")
                            } else {
                                Text(verbatim: item.name)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(verbatim: portfolio.name).lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .bold))
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 11).padding(.vertical, 10)
                    .background(Color.vxSurface, in: Capsule())
                }
                .accessibilityLabel(Text("Switch portfolio"))
            }
            balanceCard
            MarketStatus()
            actions
            if !model.hide {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Portfolio history").font(.title3.weight(.semibold))
                        Spacer()
                        IconButton(icon: "arrow.up.left.and.arrow.down.right", label: "Full screen chart") { chart = true }
                        IconButton(icon: "square.and.arrow.up", label: "Share simulation") { share = true }
                    }
                    ChartPanel(samples: samples, range: $range, candles: $candles, allowsCandles: false) {
                        model.money($0)
                    }
                }
                .panel()
            }
            positions
        }
        .refreshable { await model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)) { _ in
            if !model.hide, !chart, trade == nil { share = true }
        }
        .sheet(item: $trade) { TradeScreen(intent: $0) }
        .sheet(isPresented: $share) { PortfolioShare(portfolio: portfolio) }
        .fullScreenCover(isPresented: $chart) {
            NavigationStack {
                PageScroll {
                    SimBadge()
                    ChartPanel(samples: samples, range: $range, candles: $candles, allowsCandles: false, height: 320) {
                        model.money($0)
                    }
                }
                .navigationTitle("Portfolio history")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { chart = false } } }
            }
        }
    }

    private var samples: [ChartSample] { portfolio.chart(range: range) }

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                SimBadge(inverted: true)
                Spacer()
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3)) { model.hide.toggle() }
                    Feedback.tap()
                } label: {
                    Image(systemName: model.hide ? "eye.slash" : "eye")
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(model.hide ? "Show balances" : "Hide balances"))
            }
            Text("Portfolio value").font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.73))
            if model.loading && value == nil && !model.hide {
                Skeleton().frame(width: 160, height: 39)
            } else {
                CountValue(text: model.money(value))
                    .font(.system(size: 42, weight: .medium, design: .rounded))
                    .lineLimit(1).minimumScaleFactor(0.35)
                    .accessibilityIdentifier("portfolio.value")
            }
            Divider().overlay(.white.opacity(0.10))
            HStack(alignment: .top) {
                balanceMetric("Available cash", model.money(try? portfolio.freeCash()))
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("24h P&L").font(.caption).foregroundStyle(.white.opacity(0.73))
                    Text(verbatim: model.money(daily?.value)).font(.subheadline.weight(.semibold).monospacedDigit())
                        .lineLimit(1).minimumScaleFactor(0.55)
                    if !model.hide { ChangeText(change: daily?.percent).environment(\.colorScheme, .dark) }
                }
            }
        }
        .padding(18)
        .foregroundStyle(.white)
        .background {
            RoundedRectangle(cornerRadius: 24)
                .fill(LinearGradient(colors: [Color(red: 0.14, green: 0.08, blue: 0.28), Color(red: 0.25, green: 0.13, blue: 0.48),
                                             Color(red: 0.09, green: 0.06, blue: 0.17)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay { OrbitLines().clipShape(RoundedRectangle(cornerRadius: 24)) }
        }
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.11)))
    }

    private func balanceMetric(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.white.opacity(0.73))
            Text(verbatim: value).font(.subheadline.weight(.semibold).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.55)
        }
    }

    private var actions: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(TradeAction.allCases) { action in
                Button { trade = TradeIntent(action: action); Feedback.tap() } label: {
                    HStack(spacing: 7) {
                        Image(systemName: action.icon).font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.vxHighlight)
                        Text(action.title).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, minHeight: 45)
                    .background(Color.vxCard, in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("trade." + action.rawValue)
            }
        }
    }

    private var positions: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Holdings").font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
            if portfolio.positions.isEmpty {
                EmptyPanel(icon: "square.stack.3d.up", title: "No positions yet",
                           detail: "Simulate a buy or add holdings in Settings.")
            } else {
                if !model.hide {
                    HStack {
                        stat("Realized P&L", try? portfolio.realized())
                        Spacer()
                        stat("Unrealized P&L", try? portfolio.unrealized(prices: model.prices))
                    }
                    .panel()
                }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Asset.catalog.filter { portfolio.positions[$0.id] != nil }) { asset in
                        if let position = portfolio.positions[asset.id] {
                            NavigationLink(value: asset) { holding(asset, position) }.buttonStyle(.plain)
                            if asset.id != Asset.catalog.last(where: { portfolio.positions[$0.id] != nil })?.id {
                                Divider()
                            }
                        }
                    }
                }
                .panel(padding: 13)
            }
        }
    }

    private func stat(_ title: LocalizedStringKey, _ value: Decimal?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(Color.vxMuted)
            Text(verbatim: model.money(value)).font(.subheadline.weight(.semibold))
                .foregroundStyle(value.map { $0 >= 0 ? Color.vxUp : .vxDown } ?? .vxMuted)
                .lineLimit(1).minimumScaleFactor(0.55)
        }
    }

    private func holding(_ asset: Asset, _ position: Position) -> some View {
        let quote = model.quotes[asset.id]
        let positionValue = quote?.price.flatMap { try? MoneyMath.multiply($0, position.units) }
        let percentage = allocation(positionValue)
        return HStack(spacing: 10) {
            CoinIcon(asset: asset, url: quote?.image)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: asset.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text("Avg. \(model.money(position.average, price: true))")
                    .font(.caption2).foregroundStyle(Color.vxMuted).lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 4) {
                Text(verbatim: model.money(positionValue)).font(.subheadline.weight(.semibold).monospacedDigit())
                Text(verbatim: "\(model.units(position.units)) \(asset.ticker)")
                    .font(.caption2).foregroundStyle(Color.vxMuted)
            }
            .lineLimit(1).minimumScaleFactor(0.55)
            if let percentage, !model.hide {
                VStack(alignment: .trailing, spacing: 5) {
                    Text(verbatim: Display.number(percentage, maximum: 1) + "%")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(Color.vxHighlight)
                    ProgressView(value: min(100, max(0, NSDecimalNumber(decimal: percentage).doubleValue)), total: 100)
                        .tint(.vxAccent).frame(width: 34)
                }
                .accessibilityLabel(Text("Portfolio allocation"))
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func allocation(_ position: Decimal?) -> Decimal? {
        guard let position, let value, value > 0 else { return nil }
        return try? MoneyMath.multiply(MoneyMath.divide(position, value), 100)
    }
}

extension Portfolio {
    func chart(range: ChartRange) -> [ChartSample] {
        let cutoff = range.start(from: Date()) ?? .distantPast
        let visible = history.filter { $0.date >= cutoff }
        guard visible.count > 500 else { return visible.map { ChartSample(date: $0.date, close: $0.value) } }
        return (0..<500).map { offset in
            let point = visible[offset * (visible.count - 1) / 499]
            return ChartSample(date: point.date, close: point.value)
        }
    }
}
