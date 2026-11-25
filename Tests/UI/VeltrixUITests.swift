import XCTest

final class VeltrixUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    func testDepositThroughReviewAndSeeItInActivity() {
        let app = launch()
        capture(app, name: "Portfolio")
        let more = app.buttons["trade.more"]
        if !more.isHittable { app.swipeUp() }
        more.tap()
        app.buttons["Deposit"].tap()
        XCTAssertTrue(app.staticTexts["trade.amount"].waitForExistence(timeout: 5))
        app.buttons["keypad.1"].tap()
        app.buttons["keypad.0"].tap()
        app.buttons["keypad.0"].tap()
        if !app.buttons["trade.review"].isHittable { app.swipeUp() }
        app.buttons["trade.review"].tap()
        XCTAssertTrue(app.staticTexts["Virtual funds"].exists)
        app.buttons["trade.confirm"].tap()
        XCTAssertTrue(app.staticTexts["trade.saved"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.buttons["tab.activity"].tap()
        XCTAssertTrue(app.staticTexts["Transactions and open orders"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["activity.deposit"].exists)
        capture(app, name: "Activity")
    }

    func testMarketSearchAndNativeDetail() {
        let app = launch()
        app.buttons["tab.markets"].tap()
        let search = app.textFields["markets.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5), app.debugDescription)
        search.tap()
        search.typeText("Bitcoin")
        let coin = app.buttons["market.BTC"]
        XCTAssertTrue(coin.waitForExistence(timeout: 5))
        capture(app, name: "Market search")
        coin.tap()
        XCTAssertTrue(app.staticTexts["Price history"].waitForExistence(timeout: 5))
    }

    func testCreateCardAndHideItsBalanceThroughSettings() {
        let app = launch()
        app.buttons["tab.profile"].tap()
        app.buttons["profile.cards"].tap()
        let create = app.buttons["card.create"]
        XCTAssertTrue(create.waitForExistence(timeout: 5), app.debugDescription)
        create.tap()
        XCTAssertTrue(app.buttons["card.confirm"].waitForExistence(timeout: 5))
        app.buttons["card.confirm"].tap()
        let card = app.buttons["card.face"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertEqual(card.value as? String, "$0.00")
        capture(app, name: "Virtual card")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["profile.settings"].tap()
        let privacyButton = app.buttons["settings.hide"]
        for _ in 0..<3 where !privacyButton.isHittable || privacyButton.frame.midY > app.frame.maxY - 75 {
            app.swipeUp()
        }
        XCTAssertTrue(privacyButton.waitForExistence(timeout: 5))
        capture(app, name: "Settings")
        privacyButton.tap()
        XCTAssertTrue(privacyButton.isSelected)
        app.buttons["tab.cards"].tap()
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "••••••"), object: card)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed)
    }

    func testPortfolioHoldingEditorAndHistory() {
        let app = launch()
        app.buttons["Add holding"].tap()
        XCTAssertTrue(app.textFields["Quantity"].waitForExistence(timeout: 5))
        app.buttons["Close"].tap()
        let history = app.buttons["Portfolio history"]
        for _ in 0..<3 where !history.isHittable || history.frame.midY > app.frame.maxY - 75 {
            app.swipeUp()
        }
        history.tap()
        XCTAssertTrue(app.navigationBars["Portfolio history"].waitForExistence(timeout: 5))
        capture(app, name: "Portfolio history")
        app.buttons["Done"].tap()
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
