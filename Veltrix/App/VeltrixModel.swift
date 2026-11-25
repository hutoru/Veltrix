import Foundation
import SwiftUI

@MainActor final class VeltrixModel: ObservableObject {
    @Published private(set) var ledger: Ledger
    @Published private(set) var quotes: [String: Quote] = [:]
    @Published private(set) var rates: [String: FXRate] = [:]
    @Published private(set) var loading = false
    @Published private(set) var marketMessage: String?
    @Published private(set) var quoteDate: Date?
    @Published private(set) var fxDate: Date?
    @Published private(set) var storageError = false
    @Published var error: String?
    @Published var toast: String?
    @Published var currency: String { didSet { defaults.set(currency, forKey: "currency") } }
    @Published var digits: Int { didSet { defaults.set(digits, forKey: "digits") } }
    @Published var hide: Bool { didSet { defaults.set(hide, forKey: "hide") } }
    @Published var theme: String { didSet { defaults.set(theme, forKey: "theme") } }
    @Published private(set) var fee: Decimal { didSet { defaults.set(DisplayStored.string(fee), forKey: "fee") } }
    @Published var favorites: Set<String> { didSet { defaults.set(Array(favorites), forKey: "favorites") } }

    private var store: (any LedgerStore)?
    private var provider: any MarketDataProvider
    private let http: HTTPClient
    private let cache: MarketCache
    private let defaults: UserDefaults
    private let testing: Bool
    private var updates: Task<Void, Never>?
    private var stream: Task<Void, Never>?
    private var fxLoading = false
    private var inForeground = false
    private var marketAccess = true
    private var gecko: [String: Quote] = [:]
    private var ticks: [String: TickerTick] = [:]
    private var toastTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard, store suppliedStore: (any LedgerStore)? = nil,
         provider suppliedProvider: (any MarketDataProvider)? = nil, testing: Bool = false) {
        self.defaults = defaults
        self.testing = testing
        let client = HTTPClient()
        http = client
        provider = suppliedProvider ?? PublicMarketProvider(http: client, demoKey: testing ? nil : Self.loadDemoKey())
        cache = MarketCache(directory: testing ? nil : try? FileManager.default.url(for: .cachesDirectory,
                                                                                   in: .userDomainMask, appropriateFor: nil, create: true))
        ledger = Ledger.fresh(name: L.text("Main portfolio"))
        currency = defaults.string(forKey: "currency").flatMap { Fiat.currencies.contains($0) ? $0 : nil } ?? "USD"
        digits = min(12, max(0, defaults.object(forKey: "digits") as? Int ?? 2))
        hide = defaults.bool(forKey: "hide")
        theme = defaults.string(forKey: "theme") ?? "dark"
        fee = defaults.string(forKey: "fee").flatMap { MoneyMath.parse($0, separator: ".") } ?? Decimal(1) / 1_000
        favorites = Set(defaults.stringArray(forKey: "favorites") ?? [])
        do {
            let storage = try suppliedStore ?? CoreDataLedgerStore(inMemory: testing)
            if let loaded = try storage.load() { ledger = loaded } else { try storage.save(ledger) }
            store = storage
        } catch {
            storageError = true
        }
    }

    var portfolio: Portfolio { ledger.portfolios.first { $0.id == ledger.selected } ?? ledger.portfolios[0] }
    var cards: [VirtualCard] { ledger.cards.filter { $0.owner == ledger.selected } }
    var prices: [String: Decimal] { quotes.compactMapValues(\.price) }

    var usablePrices: [String: Decimal] {
        guard inForeground, marketAccess else { return [:] }
        return quotes.compactMapValues { quote in
            guard let updated = quote.updated, let price = quote.price else { return nil }
            let age = Date().timeIntervalSince(updated)
            return age >= -30 && age <= (quote.exchange ? 120 : 300) && price > 0 ? price : nil
        }
    }

    func money(_ amount: Decimal?, privateValue: Bool = true, price: Bool = false) -> String {
        if hide && privateValue { return "••••••" }
        guard let amount, let converted = try? Fiat.convert(amount, currency: currency, rates: rates) else { return "—" }
        let places = price && abs(converted) < 1 && converted != 0 ? max(10, digits) : digits
        return Display.money(converted, currency: currency, digits: places, minimum: digits)
    }

    func units(_ amount: Decimal) -> String { hide ? "••••" : Display.number(amount, maximum: 16) }

    func execute(_ command: Command, id: UUID = UUID()) -> Bool {
        do {
            let next = try TradingEngine.apply(command, to: ledger, id: id, prices: prices, execution: usablePrices)
            try commit(next)
            Feedback.success()
            toast = L.text("Simulation saved")
            toastTask?.cancel()
            toastTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                if !Task.isCancelled { self?.toast = nil }
            }
            if case .limit = command { settle() }
            return true
        } catch {
            self.error = Display.error(error)
            Feedback.failure()
            return false
        }
    }

    func setFee(_ value: Decimal?) -> Bool {
        guard let value, value >= 0, value < 100 else {
            error = L.text("Enter a fee between 0% and 100% (exclusive).")
            return false
        }
        do {
            fee = try MoneyMath.divide(value, 100)
            return true
        } catch {
            self.error = Display.error(error)
            return false
        }
    }

    func importBackup(_ data: Data) -> Bool {
        do {
            try commit(SimulationBackup.load(data))
            settle()
            return true
        } catch {
            self.error = Display.error(error)
            return false
        }
    }

    func exportBackup() throws -> Data {
        guard !storageError else { throw SimulationError.invalidBackup }
        return try SimulationBackup.export(ledger)
    }

    func setDemoKey(_ text: String) async -> Bool {
        do {
            let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if key.isEmpty { try Keychain.remove("coingecko") }
            else { try Keychain.write(Data(key.utf8), key: "coingecko") }
            provider = PublicMarketProvider(http: http, demoKey: key.isEmpty ? nil : key)
            return true
        } catch {
            self.error = L.text("Secure storage unavailable")
            return false
        }
    }

    func start() {
        guard !inForeground else { return }
        inForeground = true
        guard !testing else { return }
        updates = Task { [weak self] in
            await self?.restoreCache()
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: 65_000_000_000)
            }
        }
        stream = Task { [weak self] in
            var delay: UInt64 = 5
            while !Task.isCancelled {
                do {
                    try await KrakenTicker().listen { [weak self] in self?.receive($0) }
                } catch {
                    if Task.isCancelled { return }
                }
                try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
                delay = min(delay * 2, 120)
            }
        }
    }

    func stop() {
        inForeground = false
        updates?.cancel()
        stream?.cancel()
        updates = nil
        stream = nil
        marketAccess = false
        ticks.removeAll()
        rebuildQuotes()
    }

    func refresh() async {
        guard !loading, !testing else { return }
        loading = true
        defer { loading = false }
        async let updatingFX: Void = refreshFX()
        do {
            let values = try await provider.quotes()
            try Task.checkCancellation()
            marketAccess = true
            for quote in values where quote.price.map({ $0 > 0 }) ?? false { gecko[quote.id] = quote }
            quoteDate = values.compactMap(\.updated).max()
            rebuildQuotes()
            marketMessage = nil
            await cache.write(Array(gecko.values), key: "quotes")
            if !Task.isCancelled { settle() }
        } catch is CancellationError {
        } catch {
            if !Task.isCancelled {
                marketAccess = !ticks.isEmpty
                marketMessage = Display.error(error)
                rebuildQuotes()
            }
        }
        await updatingFX
    }

    func cachedHistory(_ asset: Asset, range: ChartRange, candles: Bool) async -> Cached<MarketHistory>? {
        await cache.read(MarketHistory.self, key: key(asset, range: range, candles: candles))
    }

    func loadHistory(_ asset: Asset, range: ChartRange, candles: Bool) async throws -> MarketHistory {
        let entryKey = key(asset, range: range, candles: candles)
        let refreshAfter: TimeInterval = range == .hour || range == .day ? 180 : 1_800
        if let cached = await cache.read(MarketHistory.self, key: entryKey),
           Date().timeIntervalSince(cached.saved) < refreshAfter {
            return cached.value
        }
        let history = try await provider.history(asset: asset, range: range, candles: candles)
        try Task.checkCancellation()
        await cache.write(history, key: entryKey)
        return history
    }

    private func key(_ asset: Asset, range: ChartRange, candles: Bool) -> String {
        "\(asset.id)-\(range.rawValue)-\(candles ? "ohlc" : "close")"
    }

    private func refreshFX() async {
        guard !fxLoading, fxDate.map({ Date().timeIntervalSince($0) > 7_200 }) ?? true else { return }
        fxLoading = true
        defer { fxLoading = false }
        do {
            let values = try await provider.currencies()
            try Task.checkCancellation()
            let saved = Date()
            for rate in values { rates[rate.quote] = rate }
            fxDate = saved
            await cache.write(Array(rates.values), key: "fx")
        } catch {}
    }

    private func restoreCache() async {
        if gecko.isEmpty, let saved = await cache.read([Quote].self, key: "quotes"), !Task.isCancelled {
            for quote in saved.value where gecko[quote.id] == nil { gecko[quote.id] = quote }
            quoteDate = gecko.values.compactMap(\.updated).max()
            rebuildQuotes()
        }
        if rates.isEmpty, let saved = await cache.read([FXRate].self, key: "fx"), !Task.isCancelled {
            for rate in saved.value { rates[rate.quote] = rate }
            fxDate = saved.saved
        }
    }

    private func receive(_ values: [TickerTick]) {
        guard inForeground else { return }
        for tick in values where tick.date > (ticks[tick.asset]?.date ?? .distantPast) { ticks[tick.asset] = tick }
        marketAccess = true
        rebuildQuotes()
        settle()
    }

    private func rebuildQuotes() {
        var merged = gecko
        for (asset, tick) in ticks where Date().timeIntervalSince(tick.date) <= 120 {
            var quote = merged[asset] ?? Quote(id: asset)
            quote.price = tick.price
            quote.updated = tick.date
            quote.exchange = true
            merged[asset] = quote
        }
        quotes = merged
    }

    private func settle() {
        let live = usablePrices
        guard !live.isEmpty, !storageError else { return }
        do {
            let next = try TradingEngine.settle(ledger, execution: live, prices: live, at: Date())
            if next != ledger { try commit(next) }
        } catch {
            self.error = Display.error(error)
        }
    }

    private func commit(_ next: Ledger) throws {
        guard let store else { throw SimulationError.invalidBackup }
        try store.save(next)
        ledger = next
    }

    private static func loadDemoKey() -> String? {
        (try? Keychain.read("coingecko")).flatMap { String(data: $0, encoding: .utf8) }
    }
}

private enum DisplayStored {
    static func string(_ value: Decimal) -> String { NSDecimalNumber(decimal: value).stringValue }
}
