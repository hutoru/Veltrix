import Foundation

protocol MarketDataProvider: Sendable {
    func quotes() async throws -> [Quote]
    func history(asset: Asset, range: ChartRange, candles: Bool) async throws -> MarketHistory
    func currencies() async throws -> [FXRate]
}

struct MarketHistory: Codable, Sendable {
    var samples: [ChartSample]
    var source: String
    var capped: Bool = false
}

struct PublicMarketProvider: MarketDataProvider {
    let http: HTTPClient
    var demoKey: String?

    private static let base = URL(string: "https://api.coingecko.com/api/v3/")!
    private static let frankfurter = URL(string: "https://api.frankfurter.dev/v2/rates")!
    private static let kraken = URL(string: "https://api.kraken.com/0/public/OHLC")!

    private var headers: [String: String] {
        demoKey.map { ["x-cg-demo-api-key": $0] } ?? [:]
    }

    func quotes() async throws -> [Quote] {
        let url = Self.query(Self.base.appendingPathComponent("coins/markets"), [
            "vs_currency": "usd", "ids": Asset.catalog.map(\.id).joined(separator: ","), "precision": "full", "sparkline": "true"
        ])
        let data = try await http.get(url, headers: headers)
        let quotes = try JSONDecoder().decode([GeckoQuote].self, from: data).map(\.quote)
        guard !quotes.isEmpty else { throw MarketError.unavailable }
        return quotes
    }

    func history(asset: Asset, range: ChartRange, candles: Bool) async throws -> MarketHistory {
        guard Asset.ids.contains(asset.id) else { throw MarketError.unavailable }
        if range == .all || (range == .hour && candles) {
            do {
                let samples = try await krakenHistory(asset: asset, interval: range == .all ? 21_600 : 1)
                let window = Self.window(samples, range: range)
                if window.count >= 2 { return MarketHistory(samples: window, source: "Kraken") }
            } catch is CancellationError { throw CancellationError() }
            catch { try Task.checkCancellation() }
        }

        let days = range.days ?? 365
        let coin = Self.base.appendingPathComponent("coins").appendingPathComponent(asset.id)
        let url = Self.query(coin.appendingPathComponent(candles ? "ohlc" : "market_chart"),
                             ["vs_currency": "usd", "days": String(days)])
        let data = try await http.get(url, headers: headers)
        let decoder = JSONDecoder()
        let rows = candles ? try decoder.decode([[Decimal]].self, from: data)
            : try decoder.decode(PriceHistory.self, from: data).prices
        let samples = rows.compactMap { row -> ChartSample? in
            guard row.count >= (candles ? 5 : 2) else { return nil }
            let date = Date(timeIntervalSince1970: NSDecimalNumber(decimal: row[0]).doubleValue / 1_000)
            if candles { return Self.candle(date, row[1], row[2], row[3], row[4]) }
            guard row[1] > 0 else { return nil }
            return ChartSample(date: date, close: row[1])
        }
        let window = Self.window(samples, range: range)
        guard !window.isEmpty else { throw MarketError.unavailable }
        return MarketHistory(samples: window, source: "CoinGecko", capped: range == .all)
    }

    func currencies() async throws -> [FXRate] {
        let data = try await http.get(Self.query(Self.frankfurter, ["base": "USD"]))
        let supported = Set(Fiat.currencies)
        let rates = try JSONDecoder().decode([FXRate].self, from: data).filter {
            supported.contains($0.quote) && $0.rate > 0
        }
        guard !rates.isEmpty else { throw MarketError.unavailable }
        return rates
    }

    private func krakenHistory(asset: Asset, interval: Int) async throws -> [ChartSample] {
        guard let pair = KrakenSymbols.pairs[asset.ticker] else { throw MarketError.unavailable }
        let data = try await http.get(Self.query(Self.kraken, ["pair": pair, "interval": String(interval)]))
        guard let body = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let errors = body["error"] as? [String], errors.isEmpty,
              let result = body["result"] as? [String: Any],
              let rows = result.first(where: { $0.key != "last" })?.value as? [[Any]]
        else { throw MarketError.unavailable }
        return rows.compactMap { row in
            guard row.count >= 5, let time = row[0] as? NSNumber,
                  let a = row[1] as? String, let b = row[2] as? String, let c = row[3] as? String, let d = row[4] as? String,
                  let open = MoneyMath.parse(a, separator: "."), let high = MoneyMath.parse(b, separator: "."),
                  let low = MoneyMath.parse(c, separator: "."), let close = MoneyMath.parse(d, separator: ".") else { return nil }
            return Self.candle(Date(timeIntervalSince1970: time.doubleValue), open, high, low, close)
        }
    }

    private static func candle(_ date: Date, _ open: Decimal, _ high: Decimal, _ low: Decimal, _ close: Decimal) -> ChartSample? {
        guard low > 0, low <= min(open, close), high >= max(open, close) else { return nil }
        return ChartSample(date: date, close: close, open: open, high: high, low: low)
    }

    private static func window(_ samples: [ChartSample], range: ChartRange) -> [ChartSample] {
        let start = range.start(from: Date()) ?? .distantPast
        var unique: [Date: ChartSample] = [:]
        for sample in samples where sample.date >= start && sample.date <= Date() {
            unique[sample.date] = sample
        }
        return unique.values.sorted { $0.date < $1.date }
    }

    private static func query(_ url: URL, _ parameters: [String: String]) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = parameters.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url!
    }

    private struct PriceHistory: Decodable { let prices: [[Decimal]] }

    private struct GeckoQuote: Decodable {
        let id: String
        let current_price: Decimal?
        let price_change_24h: Decimal?
        let sparkline_in_7d: Sparkline?

        struct Sparkline: Decodable { let price: [Decimal]? }
        let price_change_percentage_24h: Decimal?
        let market_cap: Decimal?
        let total_volume: Decimal?
        let image: URL?
        let last_updated: String?

        var quote: Quote {
            let format = ISO8601DateFormatter()
            format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var date = last_updated.flatMap(format.date(from:))
            if date == nil {
                format.formatOptions = [.withInternetDateTime]
                date = last_updated.flatMap(format.date(from:))
            }
            return Quote(id: id, price: current_price, change: price_change_percentage_24h, marketCap: market_cap,
                         volume: total_volume, image: image, updated: date,
                         sparkline: sparkline_in_7d?.price, change24hUSD: price_change_24h)
        }
    }
}

enum KrakenSymbols {
    static let pairs: [String: String] = Dictionary(uniqueKeysWithValues:
        "ETH SOL TON USDT USDC BNB XRP ADA TRX AVAX LINK DOT LTC BCH SHIB PEPE SUI XLM XMR NEAR ATOM APT ARB OP UNI HBAR ETC POL"
        .split(separator: " ").map { (String($0), "\($0)USD") } + [("BTC", "XBTUSD"), ("DOGE", "XDGUSD")])
}
