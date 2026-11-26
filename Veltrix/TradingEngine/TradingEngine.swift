import Foundation

enum Command: Sendable {
    case market(OrderSide, String, Decimal, Decimal)
    case marketNotional(OrderSide, String, Decimal, Decimal)
    case limit(OrderSide, String, Decimal, Decimal, Decimal)
    case cancel(UUID)
    case swap(String, String, Decimal, Decimal)
    case transfer(receive: Bool, asset: String, units: Decimal, label: String)
    case registerQR(LocalPaymentRequest, replacing: UUID?)
    case payQR(UUID, from: UUID)
    case deposit(Decimal)
    case setCash(Decimal)
    case setPosition(String, Decimal, Decimal)
    case createPortfolio(String, Decimal)
    case selectPortfolio(UUID)
    case resetPortfolio
    case createCard(CardTier, String, Decimal?, design: CardDesign? = nil)
    case configureCard(UUID, String, Decimal?, tier: CardTier? = nil, design: CardDesign? = nil)
    case freezeCard(UUID)
    case setPrimaryCard(UUID)
    case deleteCard(UUID)
    case moveCardFunds(UUID, Decimal, toCard: Bool)
    case pay(UUID, Decimal, String, subscription: Bool = false)
    case refund(UUID, UUID)
}

