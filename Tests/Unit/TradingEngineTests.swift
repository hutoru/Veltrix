import XCTest
@testable import Veltrix

final class TradingEngineTests: XCTestCase {
    func testCurrencySymbolPlacementAndLocale() throws {
        let amount = try XCTUnwrap(Decimal(string: "20520.76"))
        let english = Locale(identifier: "en_US")
        let russian = Locale(identifier: "ru_RU")
        func normalize(_ value: String) -> String {
            value.replacingOccurrences(of: "\u{00A0}", with: " ")
                .replacingOccurrences(of: "\u{202F}", with: " ")
        }
        XCTAssertEqual(Display.money(amount, currency: "USD", digits: 2, locale: english), "$20,520.76")
        XCTAssertEqual(normalize(Display.money(amount, currency: "EUR", digits: 2, locale: russian)), "20 520,76 €")
        XCTAssertEqual(normalize(Display.money(amount, currency: "RUB", digits: 2, locale: russian)), "20 520,76 ₽")
        XCTAssertEqual(normalize(Display.money(-amount, currency: "USD", digits: 2, locale: russian)), "−$20 520,76")
    }

    private let btc = "bitcoin"
    private let eth = "ethereum"
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testMarketPurchaseSaleFeesAndProfit() throws {
        let initial = Ledger.fresh(cash: 1_000, date: start)
        let bought = try execute(.market(.buy, btc, 2, decimal("0.01")), initial, bitcoin: 100)
        let position = bought.portfolios[0].positions[btc]
        XCTAssertEqual(position?.units, 2)
        XCTAssertEqual(position?.average, 101)
        XCTAssertEqual(bought.portfolios[0].cash, 798)

        let sold = try execute(.market(.sell, btc, 1, decimal("0.01")), bought, bitcoin: 150)
        XCTAssertEqual(sold.portfolios[0].cash, decimal("946.5"))
        XCTAssertEqual(sold.portfolios[0].entries.last?.fee, decimal("1.5"))
        XCTAssertEqual(try sold.portfolios[0].realized(), decimal("47.5"))
        XCTAssertEqual(try sold.portfolios[0].unrealized(prices: [btc: 150]), 49)
        XCTAssertThrowsError(try execute(.market(.sell, btc, 2, 0), sold, bitcoin: 150)) {
            XCTAssertEqual($0 as? SimulationError, .insufficientAsset)
        }
    }

    func testSwapAccountsForBothAssetsAndSingleFee() throws {
        let initial = try execute(.market(.buy, btc, 2, 0), .fresh(cash: 1_000, date: start), bitcoin: 100)
        let swapped = try execute(.swap(btc, eth, 1, decimal("0.02")), initial, bitcoin: 200)
        let portfolio = swapped.portfolios[0]
        XCTAssertEqual(portfolio.cash, 800)
        XCTAssertEqual(portfolio.positions[btc]?.units, 1)
        XCTAssertEqual(portfolio.positions[eth]?.units, decimal("3.92"))
        XCTAssertEqual(portfolio.positions[eth]?.basis, 196)
        XCTAssertEqual(try portfolio.realized(), 96)
        XCTAssertEqual(portfolio.entries.last?.fee, 4)
        XCTAssertThrowsError(try execute(.swap(btc, btc, 1, 0), swapped, bitcoin: 200))
    }

    func testMarketNotionalUsesConfirmationQuoteAndPreservesExactCashDelta() throws {
        let ledger = Ledger.fresh(cash: 1_000, date: start)
        let bought = try execute(.marketNotional(.buy, btc, 100, decimal("0.01")), ledger, bitcoin: decimal("63.17"))
        XCTAssertEqual(bought.portfolios[0].cash, 899)
        XCTAssertEqual(bought.portfolios[0].entries.last?.usd, 100)
        let units = try XCTUnwrap(bought.portfolios[0].positions[btc]?.units)
        XCTAssertEqual(units, try MoneyMath.divide(100, decimal("63.17")))
    }

