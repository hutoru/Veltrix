import Foundation
import WidgetKit

@MainActor enum WidgetPublisher {
    private static var last: WidgetData?

    static func publish(_ model: VeltrixModel, force: Bool = false) {
        guard !UITestMode.enabled, let file = WidgetData.location else { return }
        guard !model.onSet else {
            if FileManager.default.fileExists(atPath: file.path) {
                try? FileManager.default.removeItem(at: file)
                last = nil
                WidgetCenter.shared.reloadAllTimelines()
            }
            return
        }
        let hide = model.hide || model.widgetPrivacy
        let portfolio = model.portfolio
        let observed = try? portfolio.value(prices: model.prices)
        let performance = portfolio.performance(since: Date().addingTimeInterval(-7 * 86_400), liveValue: observed,
                                                 includesPoints: false)
        let ranked = Asset.catalog.compactMap { asset -> (asset: Asset, value: Decimal)? in
            guard let position = portfolio.positions[asset.id], let quote = model.prices[asset.id],
                  let value = try? MoneyMath.multiply(position.units, quote) else { return nil }
            return (asset, value)
        }.sorted { $0.value == $1.value ? $0.asset.id < $1.asset.id : $0.value > $1.value }
        let favorites = Asset.catalog.filter { model.favorites.contains($0.id) }.prefix(6)
        let stakes = portfolio.stakes ?? []
        let samples = portfolio.chart(range: .week, performance: true, liveValue: observed).suffix(96)
        var segments = [[Double]]()
        var lastSeries: Int?
        for sample in samples {
            if segments.isEmpty || lastSeries != sample.series { segments.append([]) }
            segments[segments.count - 1].append(NSDecimalNumber(decimal: sample.close).doubleValue)
            lastSeries = sample.series
        }
        let data = WidgetData(appearance: model.theme.rawValue, balance: hide ? "••••••" : model.money(observed),
                              change: hide ? "••••" : Display.percent(performance.change?.percent),
                              assets: ranked.prefix(5).map { .init(ticker: $0.asset.ticker, detail: hide ? "••••" : model.money($0.value)) },
                              favorites: favorites.map { .init(ticker: $0.ticker, detail: hide ? "••••" : model.money(model.prices[$0.id], price: true)) },
                              earn: stakes.prefix(5).map { .init(ticker: Asset.ticker($0.asset), detail: hide ? "••••" : model.units($0.units)) },
                              graph: hide ? [] : segments, updated: .now)
        if !force, let last, data.updated.timeIntervalSince(last.updated) < 60 { return }
        guard let bytes = try? JSONEncoder().encode(data), (try? bytes.write(to: file, options: .atomic)) != nil else { return }
        last = data
        WidgetCenter.shared.reloadAllTimelines()
    }
}
