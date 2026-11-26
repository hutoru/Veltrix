import Foundation

struct Asset: Identifiable, Hashable, Sendable {
    let id: String
    let ticker: String
    let name: String

    static let catalog: [Asset] = [
        .init(id: "bitcoin", ticker: "BTC", name: "Bitcoin"),
        .init(id: "ethereum", ticker: "ETH", name: "Ethereum"),
        .init(id: "solana", ticker: "SOL", name: "Solana"),
        .init(id: "the-open-network", ticker: "TON", name: "Toncoin"),
        .init(id: "tether", ticker: "USDT", name: "Tether"),
        .init(id: "usd-coin", ticker: "USDC", name: "USDC"),
        .init(id: "binancecoin", ticker: "BNB", name: "BNB"),
        .init(id: "ripple", ticker: "XRP", name: "XRP"),
        .init(id: "dogecoin", ticker: "DOGE", name: "Dogecoin"),
        .init(id: "cardano", ticker: "ADA", name: "Cardano"),
        .init(id: "tron", ticker: "TRX", name: "TRON"),
        .init(id: "avalanche-2", ticker: "AVAX", name: "Avalanche"),
        .init(id: "chainlink", ticker: "LINK", name: "Chainlink"),
        .init(id: "polkadot", ticker: "DOT", name: "Polkadot"),
        .init(id: "litecoin", ticker: "LTC", name: "Litecoin"),
        .init(id: "bitcoin-cash", ticker: "BCH", name: "Bitcoin Cash"),
        .init(id: "shiba-inu", ticker: "SHIB", name: "Shiba Inu"),
        .init(id: "pepe", ticker: "PEPE", name: "Pepe"),
        .init(id: "sui", ticker: "SUI", name: "Sui"),
        .init(id: "stellar", ticker: "XLM", name: "Stellar"),
        .init(id: "monero", ticker: "XMR", name: "Monero"),
        .init(id: "near", ticker: "NEAR", name: "NEAR Protocol"),
        .init(id: "cosmos", ticker: "ATOM", name: "Cosmos"),
        .init(id: "aptos", ticker: "APT", name: "Aptos"),
        .init(id: "arbitrum", ticker: "ARB", name: "Arbitrum"),
        .init(id: "optimism", ticker: "OP", name: "Optimism"),
        .init(id: "uniswap", ticker: "UNI", name: "Uniswap"),
        .init(id: "hedera-hashgraph", ticker: "HBAR", name: "Hedera"),
        .init(id: "ethereum-classic", ticker: "ETC", name: "Ethereum Classic"),
        .init(id: "polygon-ecosystem-token", ticker: "POL", name: "Polygon")
    ]
    static let ids = Set(catalog.map(\.id))
    static func ticker(_ id: String) -> String { catalog.first { $0.id == id }?.ticker ?? id }
}

struct Quote: Codable, Sendable {
    var id: String
    var price: Decimal?
    var change: Decimal?
    var marketCap: Decimal?
    var volume: Decimal?
    var image: URL?
    var updated: Date?
    var exchange = false
    var sparkline: [Decimal]?
    var change24hUSD: Decimal?
}

struct ChartSample: Codable, Equatable, Identifiable, Sendable {
    var date: Date
    var close: Decimal
    var open: Decimal?
    var high: Decimal?
    var low: Decimal?
    var series: Int? = nil
    var id: Date { date }
}

enum ChartRange: String, CaseIterable, Sendable {
    case hour = "1H", day = "24H", week = "7D", month = "30D", quarter = "90D", year = "1Y", all = "ALL"

    var displayTitle: String {
        switch self {
        case .day: return L.text("1D")
        case .week: return L.text("1W")
        case .month: return L.text("1M")
        case .quarter: return L.text("3M")
        default: return L.text(rawValue)
        }
    }

    var days: Int? {
        switch self {
        case .hour, .day: return 1
        case .week: return 7
        case .month: return 30
        case .quarter: return 90
        case .year: return 365
        case .all: return nil
        }
    }

    func start(from date: Date) -> Date? {
        if self == .hour { return date.addingTimeInterval(-3_600) }
        return days.map { date.addingTimeInterval(-Double($0) * 86_400) }
    }
}

struct FXRate: Codable, Sendable {
    var quote: String
    var date: String
    var rate: Decimal
}

enum Fiat {
    static let currencies = """
    USD EUR RUB GBP TRY AED CHF CNY JPY PLN KZT UAH CAD AUD HKD SGD NZD NOK SEK DKK CZK HUF RON ISK INR IDR
    KRW MYR PHP THB VND TWD ILS SAR QAR BHD KWD JOD OMR EGP MAD TND ZAR NGN KES GHS MXN BRL ARS CLP COP PEN
    UYU BOB CRC DOP GTQ HNL PAB UZS GEL AMD AZN RSD BAM MKD ALL PKR BDT LKR NPR XOF XAF XCD ETB UGX TZS
    """.split(whereSeparator: \.isWhitespace).map(String.init)

    static func convert(_ usd: Decimal, currency: String, rates: [String: FXRate]) throws -> Decimal {
        if currency == "USD" { return usd }
        guard let rate = rates[currency]?.rate, rate > 0 else { throw SimulationError.missingQuote }
        return try MoneyMath.multiply(usd, rate)
    }
}