    func testSmallFiatBuyCanBeValuedAndSoldByItsExactCoinQuantity() throws {
        let ledger = Ledger.fresh(cash: 10_000, date: start)
        let price = decimal("59617.9")
        let fee = decimal("0.001")
        let bought = try execute(.marketNotional(.buy, btc, 1, fee), ledger, bitcoin: price)
        let position = try XCTUnwrap(bought.portfolios[0].positions[btc])
        XCTAssertEqual(position.units, try MoneyMath.divide(1, price))
        XCTAssertEqual(MoneyMath.round(try bought.portfolios[0].value(prices: [btc: price]), scale: 3), decimal("9999.999"))
        XCTAssertEqual(MoneyMath.round(try bought.portfolios[0].unrealized(prices: [btc: price]), scale: 3), -fee)
        let sold = try execute(.market(.sell, btc, position.units, fee), bought, bitcoin: price)
        XCTAssertNil(sold.portfolios[0].positions[btc])
        XCTAssertEqual(MoneyMath.round(sold.portfolios[0].cash, scale: 3), decimal("9999.998"))
        XCTAssertEqual(MoneyMath.round(try sold.portfolios[0].realized(), scale: 3), decimal("-0.002"))
    }

    func testQuotedUSDAmountStaysWithinExistingLimitReservations() throws {
        let previousGross = decimal("1.00000000000000009")
        XCTAssertEqual(try MoneyMath.quotedUSD(1, at: previousGross), 1)
        let tiny = decimal("0.000000000000000001")
        XCTAssertEqual(try MoneyMath.quotedUSD(1, at: tiny), tiny)
    }

    func testHighPrecisionLimitCanReopenAndAlsoAcceptsLegacyReserve() throws {
        let price = decimal("1.00000000000000009")
        var order = try execute(.limit(.buy, btc, 1, price, 0), .fresh(cash: 100, date: start), bitcoin: 2)
        XCTAssertEqual(order.portfolios[0].orders[0].reserved, 1)
        XCTAssertEqual(try SimulationBackup.load(SimulationBackup.export(order)), order)

        order.portfolios[0].orders[0].reserved = price
        XCTAssertEqual(try SimulationBackup.load(SimulationBackup.export(order)), order)
        order.portfolios[0].orders[0].reserved = 2
        XCTAssertThrowsError(try SimulationBackup.load(SimulationBackup.export(order)))
    }

    func testLocalQRPaymentConservesPositionsAndCannotBeReplayed() throws {
        let original = Ledger.fresh(cash: 1_000, date: start)
        let payer = original.selected
        let bought = try execute(.market(.buy, btc, 2, 0), original, bitcoin: 100)
        let two = try execute(.createPortfolio("Recipient", 500), bought, bitcoin: 100)
        let request = LocalPaymentRequest(id: UUID(), recipient: two.selected, asset: btc, network: .bitcoin, units: 1)
        XCTAssertEqual(LocalPaymentRequest.identifier(from: request.payload), request.id)
        XCTAssertNil(LocalPaymentRequest.identifier(from: "bitcoin:" + request.id.uuidString))
        let registered = try execute(.registerQR(request, replacing: nil), two, bitcoin: 100)
        let reloaded = try SimulationBackup.load(SimulationBackup.export(registered))
        XCTAssertEqual(reloaded.localPaymentRequests?[request.id], request)
        XCTAssertThrowsError(try execute(.payQR(request.id, from: two.selected), reloaded, bitcoin: 100))
        let paid = try execute(.payQR(request.id, from: payer), reloaded, bitcoin: 100)
        XCTAssertEqual(paid.selected, two.selected)
        XCTAssertEqual(paid.portfolios.map { $0.positions[btc]?.units }, [1, 1])
        XCTAssertEqual(paid.portfolios.map { $0.positions[btc]?.basis }, [100, 100])
        XCTAssertEqual(paid.portfolios[0].entries.last?.kind, .qrPayment)
        XCTAssertEqual(paid.portfolios[1].entries.last?.kind, .receive)
        XCTAssertNil(paid.localPaymentRequests?[request.id])
        XCTAssertEqual(try SimulationBackup.load(SimulationBackup.export(paid)), paid)
        XCTAssertThrowsError(try execute(.payQR(request.id, from: payer), paid, bitcoin: 100)) {
            XCTAssertEqual($0 as? SimulationError, .duplicate)
        }
    }