enum TradingEngine {
    static func apply(
        _ command: Command, to original: Ledger, id: UUID = UUID(), at date: Date = Date(),
        prices: [String: Decimal] = [:], execution: [String: Decimal] = [:]
    ) throws -> Ledger {
        var ledger = original
        guard ledger.operationIDs.insert(id).inserted else { throw SimulationError.duplicate }
        let source: UUID
        if case let .payQR(_, from) = command { source = from } else { source = ledger.selected }
        guard let index = ledger.portfolios.firstIndex(where: { $0.id == source }) else {
            throw SimulationError.missingRecord
        }
        var portfolio = ledger.portfolios[index]
        var entry: Entry?
        var changedValue = false

        switch command {
        case let .market(side, asset, units, fee):
            let price = try quote(asset, in: execution)
            entry = try trade(side, asset: asset, units: units, price: price, fee: fee, id: id, date: date, portfolio: &portfolio)
            changedValue = true

        case let .marketNotional(side, asset, notional, fee):
            try MoneyMath.quantity(notional)
            let price = try quote(asset, in: execution)
            let units = try MoneyMath.divide(notional, price)
            entry = try trade(side, asset: asset, units: units, price: price, fee: fee,
                              id: id, date: date, portfolio: &portfolio, usdGross: notional)
            changedValue = true

        case let .limit(side, asset, units, limit, feeRate):
            try check(asset)
            try MoneyMath.quantity(units)
            try MoneyMath.quantity(limit)
            let gross = try MoneyMath.quotedUSD(units, at: limit)
            let fee = try commission(gross, feeRate)
            let reserved = side == .buy ? try MoneyMath.add(gross, fee) : units
            if side == .buy {
                guard try portfolio.freeCash() >= reserved else { throw SimulationError.insufficientCash }
            } else {
                guard try portfolio.freeUnits(asset) >= units else { throw SimulationError.insufficientAsset }
            }
            portfolio.orders.append(.init(id: id, date: date, side: side, asset: asset, units: units,
                                          limit: limit, feeRate: feeRate, reserved: reserved))

        case let .cancel(orderID):
            guard let order = portfolio.orders.firstIndex(where: { $0.id == orderID && $0.status == .open })
            else { throw SimulationError.missingRecord }
            portfolio.orders[order].status = .cancelled
            portfolio.orders[order].closedAt = date

        case let .swap(source, target, units, rate):
            guard source != target else { throw SimulationError.invalidPair }
            try MoneyMath.quantity(units)
            try requireUnits(units, source, portfolio)
            let gross = try MoneyMath.quotedUSD(units, at: quote(source, in: execution))
            let fee = try commission(gross, rate)
            let net = try MoneyMath.subtract(gross, fee)
            let received = try MoneyMath.divide(net, quote(target, in: execution))
            try MoneyMath.quantity(received)
            let basis = try remove(units, asset: source, from: &portfolio)
            try add(received, basis: net, asset: target, to: &portfolio)
            entry = Entry(id: id, date: date, kind: .swap, asset: source, amount: units, usd: gross, fee: fee,
                          profit: try MoneyMath.subtract(net, basis), counterAsset: target, counterAmount: received)
            changedValue = true

        case let .transfer(receive, asset, units, label):
            let price = try quote(asset, in: execution)
            try MoneyMath.quantity(units)
            let value = try MoneyMath.quotedUSD(units, at: price)
            if receive {
                try add(units, basis: value, asset: asset, to: &portfolio)
            } else {
                try requireUnits(units, asset, portfolio)
                _ = try remove(units, asset: asset, from: &portfolio)
            }
            entry = Entry(id: id, date: date, kind: receive ? .receive : .send, asset: asset, amount: units, usd: value,
                          note: label, externalFlow: receive ? value : -value)
            changedValue = true

        case let .registerQR(request, previous):
            guard request.recipient == portfolio.id, request.isValid,
                  !ledger.operationIDs.contains(request.id) else { throw SimulationError.invalidAmount }
            var requests = ledger.localPaymentRequests ?? [:]
            guard requests[request.id] == nil else { throw SimulationError.duplicate }
            if let previous, requests[previous]?.recipient == portfolio.id { requests[previous] = nil }
            requests[request.id] = request
            ledger.localPaymentRequests = requests

        case let .payQR(requestID, _):
            guard !original.operationIDs.contains(requestID) else { throw SimulationError.duplicate }
            guard let request = ledger.localPaymentRequests?[requestID], request.isValid,
                  let recipientIndex = ledger.portfolios.firstIndex(where: { $0.id == request.recipient }),
                  recipientIndex != index else { throw SimulationError.missingRecord }
            try requireUnits(request.units, request.asset, portfolio)
            let value = try MoneyMath.quotedUSD(request.units, at: quote(request.asset, in: execution))
            let basis = try remove(request.units, asset: request.asset, from: &portfolio)
            var recipient = ledger.portfolios[recipientIndex]
            try add(request.units, basis: basis, asset: request.asset, to: &recipient)
            let receiptID = UUID()
            guard ledger.operationIDs.insert(requestID).inserted, ledger.operationIDs.insert(receiptID).inserted
            else { throw SimulationError.duplicate }
            entry = Entry(id: id, date: date, kind: .qrPayment, asset: request.asset, amount: request.units,
                          usd: value, note: recipient.name, reference: requestID, externalFlow: -value)
            recipient.entries.append(Entry(id: receiptID, date: date, kind: .receive, asset: request.asset,
                                           amount: request.units, usd: value, note: portfolio.name, reference: requestID,
                                           externalFlow: value))
            recipient.observe(prices: prices, at: date, force: true)
            ledger.portfolios[recipientIndex] = recipient
            ledger.localPaymentRequests?[requestID] = nil
            changedValue = true

        case let .deposit(amount):
            try MoneyMath.quantity(amount)
            portfolio.cash = try MoneyMath.add(portfolio.cash, amount)
            entry = Entry(id: id, date: date, kind: .deposit, asset: "USD", amount: amount, usd: amount, externalFlow: amount)
            changedValue = true

        case let .setCash(amount):
            try MoneyMath.nonnegative(amount)
            let delta = try MoneyMath.subtract(amount, portfolio.cash)
            portfolio.cash = amount
            guard try portfolio.freeCash() >= 0 else { throw SimulationError.insufficientCash }
            entry = Entry(id: id, date: date, kind: .adjustment, asset: "USD", amount: abs(delta), usd: abs(delta), externalFlow: delta)
            changedValue = true

        case let .setPosition(asset, units, average):
            try check(asset)
            try MoneyMath.nonnegative(units)
            try MoneyMath.nonnegative(average)
            let delta = try MoneyMath.subtract(units, portfolio.positions[asset]?.units ?? 0)
            let flow = try prices[asset].map { try MoneyMath.multiply(delta, $0) }
            portfolio.positions[asset] = units == 0 ? nil : Position(units: units, basis: try MoneyMath.multiply(units, average))
            guard try portfolio.freeUnits(asset) >= 0 else { throw SimulationError.reservedAsset }
            entry = Entry(id: id, date: date, kind: .adjustment, asset: asset, amount: abs(delta),
                          usd: flow.map { abs($0) }, externalFlow: flow ?? 0,
                          valuationUnavailable: delta != 0 && flow == nil ? true : nil)
            changedValue = true

        case let .createPortfolio(name, cash):
            try MoneyMath.nonnegative(cash)
            var new = Portfolio(name: try validName(name), createdAt: date, cash: cash)
            new.observe(prices: [:], at: date, force: true)
            ledger.portfolios.append(new)
            ledger.selected = new.id

        case let .selectPortfolio(id):
            guard ledger.portfolios.contains(where: { $0.id == id }) else { throw SimulationError.missingRecord }
            ledger.selected = id

        case .resetPortfolio:
            portfolio = Portfolio(id: portfolio.id, name: portfolio.name, createdAt: date, cash: 0)
            ledger.cards.removeAll { $0.owner == portfolio.id }
            ledger.localPaymentRequests = ledger.localPaymentRequests?.filter { $0.value.recipient != portfolio.id }
            changedValue = true

        case let .createCard(tier, name, limit, design):
            if let limit { try MoneyMath.quantity(limit) }
            guard design?.isValid ?? true else { throw SimulationError.invalidBackup }
            ledger.cards.append(VirtualCard(owner: portfolio.id, tier: tier, name: try validName(name), limit: limit, design: design))

        case let .configureCard(card, name, limit, tier, design):
            if let limit { try MoneyMath.quantity(limit) }
            guard design?.isValid ?? true else { throw SimulationError.invalidBackup }
            let cardIndex = try findCard(card, in: ledger)
            ledger.cards[cardIndex].name = try validName(name)
            ledger.cards[cardIndex].limit = limit
            if let tier { ledger.cards[cardIndex].tier = tier }
            if let design { ledger.cards[cardIndex].design = design }

        case let .freezeCard(card):
            let cardIndex = try findCard(card, in: ledger)
            ledger.cards[cardIndex].frozen.toggle()

        case let .setPrimaryCard(card):
            _ = try findCard(card, in: ledger)
            portfolio.primaryCardID = card

        case let .deleteCard(card):
            let cardIndex = try findCard(card, in: ledger)
            guard ledger.cards[cardIndex].balance == 0 else { throw SimulationError.cardHasBalance }
            ledger.cards.remove(at: cardIndex)
            if portfolio.primaryCardID == card { portfolio.primaryCardID = nil }

        case let .moveCardFunds(card, amount, toCard):
            try MoneyMath.quantity(amount)
            let cardIndex = try findCard(card, in: ledger)
            let balance = ledger.cards[cardIndex].balance
            if toCard {
                guard !ledger.cards[cardIndex].frozen else { throw SimulationError.cardFrozen }
                guard try portfolio.freeCash() >= amount else { throw SimulationError.insufficientCash }
            } else {
                guard balance >= amount else { throw SimulationError.insufficientCash }
            }
            let flow = toCard ? -amount : amount
            portfolio.cash = try MoneyMath.add(portfolio.cash, flow)
            ledger.cards[cardIndex].balance = try MoneyMath.subtract(balance, flow)
            entry = Entry(id: id, date: date, kind: toCard ? .cardTopUp : .cardReturn, asset: "USD", amount: amount,
                          usd: amount, cardID: card, externalFlow: flow)
            changedValue = true

        case let .pay(card, amount, merchant, subscription):
            try MoneyMath.quantity(amount)
            let cardIndex = try findCard(card, in: ledger)
            let record = ledger.cards[cardIndex]
            guard !record.frozen else { throw SimulationError.cardFrozen }
            if let limit = record.limit, amount > limit { throw SimulationError.cardLimit }
            guard record.balance >= amount else { throw SimulationError.insufficientCash }
            ledger.cards[cardIndex].balance = try MoneyMath.subtract(record.balance, amount)
            entry = Entry(id: id, date: date, kind: .cardPayment, asset: "USD", amount: amount, usd: amount,
                          note: try validName(merchant), cardID: card, cardSubscription: subscription ? true : nil)

        case let .refund(card, paymentID):
            let cardIndex = try findCard(card, in: ledger)
            guard let payment = portfolio.entries.first(where: { $0.id == paymentID && $0.cardID == card && $0.kind == .cardPayment })
            else { throw SimulationError.missingRecord }
            guard !portfolio.entries.contains(where: { $0.kind == .refund && $0.reference == paymentID })
            else { throw SimulationError.alreadyRefunded }
            ledger.cards[cardIndex].balance = try MoneyMath.add(ledger.cards[cardIndex].balance, payment.amount)
            entry = Entry(id: id, date: date, kind: .refund, asset: "USD", amount: payment.amount, usd: payment.amount,
                          note: payment.note, cardID: card, reference: paymentID, cardSubscription: payment.cardSubscription)
        }

        if let entry { portfolio.entries.append(entry) }
        if changedValue { portfolio.observe(prices: prices, at: date, force: true) }
        ledger.portfolios[index] = portfolio
        return ledger
    }

