import SwiftUI

struct PortfolioAnalyticsScreen: View {
    private struct Allocation: Identifiable {
        let asset: Asset
        let weight: Decimal
        var id: String { asset.id }
    }

    @EnvironmentObject private var model: VeltrixModel
    @State private var range = ChartRange.week
    @State private var candles = false

    private var portfolio: Portfolio { model.portfolio }
    private var trades: [Entry] { portfolio.entries.filter { [.buy, .sell, .swap].contains($0.kind) } }
    private var realizedTrades: [Entry] { trades.filter { $0.profit != nil } }
    private var samples: [ChartSample] {
        portfolio.chart(range: range, candles: candles, performance: true,
                        liveValue: try? portfolio.value(prices: model.usablePrices))
    }

    var body: some View {
        PageScroll {
            CountValue(text: model.money(try? portfolio.value(prices: model.prices)))
                .font(.system(size: 42, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.4)
            HStack(spacing: 12) {
                metric("Available cash", value: model.money(try? portfolio.freeCash()))
                metric("Unrealized P&L", value: model.signedMoney(try? portfolio.unrealized(prices: model.prices)))
            }
            Divider().overlay(Color.vxSeparator)
            if !model.hide {
                VeltrixChart(samples: samples, range: $range, candles: $candles, allowsCandles: true,
                           compareAmounts: true, ranges: [.day, .week, .month, .all]) { model.signedMoney($0) }
                LabeledContent("Realized P&L", value: model.signedMoney(periodProfit))
                allocation
            }
            Text("Open positions").font(.headline)
            if portfolio.positions.isEmpty {
                Text("No positions yet").font(.subheadline).foregroundStyle(Color.vxMuted)
            }
            ForEach(Asset.catalog.filter { portfolio.positions[$0.id] != nil }) { coin in
                NavigationLink(value: coin) {
                    HStack {
                        CoinIcon(asset: coin, url: model.quotes[coin.id]?.image, size: 30)
                        Text(verbatim: coin.name)
                        Spacer()
                        if let position = portfolio.positions[coin.id] { Text(verbatim: model.units(position.units)) }
                    }.frame(minHeight: 48).contentShape(Rectangle())
                }.buttonStyle(.plain)
                Divider().overlay(Color.vxSeparator)
            }
            let closed = Asset.catalog.filter { coin in
                portfolio.positions[coin.id] == nil && realizedTrades.contains { $0.asset == coin.id }
            }
            if !closed.isEmpty {
                Text("Closed positions").font(.headline)
                ForEach(closed) { coin in
                    let profit = try? realizedTrades.filter { $0.asset == coin.id }.compactMap(\.profit).reduce(0, MoneyMath.addValuation)
                    NavigationLink(value: coin) {
                        HStack {
                            CoinIcon(asset: coin, url: model.quotes[coin.id]?.image, size: 30)
                            Text(verbatim: coin.name)
                            Spacer()
                            Text(verbatim: model.money(profit)).monospacedDigit()
                        }.frame(minHeight: 48).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    Divider().overlay(Color.vxSeparator)
                }
            }
            if !realizedTrades.isEmpty {
                Text("Realized trades").font(.headline)
                ForEach(realizedTrades.reversed()) { entry in
                    NavigationLink { EntryScreen(entry: entry) } label: { EntryRow(entry: entry) }
                        .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Analytics")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func metric(_ label: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(Color.vxMuted)
            CountValue(text: value).font(.headline).lineLimit(1).minimumScaleFactor(0.5)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var allocation: some View {
        if let total = try? portfolio.value(prices: model.prices), total > 0 {
            let weights = Asset.catalog.compactMap { asset -> Allocation? in
                guard let position = portfolio.positions[asset.id], let price = model.prices[asset.id],
                      let weight = try? MoneyMath.divide(MoneyMath.multiply(price, position.units), total) else { return nil }
                return Allocation(asset: asset, weight: weight)
            }.sorted { $0.weight > $1.weight }
            if !weights.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Portfolio allocation").font(.headline)
                    ForEach(Array(weights.prefix(5))) { allocation in
                        let asset = allocation.asset
                        let weight = allocation.weight
                        HStack(spacing: 12) {
                            CoinIcon(asset: asset, url: model.quotes[asset.id]?.image, size: 24)
                            Text(verbatim: asset.ticker).font(.caption.weight(.semibold)).frame(width: 46, alignment: .leading)
                            ProgressView(value: min(1, max(0, NSDecimalNumber(decimal: weight).doubleValue)))
                            Text(verbatim: Display.number(weight * 100, maximum: 1) + "%").font(.caption.monospacedDigit())
                                .frame(minWidth: 55, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    private var periodProfit: Decimal? {
        let start = range.start(from: .now) ?? .distantPast
        return try? realizedTrades.filter { $0.date >= start }.compactMap(\.profit).reduce(0, MoneyMath.addValuation)
    }
}