    func testLocalQRInsufficientBalanceDoesNotConsumeRequestAndRefreshInvalidatesPreviousCode() throws {
        let original = Ledger.fresh(date: start)
        let two = try execute(.createPortfolio("Recipient", 0), original, bitcoin: 100)
        let request = LocalPaymentRequest(id: UUID(), recipient: two.selected, asset: btc, network: .bitcoin, units: 1)
        let registered = try execute(.registerQR(request, replacing: nil), two, bitcoin: 100)
        XCTAssertThrowsError(try execute(.payQR(request.id, from: original.selected), registered, bitcoin: 100)) {
            XCTAssertEqual($0 as? SimulationError, .insufficientAsset)
        }
        let next = LocalPaymentRequest(id: UUID(), recipient: two.selected, asset: btc, network: .bitcoin, units: 2)
        let refreshed = try execute(.registerQR(next, replacing: request.id), registered, bitcoin: 100)
        XCTAssertNil(refreshed.localPaymentRequests?[request.id])
        XCTAssertEqual(refreshed.localPaymentRequests?[next.id], next)
    }

    func testPerformanceHistoryExcludesDepositsAndManualAdjustments() throws {
        let original = Ledger.fresh(cash: 1_000, date: start)
        let deposit = try TradingEngine.apply(.deposit(500), to: original, at: start.addingTimeInterval(1))
        var bought = try TradingEngine.apply(.market(.buy, btc, 1, 0), to: deposit, at: start.addingTimeInterval(2),
                                             prices: [btc: 100], execution: [btc: 100])
        bought.portfolios[0].observe(prices: [btc: 140], at: start.addingTimeInterval(3), force: true)
        let adjusted = try TradingEngine.apply(.setCash(1_600), to: bought, at: start.addingTimeInterval(4), prices: [btc: 140])
        XCTAssertEqual(adjusted.portfolios[0].performanceHistory(since: start).map(\.value), [0, 0, 0, 40, 40])
    }

    func testOfflinePositionEditRecordsUnitsWithoutFabricatingValue() throws {
        let ledger = Ledger.fresh(cash: 100, date: start)
        let edited = try TradingEngine.apply(.setPosition(btc, 1, 25), to: ledger, at: start.addingTimeInterval(1))
        XCTAssertEqual(edited.portfolios[0].positions[btc]?.basis, 25)
        XCTAssertEqual(edited.portfolios[0].entries.last?.valuationUnavailable, true)
        XCTAssertEqual(edited.portfolios[0].history.count, 1)
        XCTAssertNil(try edited.portfolios[0].daily(now: start.addingTimeInterval(2), prices: [btc: 50]))
    }

    func testLimitReservationsEligibilityFillAndCancellation() throws {
        let original = Ledger.fresh(cash: 500, date: start)
        let ordered = try execute(.limit(.buy, btc, 2, 100, decimal("0.01")), original, bitcoin: 110)
        let order = try XCTUnwrap(ordered.portfolios[0].orders.first)
        XCTAssertEqual(try ordered.portfolios[0].freeCash(), 298)
        XCTAssertThrowsError(try execute(.market(.buy, btc, 3, 0), ordered, bitcoin: 110))
        let noFill = try TradingEngine.settle(ordered, execution: [:], prices: [btc: 90], at: start)
        XCTAssertEqual(noFill.portfolios[0].orders.first?.status, .open)

        let cancelled = try execute(.cancel(order.id), ordered, bitcoin: 110)
        XCTAssertEqual(try cancelled.portfolios[0].freeCash(), 500)
        XCTAssertEqual(cancelled.portfolios[0].orders.first?.status, .cancelled)
        let filled = try TradingEngine.settle(ordered, execution: [btc: 90], prices: [btc: 90], at: start.addingTimeInterval(2))
        XCTAssertEqual(filled.portfolios[0].orders.first?.filledPrice, 90)
        XCTAssertEqual(filled.portfolios[0].orders.first?.status, .filled)
        XCTAssertEqual(filled.portfolios[0].entries.first?.id, order.id)
        XCTAssertEqual(filled.portfolios[0].cash, decimal("318.2"))
        XCTAssertEqual(filled.portfolios[0].entries.first?.availableCashAfterFill, decimal("318.2"))
        let second = try TradingEngine.settle(filled, execution: [btc: 88], prices: [btc: 88], at: start.addingTimeInterval(3))
        XCTAssertEqual(second.portfolios[0].entries.count, 1)
        try second.validate(assets: Asset.ids)
    }

