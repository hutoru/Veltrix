import XCTest

final class VeltrixUITests: XCTestCase {
    private func launch(_ arguments: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchArguments += arguments
        app.launchEnvironment["VELTRIX_XCUITEST_OHLC"] = MarketFixture.bitcoinOHLC
        app.launch()
        return app
    }

    func testDepositThroughReviewAndSeeItInActivity() {
        let app = launch()
        capture(app, name: "Home")
        let more = app.buttons["trade.more"]
        if !more.isHittable { app.swipeUp() }
        more.tap()
        app.buttons["Deposit"].tap()
        XCTAssertTrue(app.staticTexts["trade.amount"].waitForExistence(timeout: 5))
        capture(app, name: "Deposit")
        app.buttons["keypad.1"].tap()
        app.buttons["keypad.0"].tap()
        app.buttons["keypad.0"].tap()
        if !app.buttons["trade.review"].isHittable { app.swipeUp() }
        app.buttons["trade.review"].tap()
        XCTAssertTrue(app.staticTexts["Local operation"].exists)
        capture(app, name: "Review Order")
        app.buttons["trade.confirm"].tap()
        XCTAssertTrue(app.staticTexts["trade.saved"].waitForExistence(timeout: 5))
        capture(app, name: "Operation Saved")
        app.buttons["Done"].tap()
        app.buttons["Notifications"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["activity.deposit"].waitForExistence(timeout: 5))
        capture(app, name: "Notifications")
        app.navigationBars["Notifications"].buttons.element(boundBy: 0).tap()
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
        capture(app, name: "Explore")
        search.tap()
        search.typeText("Bitcoin")
        let coin = app.buttons["market.BTC"]
        XCTAssertTrue(coin.waitForExistence(timeout: 5))
        capture(app, name: "Market search")
        coin.tap()
        XCTAssertTrue(app.staticTexts["Price history"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["Historical chart"].firstMatch.waitForExistence(timeout: 5))
        capture(app, name: "Asset Details")
    }

    func testCreateCardAndHideItsBalanceThroughSettings() {
        let app = launch()
        app.buttons["tab.profile"].tap()
        capture(app, name: "Profile")
        app.buttons["profile.cards"].tap()
        let create = app.buttons["card.create"]
        XCTAssertTrue(create.waitForExistence(timeout: 5), app.debugDescription)
        create.tap()
        XCTAssertTrue(app.buttons["card.confirm"].waitForExistence(timeout: 5))
        capture(app, name: "Card Studio")
        app.buttons["card.confirm"].tap()
        let card = app.buttons["card.face"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertEqual(card.value as? String, "$0.00")
        capture(app, name: "Cards")
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
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["profile.cards"].tap()
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

    func testTradingFormsShareTheCustomKeypadAndDiscloseOnReview() {
        let app = launch()
        for (action, unit) in [("Buy", "USD"), ("Sell", "BTC"), ("Swap", "BTC")] {
            app.buttons["tab.trade"].tap()
            app.buttons[action].tap()
            let amount = app.staticTexts["trade.amount"]
            XCTAssertTrue(amount.waitForExistence(timeout: 5))
            capture(app, name: action)
            app.buttons["keypad.1"].tap()
            app.buttons["keypad.2"].tap()
            app.buttons["keypad.delete"].tap()
            XCTAssertEqual(amount.label, "1 " + unit)
            XCTAssertFalse(app.keyboards.firstMatch.exists)

            if action == "Buy" {
                app.buttons["Limit"].tap()
                let price = app.textFields["Limit price (USD)"]
                price.tap()
                price.typeText("100")
                if !app.buttons["trade.review"].isHittable { app.swipeUp() }
                app.buttons["trade.review"].tap()
                XCTAssertTrue(app.staticTexts["Local operation"].waitForExistence(timeout: 5))
                app.buttons["Edit"].tap()
            }
            app.buttons["Close"].tap()
        }
    }

    func testLaunchAndUnlockWithPIN() {
        let app = launch(["--capture-launch", "--locked-fixture"])
        capture(app, name: "Splash")
        XCTAssertTrue(app.staticTexts["Welcome back"].waitForExistence(timeout: 8))
        capture(app, name: "Lock Screen")
        for digit in ["1", "2", "3", "4"] { app.buttons["keypad." + digit].tap() }
        app.buttons["Unlock"].tap()
        XCTAssertTrue(app.staticTexts["Incorrect PIN"].waitForExistence(timeout: 5))
        for digit in ["2", "4", "6", "8"] { app.buttons["keypad." + digit].tap() }
        app.buttons["Unlock"].tap()
        XCTAssertTrue(app.buttons["tab.portfolio"].waitForExistence(timeout: 5))
    }

    func testQRScannerOpensAndCanBeDismissed() {
        let app = launch()
        app.buttons["Scan QR code"].tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 2) { allow.tap() }
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5))
        capture(app, name: "QR Scanner")
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Scan QR code"].waitForExistence(timeout: 5))
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
