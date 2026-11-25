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
    @Published var pushOperations: Bool { didSet { defaults.set(pushOperations, forKey: "pushOperations") } }
    @Published var privateNotifications: Bool { didSet { defaults.set(privateNotifications, forKey: "privateNotifications") } }
    @Published private(set) var onSet: Bool { didSet { defaults.set(onSet, forKey: "onSet") } }
    @Published var quickActionIDs: [String] { didSet { defaults.set(quickActionIDs, forKey: "quickActionIDs") } }
    @Published private(set) var priceAlerts: [PriceAlert] {
        didSet { defaults.set(try? JSONEncoder().encode(priceAlerts), forKey: "priceAlerts") }
    }
    @Published private(set) var recentAssetIDs: [String] {
        didSet { defaults.set(recentAssetIDs, forKey: "recentAssetIDs") }
    }
    @Published private var notificationsCleared: Date { didSet { defaults.set(notificationsCleared, forKey: notificationKey("notificationsCleared")) } }
    @Published private var notificationsReadDate: Date { didSet { defaults.set(notificationsReadDate, forKey: notificationKey("notificationsReadDate")) } }
    @Published private var notificationsRead: Set<String> { didSet { defaults.set(Array(notificationsRead), forKey: notificationKey("notificationsRead")) } }

    private var store: (any LedgerStore)?
    private var mainStore: (any LedgerStore)?
    private var onSetStore: (any LedgerStore)?
    private var provider: any MarketDataProvider
    private let http: HTTPClient
    private let cache: MarketCache
    private let defaults: UserDefaults
    private let testing: Bool
    private var updates: Task<Void, Never>?
    private var stream: Task<Void, Never>?
    private var fxLoading = false
    private var inForeground = false
    private var geckoOnline = false
    private var gecko: [String: Quote] = [:]
    private var ticks: [String: TickerTick] = [:]
    private var toastTask: Task<Void, Never>?
    #if DEBUG
    private var uiSamples: [ChartSample] = []
    #endif

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
        pushOperations = defaults.bool(forKey: "pushOperations")
        privateNotifications = defaults.object(forKey: "privateNotifications") as? Bool ?? true
        let onSet = defaults.bool(forKey: "onSet")
        self.onSet = onSet
        quickActionIDs = defaults.stringArray(forKey: "quickActionIDs") ?? Self.standardActions.map(\.rawValue)
        priceAlerts = defaults.data(forKey: "priceAlerts")
            .flatMap { try? JSONDecoder().decode([PriceAlert].self, from: $0) } ?? []
        recentAssetIDs = defaults.stringArray(forKey: "recentAssetIDs") ?? []
        let prefix = onSet ? "onSet." : ""
        notificationsCleared = defaults.object(forKey: prefix + "notificationsCleared") as? Date ?? .distantPast
        notificationsReadDate = defaults.object(forKey: prefix + "notificationsReadDate") as? Date ?? Date()
        notificationsRead = Set(defaults.stringArray(forKey: prefix + "notificationsRead") ?? [])
        do {
            mainStore = suppliedStore
            let storage = try (onSet ? onSetStore : mainStore) ?? CoreDataLedgerStore(inMemory: testing, onSet: onSet)
            ledger = try Self.loadLedger(from: storage)
            if onSet { onSetStore = storage } else { mainStore = storage }
            store = storage
        } catch {
            storageError = true
        }
        #if DEBUG
        if testing { loadTestMarket() }
        #endif
    }

    var portfolio: Portfolio { ledger.portfolios.first { $0.id == ledger.selected } ?? ledger.portfolios[0] }
    var cards: [VirtualCard] { ledger.cards.filter { $0.owner == ledger.selected } }
    var prices: [String: Decimal] { quotes.compactMapValues(\.price) }
    static let standardActions: [TradeAction] = [.buy, .sell, .send, .receive, .swap]

    var quickActions: [TradeAction] {
        var seen: Set<String> = []
        let actions = quickActionIDs.compactMap { id in
            seen.insert(id).inserted ? TradeAction(rawValue: id) : nil
        }
        return actions.isEmpty ? Self.standardActions : Array(actions.prefix(5))
    }

    func setOnSet(_ enabled: Bool) {
        guard onSet != enabled else { return }
        do {
            let storage = try (enabled ? onSetStore : mainStore) ?? CoreDataLedgerStore(inMemory: testing, onSet: enabled)
            let next = try Self.loadLedger(from: storage)
            if enabled { onSetStore = storage } else { mainStore = storage }
            store = storage
            ledger = next
            onSet = enabled
            notificationsCleared = defaults.object(forKey: notificationKey("notificationsCleared")) as? Date ?? .distantPast
            notificationsReadDate = defaults.object(forKey: notificationKey("notificationsReadDate")) as? Date ?? Date()
            notificationsRead = Set(defaults.stringArray(forKey: notificationKey("notificationsRead")) ?? [])
            toastTask?.cancel()
            toast = nil
        } catch {
            self.error = L.text("Local storage unavailable")
        }
    }

    private static func loadLedger(from storage: any LedgerStore) throws -> Ledger {
        if let loaded = try storage.load() { return loaded }
        let fresh = Ledger.fresh(name: L.text("Main portfolio"))
        try storage.save(fresh)
        return fresh
    }

    private func notificationKey(_ key: String) -> String { onSet ? "onSet." + key : key }

    var recentAssets: [Asset] {
        recentAssetIDs.compactMap { id in Asset.catalog.first { $0.id == id } }
    }

    func recordAsset(_ asset: Asset) {
        guard recentAssetIDs.first != asset.id else { return }
        recentAssetIDs = Array(([asset.id] + recentAssetIDs.filter { $0 != asset.id }).prefix(8))
    }

    func addPriceAlert(_ alert: PriceAlert) {
        priceAlerts.append(alert)
        checkPriceAlerts()
    }

    func removePriceAlert(_ id: UUID) { priceAlerts.removeAll { $0.id == id } }

    var notificationEntries: [Entry] {
        portfolio.entries.filter { $0.date > notificationsCleared && OperationNotifications.eligible($0) }
            .sorted { $0.date > $1.date }
    }

    var hasUnreadNotifications: Bool {
        portfolio.entries.reversed().contains { $0.date > notificationsCleared && OperationNotifications.eligible($0) && isUnread($0) }
    }

    func isUnread(_ entry: Entry) -> Bool {
        entry.date > notificationsReadDate && !notificationsRead.contains(entry.id.uuidString)
    }

    func readNotification(_ entry: Entry) {
        if isUnread(entry) { notificationsRead.insert(entry.id.uuidString) }
    }

    func readNotifications() {
        notificationsReadDate = .now
        notificationsRead = []
    }

    func clearNotifications() {
        notificationsCleared = .now
        readNotifications()
        if !onSet { OperationNotifications.clear() }
    }

    func openNotification(_ id: UUID) -> Entry? {
        guard let owner = ledger.portfolios.first(where: { $0.entries.contains { $0.id == id } }),
              let entry = owner.entries.first(where: { $0.id == id }) else { return nil }
        if owner.id != ledger.selected && !execute(.selectPortfolio(owner.id)) { return nil }
        readNotification(entry)
        return entry
    }

    var usablePrices: [String: Decimal] {
        guard inForeground else { return [:] }
        #if DEBUG
        if testing && !uiSamples.isEmpty { return prices }
        #endif
        return quotes.compactMapValues { quote in
            guard quote.exchange || geckoOnline, let updated = quote.updated, let price = quote.price else { return nil }
            let age = Date().timeIntervalSince(updated)
            return age >= -30 && age <= (quote.exchange ? 120 : 300) && price > 0 ? price : nil
        }
    }

    func money(_ amount: Decimal?, privateValue: Bool = true, price: Bool = false) -> String {
        if hide && privateValue { return "••••••" }
        guard let amount, let converted = try? Fiat.convert(amount, currency: currency, rates: rates) else { return "—" }
        let places = price ? FinancialFormatter.pricePrecision(converted, minimum: digits) : digits
        return Display.money(converted, currency: currency, digits: places, minimum: digits)
    }

    func signedMoney(_ amount: Decimal?) -> String {
        let text = money(amount)
        return !hide && text != "—" && (amount ?? 0) > 0 ? "+" + text : text
    }

    func units(_ amount: Decimal) -> String {
        hide ? "••••" : Display.number(amount, maximum: FinancialFormatter.pricePrecision(amount, minimum: 4))
    }

    func execute(_ command: Command, id: UUID = UUID()) -> Bool {
        do {
            let live = usablePrices
            let next = try TradingEngine.apply(command, to: ledger, id: id, prices: live, execution: live)
            try commit(next, notify: true)
            Feedback.success()
            toast = L.text("Operation saved")
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

    func validateTrade(_ command: Command, id: UUID) throws {
        let live = usablePrices
        _ = try TradingEngine.apply(command, to: ledger, id: id, prices: live, execution: live)
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
        geckoOnline = false
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
            geckoOnline = true
            for quote in values where quote.price.map({ $0 > 0 }) ?? false { gecko[quote.id] = quote }
            quoteDate = values.compactMap(\.updated).max()
            rebuildQuotes()
            checkPriceAlerts()
            marketMessage = nil
            await cache.write(Array(gecko.values), key: "quotes")
            if !Task.isCancelled { settle() }
        } catch is CancellationError {
        } catch {
            if !Task.isCancelled {
                geckoOnline = false
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
        #if DEBUG
        if testing && asset.id == "bitcoin", let latest = uiSamples.last {
            let cutoff = range.start(from: latest.date) ?? .distantPast
            return MarketHistory(samples: uiSamples.filter { $0.date >= cutoff }, source: "Kraken")
        }
        #endif
        guard !testing else { throw MarketError.unavailable }
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
        rebuildQuotes()
        checkPriceAlerts()
        settle()
    }

    private func checkPriceAlerts() {
        let live = usablePrices
        guard !onSet, !live.isEmpty, !priceAlerts.isEmpty else { return }
        var alerts = priceAlerts
        var triggered: [(PriceAlert, Decimal)] = []
        for index in alerts.indices {
            let alert = alerts[index]
            guard alert.triggeredAt == nil, let price = live[alert.asset],
                  (alert.above ? price >= alert.threshold : price <= alert.threshold) else { continue }
            alerts[index].triggeredAt = .now
            triggered.append((alert, price))
        }
        guard !triggered.isEmpty else { return }
        priceAlerts = alerts
        for (alert, price) in triggered {
            let message = L.format("Price alert · %@", Asset.ticker(alert.asset))
            if pushOperations && !testing && !onSet {
                let body = privateNotifications || hide ? message : message + " · " + money(price, privateValue: false, price: true)
                OperationNotifications.schedulePriceAlert(id: alert.id, body: body)
            }
            toast = message
        }
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if !Task.isCancelled { self?.toast = nil }
        }
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
            if next != ledger { try commit(next, notify: true) }
        } catch {
            self.error = Display.error(error)
        }
    }

    private func commit(_ next: Ledger, notify: Bool = false) throws {
        guard let store else { throw SimulationError.invalidBackup }
        let previous = ledger
        try store.save(next)
        ledger = next
        guard notify, pushOperations, !testing, !onSet else { return }
        for portfolio in next.portfolios {
            let count = previous.portfolios.first { $0.id == portfolio.id }?.entries.count ?? 0
            guard portfolio.entries.count > count else { continue }
            for entry in portfolio.entries.dropFirst(count) where OperationNotifications.eligible(entry) {
                let filled = portfolio.orders.contains { $0.id == entry.id && $0.status == .filled }
                var summary: String?
                if !privateNotifications && !hide {
                    let quantity = entry.asset == "USD" ? money(entry.amount) : "\(units(entry.amount)) \(Asset.ticker(entry.asset))"
                    if entry.asset != "USD", let usd = entry.usd {
                        summary = quantity + " · " + money(usd)
                    } else {
                        summary = quantity
                    }
                }
                OperationNotifications.schedule(entry, filled: filled, amounts: summary)
            }
        }
    }

    private static func loadDemoKey() -> String? {
        (try? Keychain.read("coingecko")).flatMap { String(data: $0, encoding: .utf8) }
    }

    #if DEBUG
    private func loadTestMarket() {
        guard let json = ProcessInfo.processInfo.environment["VELTRIX_XCUITEST_OHLC"],
              let rows = try? JSONDecoder().decode([[Decimal]].self, from: Data(json.utf8)) else { return }
        uiSamples = rows.compactMap { row in
            guard row.count == 5 else { return nil }
            return ChartSample(date: Date(timeIntervalSince1970: NSDecimalNumber(decimal: row[0]).doubleValue),
                               close: row[4], open: row[1], high: row[2], low: row[3])
        }
        guard let first = uiSamples.first, let last = uiSamples.last, first.close > 0 else { return }
        quoteDate = last.date
        gecko["bitcoin"] = Quote(id: "bitcoin", price: last.close,
                               change: (last.close / first.close - 1) * 100, updated: last.date,
                               exchange: true, sparkline: uiSamples.map(\.close))
        rebuildQuotes()
    }
    #endif
}

private enum DisplayStored {
    static func string(_ value: Decimal) -> String { NSDecimalNumber(decimal: value).stringValue }
}