    func testLimitSellReservesOnlyItsAssetAndFillsAtBetterPrice() throws {
        let bought = try execute(.market(.buy, btc, 3, 0), .fresh(cash: 3_000, date: start), bitcoin: 100)
        let ordered = try execute(.limit(.sell, btc, 2, 150, 0), bought, bitcoin: 120)
        XCTAssertEqual(try ordered.portfolios[0].freeUnits(btc), 1)
        XCTAssertThrowsError(try execute(.setPosition(btc, 1, 100), ordered, bitcoin: 120))
        let waiting = try TradingEngine.settle(ordered, execution: [btc: 149], prices: [btc: 149], at: start.addingTimeInterval(2))
        XCTAssertEqual(waiting.portfolios[0].orders.first?.status, .open)
        let filled = try TradingEngine.settle(waiting, execution: [btc: 160], prices: [btc: 160], at: start.addingTimeInterval(3))
        XCTAssertEqual(filled.portfolios[0].positions[btc]?.units, 1)
        XCTAssertEqual(try filled.portfolios[0].realized(), 120)
    }

    func testIdempotencyAndLargeBalances() throws {
        let amount = decimal("99999999999999999999999999999999.01")
        let id = UUID()
        let ledger = Ledger.fresh(cash: 0, date: start)
        let updated = try TradingEngine.apply(.deposit(amount), to: ledger, id: id, at: start)
        XCTAssertEqual(updated.portfolios[0].cash, amount)
        XCTAssertEqual(MoneyMath.parse("99999999999999999999999999999999,01", separator: ","), amount)
        XCTAssertNil(MoneyMath.parse("10,0trailing", separator: ","))
        XCTAssertNil(MoneyMath.parse("99999999999999999999999999999999999999999999.01", separator: "."))
        XCTAssertThrowsError(try TradingEngine.apply(.deposit(amount), to: updated, id: id)) {
            XCTAssertEqual($0 as? SimulationError, .duplicate)
        }
    }

    func testDailyPerformanceMatchesHistoryAndCurrentValuation() throws {
        let original = Ledger.fresh(cash: 1_000, date: start)
        let deposited = try TradingEngine.apply(.deposit(2_000), to: original, at: start.addingTimeInterval(5))
        let bought = try TradingEngine.apply(.market(.buy, btc, 1, 0), to: deposited, at: start.addingTimeInterval(10),
                                             prices: [btc: 100], execution: [btc: 100])
        let daily = try XCTUnwrap(bought.portfolios[0].daily(now: start.addingTimeInterval(20), prices: [btc: 150]))
        XCTAssertEqual(daily.value, 50)
        XCTAssertEqual(daily.percent, 2)
        let series = bought.portfolios[0].performance(since: start, until: start.addingTimeInterval(20), liveValue: 3_050)
        XCTAssertEqual(series.points.last?.value, daily.value)
        XCTAssertEqual(series.change?.percent, daily.percent)
    }

    func testFiatConversionDecimalAndCurrencyCoverage() throws {
        let rates = ["JPY": FXRate(quote: "JPY", date: "2026-03-05", rate: decimal("153.38"))]
        XCTAssertEqual(try Fiat.convert(decimal("125.50"), currency: "JPY", rates: rates), decimal("19249.19"))
        XCTAssertEqual(try Fiat.convert(123, currency: "USD", rates: [:]), 123)
        XCTAssertThrowsError(try Fiat.convert(123, currency: "RUB", rates: rates))
        XCTAssertGreaterThan(Set(Fiat.currencies).count, 50)
    }

