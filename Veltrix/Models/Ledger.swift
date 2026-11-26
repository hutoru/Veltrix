import Foundation

struct Position: Codable, Equatable, Sendable {
    var units: Decimal
    var basis: Decimal
    var average: Decimal? { try? MoneyMath.divide(basis, units) }
}

enum OperationKind: String, Codable, CaseIterable, Sendable {
    case buy, sell, swap, send, receive, deposit, adjustment, cardTopUp, cardReturn, cardPayment, refund, qrPayment
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
    var availableCashAfterFill: Decimal?

    var settlementUSD: Decimal? {
        guard let usd else { return nil }
        switch kind {
        case .buy: return try? MoneyMath.add(usd, fee)
        case .sell, .swap: return try? MoneyMath.subtract(usd, fee)
        default: return usd
        }
    }
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
    var primaryCardID: UUID?

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
        guard !entries.contains(where: { $0.date >= cutoff && $0.date <= now && $0.valuationUnavailable == true }) else { return nil }
        return performance(since: cutoff, until: now, liveValue: try value(prices: prices)).change
    }

    func performanceHistory(since cutoff: Date) -> [PortfolioPoint] {
        performance(since: cutoff).points
    }

    func performance(since cutoff: Date, until end: Date = .distantFuture, liveValue: Decimal? = nil)
        -> (points: [PortfolioPoint], change: (value: Decimal, percent: Decimal?)?) {
        let lastUnknown = entries.last(where: { $0.date <= end && $0.valuationUnavailable == true })?.date ?? .distantPast
        var visible = history.filter { $0.date >= cutoff && $0.date > lastUnknown && $0.date <= end }
        if let liveValue, end > lastUnknown, end >= cutoff, end < .distantFuture {
            let point = PortfolioPoint(date: end, value: liveValue)
            if visible.last?.date == end { visible[visible.count - 1] = point }
            else { visible.append(point) }
        }
        guard let start = visible.first else { return ([], nil) }
        let flows = entries.filter { $0.date > start.date && $0.externalFlow != 0 }.sorted { $0.date < $1.date }
        var flowIndex = 0
        var net: Decimal = 0
        var points: [PortfolioPoint] = []
        do {
            for point in visible {
                while flowIndex < flows.count && flows[flowIndex].date <= point.date {
                    net = try MoneyMath.addValuation(net, flows[flowIndex].externalFlow)
                    flowIndex += 1
                }
                let change = try MoneyMath.subtractValuation(point.value, start.value)
                points.append(PortfolioPoint(date: point.date, value: try MoneyMath.subtractValuation(change, net)))
            }
            guard points.count > 1, let last = points.last, last.date > start.date else { return (points, nil) }
            // Modified Dietz weights each contribution or withdrawal by the time it was invested.
            let duration = last.date.timeIntervalSince(start.date)
            let basis = try flows.prefix(flowIndex).reduce(start.value) { capital, entry in
                let weight = Decimal(last.date.timeIntervalSince(entry.date) / duration)
                return try MoneyMath.addValuation(capital, MoneyMath.multiply(entry.externalFlow, weight))
            }
            let percent = basis > 0 ? try MoneyMath.multiply(MoneyMath.divide(last.value, basis), 100) : nil
            return (points, (last.value, percent))
        } catch {
            return ([], nil)
        }
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
    var localPaymentRequests: [UUID: LocalPaymentRequest]?

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
                  portfolio.primaryCardID.map({ id in cards.contains { $0.id == id && $0.owner == portfolio.id } }) ?? true,
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
                let reserveMatches: Bool
                if order.side == .buy {
                    let gross = try MoneyMath.quotedUSD(order.units, at: order.limit)
                    let settled = try? MoneyMath.add(gross, MoneyMath.multiply(gross, order.feeRate))
                    let legacyGross = try? MoneyMath.multiply(order.units, order.limit)
                    let legacy = legacyGross.flatMap { try? MoneyMath.add($0, MoneyMath.multiply($0, order.feeRate)) }
                    reserveMatches = order.reserved == settled || order.reserved == legacy
                } else {
                    reserveMatches = order.reserved == order.units
                }
                guard reserveMatches,
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
        for (id, request) in localPaymentRequests ?? [:] {
            guard request.id == id, ids.contains(request.recipient), !operationIDs.contains(id),
                  request.isValid else { throw SimulationError.invalidBackup }
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
