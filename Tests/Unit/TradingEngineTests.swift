import XCTest
@testable import Veltrix

final class TradingEngineTests: XCTestCase {
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

    func testDailyPerformanceExcludesDepositsAndVirtualTransfers() throws {
        let original = Ledger.fresh(cash: 1_000, date: start)
        let deposited = try TradingEngine.apply(.deposit(2_000), to: original, at: start.addingTimeInterval(5))
        let bought = try TradingEngine.apply(.market(.buy, btc, 1, 0), to: deposited, at: start.addingTimeInterval(10),
                                             prices: [btc: 100], execution: [btc: 100])
        let daily = try XCTUnwrap(bought.portfolios[0].daily(now: start.addingTimeInterval(20), prices: [btc: 150]))
        XCTAssertEqual(daily.value, 50)
        XCTAssertNotNil(daily.percent)
    }

    func testFiatConversionDecimalAndCurrencyCoverage() throws {
        let rates = ["JPY": FXRate(quote: "JPY", date: "2026-03-05", rate: decimal("153.38"))]
        XCTAssertEqual(try Fiat.convert(decimal("125.50"), currency: "JPY", rates: rates), decimal("19249.19"))
        XCTAssertEqual(try Fiat.convert(123, currency: "USD", rates: [:]), 123)
        XCTAssertThrowsError(try Fiat.convert(123, currency: "RUB", rates: rates))
        XCTAssertGreaterThan(Set(Fiat.currencies).count, 50)
        XCTAssertEqual(Asset.ids.count, 30)
        XCTAssertEqual(Set(KrakenSymbols.pairs.keys), Set(Asset.catalog.map(\.ticker)))
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