    func testCatalogKeepsExchangeCryptoPairsAndTokenizedStocksDistinct() {
        XCTAssertEqual(Asset.cryptoCatalog.count, 30)
        XCTAssertEqual(Set(KrakenSymbols.pairs.keys), Set(Asset.cryptoCatalog.map(\.ticker)))
        XCTAssertEqual(Asset.ids.count, Asset.catalog.count)
        XCTAssertEqual(Set(Asset.tokenizedStocks.map(\.ticker)),
                       ["AAPLx", "NVDAx", "MSFTx", "TSLAx", "AMZNx", "GOOGLx", "METAx"])
        XCTAssertTrue(Asset.tokenizedStocks.allSatisfy(\.isTokenizedStock))
    }

    func testSubscriptionPaymentAndRefundSurviveBackup() throws {
        let initial = Ledger.fresh(cash: 200)
        let created = try execute(.createCard(.classic, "Studio", nil), initial, bitcoin: 100)
        let card = try XCTUnwrap(created.cards.first?.id)
        let funded = try execute(.moveCardFunds(card, 100, toCard: true), created, bitcoin: 100)
        let paid = try execute(.pay(card, 20, "Service", subscription: true), funded, bitcoin: 100)
        let payment = try XCTUnwrap(paid.portfolios.first?.entries.last)
        XCTAssertEqual(payment.cardSubscription, true)
        let refunded = try execute(.refund(card, payment.id), paid, bitcoin: 100)
        let restored = try SimulationBackup.load(SimulationBackup.export(refunded))
        XCTAssertEqual(restored.cards.first?.balance, 100)
        XCTAssertEqual(restored.portfolios.first?.entries.last?.cardSubscription, true)
        XCTAssertEqual(restored.portfolios.first?.entries.last?.reference, payment.id)
    }

    func testCardMoveFreezeLimitPaymentRefundAndOwnership() throws {
        var ledger = try execute(.createCard(.gold, "Test", 100), .fresh(cash: 1_000, date: start), bitcoin: 100)
        let card = try XCTUnwrap(ledger.cards.first?.id)
        ledger = try execute(.moveCardFunds(card, 200, toCard: true), ledger, bitcoin: 100)
        XCTAssertEqual(ledger.portfolios[0].cash, 800)
        XCTAssertEqual(ledger.cards[0].balance, 200)
        XCTAssertThrowsError(try execute(.pay(card, 101, "Cafe"), ledger, bitcoin: 100))
        let frozen = try execute(.freezeCard(card), ledger, bitcoin: 100)
        XCTAssertThrowsError(try execute(.pay(card, 10, "Cafe"), frozen, bitcoin: 100))
        let paid = try execute(.pay(card, 75, "Cafe"), ledger, bitcoin: 100)
        let payment = try XCTUnwrap(paid.portfolios[0].entries.last?.id)
        XCTAssertEqual(paid.cards[0].balance, 125)
        let refunded = try execute(.refund(card, payment), paid, bitcoin: 100)
        XCTAssertEqual(refunded.cards[0].balance, 200)
        XCTAssertThrowsError(try execute(.refund(card, payment), refunded, bitcoin: 100))
        XCTAssertThrowsError(try execute(.deleteCard(card), refunded, bitcoin: 100))
        let switched = try execute(.createPortfolio("Separate", 500), refunded, bitcoin: 100)
        XCTAssertThrowsError(try execute(.pay(card, 5, "Cafe"), switched, bitcoin: 100))
        let returned = try execute(.moveCardFunds(card, 200, toCard: false), refunded, bitcoin: 100)
        let deleted = try execute(.deleteCard(card), returned, bitcoin: 100)
        XCTAssertEqual(deleted.portfolios[0].cash, 1_000)
        XCTAssertEqual(deleted.cards.count, 0)
        XCTAssertEqual(deleted.portfolios[0].entries.count, 4)
    }

    private func execute(_ command: Command, _ ledger: Ledger, bitcoin: Decimal) throws -> Ledger {
        let prices = [btc: bitcoin, eth: 50]
        return try TradingEngine.apply(command, to: ledger, at: start.addingTimeInterval(1), prices: prices, execution: prices)
    }

    private func decimal(_ value: String) -> Decimal {
        Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))!
    }
}
