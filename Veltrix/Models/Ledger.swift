import Foundation

struct Position: Codable, Equatable, Sendable {
    var units: Decimal
    var basis: Decimal
    var average: Decimal? { try? MoneyMath.divide(basis, units) }
}

enum OperationKind: String, Codable, CaseIterable, Sendable {
    case buy, sell, swap, send, receive, deposit, adjustment, cardTopUp, cardReturn, cardPayment, refund
}

struct Entry: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var date: Date
    var kind: OperationKind
    var asset: String
    var amount: Decimal
    var usd: Decimal?
    var fee: Decimal = 0
    var profit: Decimal?
    var counterAsset: String?
    var counterAmount: Decimal?
    var note: String = ""
    var cardID: UUID?
    var reference: UUID?
    var externalFlow: Decimal = 0
    var valuationUnavailable: Bool?
}

enum OrderSide: String, Codable, CaseIterable, Sendable { case buy, sell }
enum OrderStatus: String, Codable, Sendable { case open, filled, cancelled }

struct LimitOrder: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var date: Date
    var side: OrderSide
    var asset: String
    var units: Decimal
    var limit: Decimal
    var feeRate: Decimal
    var reserved: Decimal
    var status: OrderStatus = .open
    var closedAt: Date?
    var filledPrice: Decimal?
}

struct PortfolioPoint: Codable, Equatable, Sendable {
    var date: Date
    var value: Decimal
}

struct Portfolio: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var createdAt = Date()
    var cash: Decimal
    var positions: [String: Position] = [:]
    var entries: [Entry] = []
    var orders: [LimitOrder] = []
    var history: [PortfolioPoint] = []

    func freeCash() throws -> Decimal {
        try orders.filter { $0.status == .open && $0.side == .buy }
            .reduce(cash) { try MoneyMath.subtract($0, $1.reserved) }
    }

    func freeUnits(_ asset: String) throws -> Decimal {
        try orders.filter { $0.status == .open && $0.side == .sell && $0.asset == asset }
            .reduce(positions[asset]?.units ?? 0) { try MoneyMath.subtract($0, $1.reserved) }
    }

    func value(prices: [String: Decimal]) throws -> Decimal {
        try positions.keys.sorted().reduce(cash) { subtotal, asset in
            guard let price = prices[asset], let position = positions[asset], price > 0 else {
                throw SimulationError.missingQuote
            }
            return try MoneyMath.addValuation(subtotal, MoneyMath.multiply(price, position.units))
        }
    }

    func unrealized(prices: [String: Decimal]) throws -> Decimal {
        try positions.keys.sorted().reduce(0) { total, asset in
            guard let price = prices[asset], let position = positions[asset], price > 0 else {
                throw SimulationError.missingQuote
            }
            let gain = try MoneyMath.subtractValuation(MoneyMath.multiply(price, position.units), position.basis)
            return try MoneyMath.addValuation(total, gain)
        }
    }

    func realized() throws -> Decimal {
        try entries.compactMap(\.profit).reduce(Decimal.zero, MoneyMath.addValuation)
    }

    func daily(now: Date, prices: [String: Decimal]) throws -> (value: Decimal, percent: Decimal?)? {
        let cutoff = now.addingTimeInterval(-86_400)
        let baseline = history.last(where: { $0.date <= cutoff })
        let start = baseline ?? (createdAt > cutoff ? history.first : nil)
        guard let start, start.date < now, start.date >= cutoff.addingTimeInterval(-3_600) else { return nil }
        let changes = entries.filter { $0.date > start.date && $0.date <= now }
        guard !changes.contains(where: { $0.valuationUnavailable == true }) else { return nil }
        let net = try changes.map(\.externalFlow).reduce(Decimal.zero, MoneyMath.addValuation)
        let value = try MoneyMath.subtractValuation(MoneyMath.subtractValuation(self.value(prices: prices), start.value), net)
        let basis = try MoneyMath.addValuation(start.value, max(0, net))
        let percent = basis > 0 ? try MoneyMath.multiply(MoneyMath.divide(value, basis), 100) : nil
        return (value, percent)
    }

    mutating func observe(prices: [String: Decimal], at date: Date, force: Bool = false) {
        guard let value = try? value(prices: prices) else { return }
        if let last = history.last {
            guard last.date <= date else { return }
            if last.date == date {
                history[history.count - 1].value = value
                return
            }
            if !force && date.timeIntervalSince(last.date) < 300 { return }
        }
        history.append(.init(date: date, value: value))
        if history.count > 12_000 {
            let older = history.prefix(6_000)
            var sampled: [PortfolioPoint] = []
            for point in older where sampled.last.map({ point.date.timeIntervalSince($0.date) >= 3_600 }) ?? true {
                sampled.append(point)
            }
            history = Array(sampled.suffix(5_999)) + history.dropFirst(6_000)
        }
    }
}

