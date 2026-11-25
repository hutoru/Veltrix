import XCTest

final class VeltrixUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    func testDepositThroughReviewAndSeeItInActivity() {
        let app = launch()
        app.buttons["trade.deposit"].tap()
        let amount = app.textFields["trade.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.tap()
        amount.typeText("100")
        if !app.buttons["trade.review"].isHittable { app.swipeUp() }
        app.buttons["trade.review"].tap()
        app.buttons["trade.confirm"].tap()
        XCTAssertTrue(app.staticTexts["trade.saved"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.buttons["tab.activity"].tap()
        XCTAssertTrue(app.staticTexts["Deposit"].waitForExistence(timeout: 5))
    }

    func testMarketSearchAndNativeDetail() {
        let app = launch()
        app.buttons["tab.markets"].tap()
        let search = app.textFields["markets.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Bitcoin")
        let coin = app.buttons["market.BTC"]
        XCTAssertTrue(coin.waitForExistence(timeout: 5))
        coin.tap()
        XCTAssertTrue(app.staticTexts["Price history"].waitForExistence(timeout: 5))
    }

    func testCreateCardAndHideItsBalanceThroughSettings() {
        let app = launch()
        app.buttons["tab.cards"].tap()
        app.buttons["card.create"].tap()
        XCTAssertTrue(app.buttons["card.confirm"].waitForExistence(timeout: 5))
        app.buttons["card.confirm"].tap()
        let card = app.buttons["card.face"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertEqual(card.value as? String, "$0.00")
        app.buttons["tab.settings"].tap()
        let toggle = app.switches["Hide balances"]
        if !toggle.isHittable { app.swipeUp() }
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()
        app.buttons["tab.cards"].tap()
        XCTAssertEqual(card.value as? String, "••••••")
    }
}