    static func settle(_ original: Ledger, execution: [String: Decimal], prices: [String: Decimal], at date: Date) throws -> Ledger {
        var ledger = original
        for index in ledger.portfolios.indices {
            var portfolio = ledger.portfolios[index]
            for orderIndex in portfolio.orders.indices {
                let order = portfolio.orders[orderIndex]
                guard order.status == .open, let price = execution[order.asset], price > 0,
                      order.side == .buy ? price <= order.limit : price >= order.limit else { continue }
                var candidate = portfolio
                candidate.orders[orderIndex].status = .filled
                candidate.orders[orderIndex].closedAt = date
                candidate.orders[orderIndex].filledPrice = price
                var entry = try trade(order.side, asset: order.asset, units: order.units, price: price, fee: order.feeRate,
                                      id: order.id, date: date, portfolio: &candidate)
                entry.availableCashAfterFill = try candidate.freeCash()
                candidate.entries.append(entry)
                candidate.observe(prices: prices, at: date, force: true)
                portfolio = candidate
            }
            portfolio.observe(prices: prices, at: date)
            ledger.portfolios[index] = portfolio
        }
        return ledger
    }

    private static func trade(_ side: OrderSide, asset: String, units: Decimal, price: Decimal, fee rate: Decimal,
                              id: UUID, date: Date, portfolio: inout Portfolio, usdGross: Decimal? = nil) throws -> Entry {
        try check(asset)
        try MoneyMath.quantity(units)
        let gross = try usdGross ?? MoneyMath.quotedUSD(units, at: price)
        let fee = try commission(gross, rate)
        if side == .buy {
            let total = try MoneyMath.add(gross, fee)
            guard try portfolio.freeCash() >= total else { throw SimulationError.insufficientCash }
            portfolio.cash = try MoneyMath.subtract(portfolio.cash, total)
            try add(units, basis: total, asset: asset, to: &portfolio)
            return Entry(id: id, date: date, kind: .buy, asset: asset, amount: units, usd: gross, fee: fee)
        }
        try requireUnits(units, asset, portfolio)
        let net = try MoneyMath.subtract(gross, fee)
        let basis = try remove(units, asset: asset, from: &portfolio)
        portfolio.cash = try MoneyMath.add(portfolio.cash, net)
        return Entry(id: id, date: date, kind: .sell, asset: asset, amount: units, usd: gross, fee: fee,
                     profit: try MoneyMath.subtract(net, basis))
    }