enum CardTier: String, Codable, CaseIterable, Sendable {
    case classic, gold, platinum, signature, infinite
    case standard, atlasGold, atlasPlatinum, world, worldElite
    case green, reserveGold, reservePlatinum, centurion
    case black, carbonBlack, royalGold, brushedSilver, ceramicWhite, crystalGlass, holographic, purple, custom
}

enum CardMaterial: String, Codable, CaseIterable, Sendable {
    case matte, titanium, gold, silver, carbon, ceramic, glass, holographic
}

enum CardTexture: String, Codable, CaseIterable, Sendable {
    case none, brushed, woven, engraved
}

enum CardTypeface: String, Codable, CaseIterable, Sendable {
    case modern, classic, mono
}

struct CardDesign: Codable, Equatable, Sendable {
    var material: CardMaterial
    var texture: CardTexture
    var typeface: CardTypeface = .modern
    var tint: UInt32?
    var shade: UInt32?
    var sheen = 0.5
    var markX = 0.18
    var markY = 0.23
    var portrait: Data?

    var isValid: Bool {
        (0...1).contains(sheen) && (0.13...0.87).contains(markX) && (0.14...0.82).contains(markY)
            && (tint.map { $0 <= 0xFFFFFF } ?? true) && (shade.map { $0 <= 0xFFFFFF } ?? true)
            && (portrait?.count ?? 0) <= 360_000
    }
}

struct VirtualCard: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var owner: UUID
    var tier: CardTier
    var name: String
    var balance: Decimal = 0
    var limit: Decimal?
    var frozen = false
    var design: CardDesign? = nil
}

struct Ledger: Codable, Equatable, Sendable {
    let schema: Int
    var portfolios: [Portfolio]
    var selected: UUID
    var cards: [VirtualCard]
    var operationIDs: Set<UUID>

    static func fresh(name: String = "Main", cash: Decimal = 10_000, date: Date = Date()) -> Ledger {
        var portfolio = Portfolio(name: name, createdAt: date, cash: cash)
        portfolio.observe(prices: [:], at: date, force: true)
        return Ledger(schema: 1, portfolios: [portfolio], selected: portfolio.id, cards: [], operationIDs: [])
    }

    func validate(assets: Set<String>) throws {
        let ids = Set(portfolios.map(\.id))
        guard schema == 1, ids.count == portfolios.count, ids.contains(selected),
              Set(cards.map(\.id)).count == cards.count else { throw SimulationError.invalidBackup }
        var events = Set<UUID>()
        var orders = Set<UUID>()
        for portfolio in portfolios {
            guard !portfolio.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  try portfolio.freeCash() >= 0,
                  portfolio.history.allSatisfy({ !$0.value.isNaN && $0.value >= 0 }),
                  zip(portfolio.history, portfolio.history.dropFirst()).allSatisfy({ $0.0.date < $0.1.date })
            else { throw SimulationError.invalidBackup }
            try MoneyMath.nonnegative(portfolio.cash)
            for (asset, position) in portfolio.positions {
                guard assets.contains(asset), try portfolio.freeUnits(asset) >= 0 else { throw SimulationError.invalidBackup }
                try MoneyMath.quantity(position.units)
                try MoneyMath.nonnegative(position.basis)
            }
            for order in portfolio.orders {
                guard orders.insert(order.id).inserted, operationIDs.contains(order.id), assets.contains(order.asset),
                      order.feeRate >= 0, order.feeRate <= 1 else { throw SimulationError.invalidBackup }
                try MoneyMath.quantity(order.units)
                try MoneyMath.quantity(order.limit)
                let gross = try MoneyMath.multiply(order.units, order.limit)
                let reserve = order.side == .buy
                    ? try MoneyMath.add(gross, MoneyMath.multiply(gross, order.feeRate)) : order.units
                guard reserve == order.reserved,
                      order.status != .open || order.side != .sell || portfolio.positions[order.asset] != nil
                else { throw SimulationError.invalidBackup }
            }
            for entry in portfolio.entries {
                guard events.insert(entry.id).inserted, operationIDs.contains(entry.id),
                      entry.asset == "USD" || assets.contains(entry.asset),
                      entry.counterAsset.map(assets.contains) ?? true else { throw SimulationError.invalidBackup }
                try MoneyMath.nonnegative(entry.amount)
                try MoneyMath.nonnegative(entry.fee)
                if let usd = entry.usd { try MoneyMath.nonnegative(usd) }
                guard !entry.externalFlow.isNaN, !(entry.profit?.isNaN ?? false) else { throw SimulationError.invalidBackup }
            }
        }
        for card in cards {
            guard ids.contains(card.owner), !card.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  card.design?.isValid ?? true
            else { throw SimulationError.invalidBackup }
            try MoneyMath.nonnegative(card.balance)
            if let limit = card.limit { try MoneyMath.quantity(limit) }
        }
    }
}
