import XCTest

final class VeltrixUITests: XCTestCase {
    private func launch(_ arguments: [String] = [], language: String = "en", locale: String = "en_US") -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", "-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        app.launchArguments += arguments
        app.launchEnvironment["UITEST_MODE"] = "1"
        app.launchEnvironment["VELTRIX_XCUITEST_OHLC"] = MarketFixture.bitcoinOHLC
        app.launchEnvironment["VELTRIX_XCUITEST_QUOTES"] = MarketFixture.quotes
        app.launch()
        return app
    }

    func testDepositThroughReviewAndSeeItInActivity() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["portfolio.total"].waitForExistence(timeout: 5))
        capture(app, name: "Home Empty")
        let more = app.buttons["trade.more"]
        if !more.isHittable { app.swipeUp() }
        more.tap()
        app.buttons["Deposit"].tap()
        XCTAssertTrue(app.textFields["trade.amount"].waitForExistence(timeout: 5))
        capture(app, name: "Deposit")
        enterAmount("100", in: app)
        if !app.buttons["trade.review"].isHittable { app.swipeUp() }
        app.buttons["trade.review"].tap()
        XCTAssertTrue(app.staticTexts["trade.review.title"].exists)
        capture(app, name: "Deposit Review")
        app.buttons["trade.confirm"].tap()
        XCTAssertTrue(app.staticTexts["trade.saved"].waitForExistence(timeout: 5))
        capture(app, name: "Deposit Saved")
        app.buttons["Done"].tap()
        app.buttons["Notifications"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["activity.deposit"].waitForExistence(timeout: 5))
        capture(app, name: "Notifications")
        app.navigationBars["Notifications"].buttons.element(boundBy: 0).tap()
        openActivity(in: app)
        XCTAssertTrue(app.staticTexts["Transactions and open orders"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["activity.deposit"].exists)
        capture(app, name: "Activity")
    }

    func testFloatingNavigationOpensGlobalSearch() {
        let app = launch()
        XCTAssertTrue(app.buttons["tab.portfolio"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tab.markets"].isHittable)
        XCTAssertTrue(app.buttons["tab.operations"].isHittable)
        app.buttons["tab.search"].tap()
        let field = app.textFields["global.search"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Bitcoin")
        let result = app.buttons["global.asset.BTC"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        capture(app, name: "Global Search")
        result.tap()
        XCTAssertTrue(app.buttons["asset.buy"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["asset.buy"].isHittable)
        XCTAssertTrue(app.buttons["asset.sell"].isHittable)
    }

    private func openActivity(in app: XCUIApplication) {
        app.buttons["tab.operations"].tap()
        let activity = app.buttons["operations.activity"]
        for _ in 0..<3 where !activity.isHittable || activity.frame.midY > app.frame.maxY - 75 {
            app.swipeUp()
        }
        activity.tap()
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
        XCTAssertFalse(app.buttons["tab.markets"].exists)
        XCTAssertTrue(app.buttons["asset.buy"].isHittable)
        XCTAssertTrue(app.buttons["asset.sell"].isHittable)
        capture(app, name: "Asset Details")
        app.buttons["asset.buy"].tap()
        XCTAssertTrue(app.textFields["trade.amount"].waitForExistence(timeout: 5))
        enterAmount("20", in: app)
        app.buttons["trade.review"].tap()
        app.buttons["trade.confirm"].tap()
        XCTAssertTrue(app.staticTexts["trade.saved"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["asset.sell"].waitForExistence(timeout: 5))
        app.buttons["asset.sell"].tap()
        XCTAssertTrue(app.buttons["25%"].waitForExistence(timeout: 5))
        app.buttons["25%"].tap()
        app.buttons["trade.review"].tap()
        app.buttons["trade.confirm"].tap()
        XCTAssertTrue(app.staticTexts["trade.saved"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
    }

    func testCreateCardAndHideItsBalanceThroughSettings() {
        let app = launch()
        app.buttons["home.profile"].tap()
        XCTAssertTrue(app.buttons["profile.settings"].waitForExistence(timeout: 5))
        capture(app, name: "Profile")
        app.buttons["profile.cards"].tap()
        XCTAssertTrue(app.staticTexts["Card Studio and spending"].waitForExistence(timeout: 5))
        let create = app.buttons["card.create"]
        XCTAssertTrue(create.waitForExistence(timeout: 5), app.debugDescription)
        create.tap()
        XCTAssertTrue(app.buttons["card.confirm"].waitForExistence(timeout: 5))
        capture(app, name: "Card Studio")
        app.buttons["card.catalog"].tap()
        let gold = app.buttons["card.design.gold"]
        XCTAssertTrue(gold.waitForExistence(timeout: 5))
        capture(app, name: "Card Catalog")
        gold.tap()
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
        XCTAssertTrue(app.buttons["home.section.assets"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["home.section.cards"].exists)
        app.buttons["home.section.favorites"].tap()
        XCTAssertTrue(app.staticTexts["No favorites yet"].waitForExistence(timeout: 5))
        app.buttons["home.section.assets"].tap()
        XCTAssertTrue(app.textFields["home.assets.search"].waitForExistence(timeout: 5))
        capture(app, name: "Home Assets")
        app.buttons["Add holding"].tap()
        XCTAssertTrue(app.textFields["Quantity"].waitForExistence(timeout: 5))
        app.buttons["Close"].tap()
        app.buttons["tab.operations"].tap()
        let analytics = app.buttons["operations.analytics"]
        for _ in 0..<3 where !analytics.isHittable || analytics.frame.midY > app.frame.maxY - 75 {
            app.swipeUp()
        }
        analytics.tap()
        XCTAssertTrue(app.navigationBars["Analytics"].waitForExistence(timeout: 5))
        capture(app, name: "Analytics")
    }

    func testTradingUsesNativeDecimalKeyboardAndReviewsQuotes() {
        let app = launch()
        for (action, unit) in [("Buy", "USD"), ("Sell", "BTC"), ("Swap", "BTC")] {
            app.buttons["tab.operations"].tap()
            let actionButton = app.buttons["trade.action." + action.lowercased()]
            XCTAssertTrue(actionButton.waitForExistence(timeout: 5))
            actionButton.tap()
            let amount = app.textFields["trade.amount"]
            XCTAssertTrue(amount.waitForExistence(timeout: 5))
            enterAmount("12", in: app)
            XCTAssertEqual(amount.value as? String, "12")
            XCTAssertEqual(app.staticTexts["trade.amount.unit"].label, unit)

            if action == "Buy" {
                capture(app, name: action)
                app.buttons["Limit"].tap()
                let price = app.textFields["Limit price (USD)"]
                price.tap()
                price.typeText("100")
                dismissKeyboard(in: app)
                if !app.buttons["trade.review"].isHittable { app.swipeUp() }
                app.buttons["trade.review"].tap()
                XCTAssertTrue(app.staticTexts["trade.review.title"].waitForExistence(timeout: 5))
                capture(app, name: "Review Order")
                app.buttons["Edit"].tap()
                app.buttons["Market"].tap()
                if !app.buttons["trade.review"].isHittable { app.swipeUp() }
                app.buttons["trade.review"].tap()
                XCTAssertTrue(app.descendants(matching: .any)["trade.quote.countdown"].exists)
                app.buttons["trade.confirm"].tap()
                XCTAssertTrue(app.staticTexts["trade.saved"].waitForExistence(timeout: 5))
                capture(app, name: "Operation Saved")
                app.buttons["Done"].tap()
                XCTAssertTrue(app.buttons["tab.operations"].waitForExistence(timeout: 5))
                app.buttons["tab.portfolio"].tap()
                XCTAssertTrue(app.staticTexts["Bitcoin"].waitForExistence(timeout: 5))
                XCTAssertEqual(app.staticTexts["portfolio.total"].label, "$9,999.99")
                capture(app, name: "Home")
                continue
            }

            app.buttons["trade.unit"].tap()
            XCTAssertEqual(app.staticTexts["trade.amount.unit"].label, "USD")
            app.buttons[action == "Sell" ? "25%" : "MAX"].tap()
            XCTAssertNotEqual(amount.value as? String, "0")
            if action == "Sell" { XCTAssertEqual(amount.value as? String, "3") }
            capture(app, name: action)
            app.buttons["trade.review"].tap()
            XCTAssertTrue(app.staticTexts["trade.review.title"].waitForExistence(timeout: 5))
            app.buttons["trade.confirm"].tap()
            XCTAssertTrue(app.staticTexts["trade.saved"].waitForExistence(timeout: 5))
            capture(app, name: action + " Saved")
            app.buttons["Done"].tap()
        }
        openActivity(in: app)
        XCTAssertTrue(app.descendants(matching: .any)["activity.swap"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["activity.sell"].exists)
    }

    func testSendRecordsSimulatedTransfer() {
        let app = launch()
        app.buttons["trade.buy"].tap()
        XCTAssertTrue(app.buttons["25%"].waitForExistence(timeout: 5))
        app.buttons["25%"].tap()
        app.buttons["trade.review"].tap()
        app.buttons["trade.confirm"].tap()
        XCTAssertTrue(app.staticTexts["trade.saved"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()

        let send = app.buttons["trade.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        send.tap()
        let recipient = app.textFields["Recipient label"]
        XCTAssertTrue(recipient.waitForExistence(timeout: 5))
        recipient.tap()
        recipient.typeText("Test recipient")
        dismissKeyboard(in: app)
        app.buttons["25%"].tap()
        app.buttons["trade.review"].tap()
        XCTAssertTrue(app.staticTexts["trade.review.title"].waitForExistence(timeout: 5))
        app.buttons["trade.confirm"].tap()
        XCTAssertTrue(app.staticTexts["trade.saved"].waitForExistence(timeout: 5))
        capture(app, name: "Send Saved")
        app.buttons["Done"].tap()
        openActivity(in: app)
        XCTAssertTrue(app.descendants(matching: .any)["activity.send"].waitForExistence(timeout: 5))
    }

    func testLaunchShowsSystemAuthenticationGate() {
        let app = launch(["--capture-launch", "--locked-fixture", "--capture-lock-background"])
        capture(app, name: "Splash")
        XCTAssertTrue(app.staticTexts["Welcome back"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["lock.unlock"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["trade.amount"].exists)
        XCTAssertFalse(app.buttons["tab.portfolio"].exists)
        capture(app, name: "Lock Screen")
        let systemPrompt = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "iPhone Passcode")).firstMatch
        _ = systemPrompt.waitForExistence(timeout: 5)
        capture(app, name: "iOS Device Authentication")
    }

    func testSavedTradeReachesIOSNotificationCenter() {
        let app = launch(["--native-notifications"])
        app.buttons["trade.buy"].tap()
        let quarterBalance = app.buttons["25%"]
        XCTAssertTrue(quarterBalance.waitForExistence(timeout: 5))
        quarterBalance.tap()
        app.buttons["trade.review"].tap()
        app.buttons["trade.confirm"].tap()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }
        XCTAssertTrue(app.staticTexts["trade.saved"].waitForExistence(timeout: 8))
        app.buttons["Done"].tap()
        app.buttons["home.profile"].tap()
        app.buttons["profile.settings"].tap()
        let delivery = app.staticTexts["notifications.delivery"]
        for _ in 0..<6 where !delivery.isHittable { app.swipeUp() }
        let delivered = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Last notification delivered"),
                                                 object: delivery)
        XCTAssertEqual(XCTWaiter.wait(for: [delivered], timeout: 8), .completed, app.debugDescription)
        capture(app, name: "iOS Notification Diagnostics")
    }

    func testSimulatorDisclosureAppearsAtBottomOfSettings() {
        let app = launch()
        let disclosure = app.staticTexts["settings.simulatorDisclosure"]
        XCTAssertFalse(disclosure.exists)
        app.buttons["home.profile"].tap()
        app.buttons["profile.settings"].tap()
        for _ in 0..<9 where !disclosure.isHittable { app.swipeUp() }
        XCTAssertTrue(disclosure.isHittable)
        XCTAssertTrue(disclosure.label.hasPrefix("VELTRIX is a simulator."))
        capture(app, name: "Settings disclosure")
    }

    func testQRScannerOpensAndCanBeDismissed() {
        let app = launch()
        app.buttons["Scan QR code"].tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 2) { allow.tap() }
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Scan QR from Photos"].exists)
        capture(app, name: "QR Scanner")
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Scan QR code"].waitForExistence(timeout: 5))
    }

    func testReceiveCreatesAndRefreshesLocalQRRequest() {
        let app = launch()
        app.buttons["trade.receive"].tap()
        enterAmount("0.01", in: app, fieldID: "receive.amount")
        let generate = app.buttons["receive.generate"]
        generate.tap()
        let qr = app.images["receive.qr"]
        XCTAssertTrue(qr.waitForExistence(timeout: 5))
        let original = app.staticTexts["receive.requestID"]
        XCTAssertTrue(original.exists)
        let requestID = original.label
        XCTAssertNotNil(UUID(uuidString: requestID))
        capture(app, name: "Receive Local QR")
        generate.tap()
        XCTAssertNotEqual(original.label, requestID)
    }

    func testRussianLightThemeAndNativeDecimalInput() {
        let app = launch(["--light-fixture"], language: "ru", locale: "ru_RU")
        XCTAssertTrue(app.buttons["tab.portfolio"].waitForExistence(timeout: 5))
        capture(app, name: "Home Russian Light")
        app.buttons["trade.buy"].tap()
        let amount = app.textFields["trade.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        amount.typeText("1,25")
        XCTAssertFalse(app.buttons["trade.review"].isHittable)
        XCTAssertTrue(app.buttons["keyboard.done"].isHittable)
        capture(app, name: "Native Keyboard Russian Light")
        dismissKeyboard(in: app)
        XCTAssertTrue(app.buttons["trade.review"].isHittable)
        capture(app, name: "Buy Russian Light")
        app.buttons["trade.review"].tap()
        XCTAssertTrue(app.buttons["trade.confirm"].waitForExistence(timeout: 5))
        capture(app, name: "Review Russian Light")
        app.buttons["trade.confirm"].tap()
        XCTAssertTrue(app.staticTexts["trade.saved"].waitForExistence(timeout: 5))
        capture(app, name: "Operation Saved Russian Light")
        for title in ["Тип операции", "Итого"] {
            // SwiftUI can expose the label and value as one accessibility element.
            let row = app.descendants(matching: .any).matching(
                NSPredicate(format: "label BEGINSWITH %@", title)
            ).firstMatch
            XCTAssertTrue(row.exists, "Missing receipt row \(title)\n\(app.debugDescription)")
        }
    }

    private func enterAmount(_ value: String, in app: XCUIApplication, fieldID: String = "trade.amount") {
        let amount = app.textFields[fieldID]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        amount.typeText(value)
        dismissKeyboard(in: app)
    }

    private func dismissKeyboard(in app: XCUIApplication) {
        let done = app.buttons["keyboard.done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 3))
        done.tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                                  object: app.keyboards.firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
    }

    private func capture(_ app: XCUIApplication, name: String) {
        Thread.sleep(forTimeInterval: 0.35)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