    private static func commission(_ gross: Decimal, _ rate: Decimal) throws -> Decimal {
        guard !rate.isNaN, rate >= 0, rate < 1 else { throw SimulationError.invalidAmount }
        return try MoneyMath.multiply(gross, rate)
    }

    private static func add(_ units: Decimal, basis: Decimal, asset: String, to portfolio: inout Portfolio) throws {
        let old = portfolio.positions[asset] ?? Position(units: 0, basis: 0)
        portfolio.positions[asset] = Position(units: try MoneyMath.add(old.units, units),
                                             basis: try MoneyMath.add(old.basis, basis))
    }

    private static func remove(_ units: Decimal, asset: String, from portfolio: inout Portfolio) throws -> Decimal {
        guard let old = portfolio.positions[asset] else { throw SimulationError.insufficientAsset }
        if units == old.units {
            portfolio.positions[asset] = nil
            return old.basis
        }
        // Round the allocated basis at a predictable USD scale and leave the remainder with the position.
        let ratio = MoneyMath.round(try MoneyMath.divide(units, old.units), scale: 16)
        let allocation = min(old.basis, MoneyMath.round(try MoneyMath.multiply(old.basis, ratio), scale: 12))
        portfolio.positions[asset] = Position(units: try MoneyMath.subtract(old.units, units),
                                              basis: try MoneyMath.subtract(old.basis, allocation))
        return allocation
    }

    private static func check(_ asset: String) throws {
        guard Asset.ids.contains(asset) else { throw SimulationError.invalidPair }
    }

    private static func quote(_ asset: String, in prices: [String: Decimal]) throws -> Decimal {
        try check(asset)
        guard let price = prices[asset], !price.isNaN, price > 0 else { throw SimulationError.missingQuote }
        return price
    }

    private static func requireUnits(_ units: Decimal, _ asset: String, _ portfolio: Portfolio) throws {
        guard try portfolio.freeUnits(asset) >= units else { throw SimulationError.insufficientAsset }
    }

    private static func validName(_ raw: String) throws -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw SimulationError.invalidName }
        return name
    }

    private static func findCard(_ id: UUID, in ledger: Ledger) throws -> Int {
        guard let index = ledger.cards.firstIndex(where: { $0.id == id && $0.owner == ledger.selected })
        else { throw SimulationError.missingRecord }
        return index
    }
}
