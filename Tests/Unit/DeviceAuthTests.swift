import LocalAuthentication
import UserNotifications
import XCTest
@testable import Veltrix

final class DeviceAuthTests: XCTestCase {
    @MainActor func testLegacyProtectionMigratesAndUsesSystemPolicyWithPasscodeFallback() async throws {
        let name = "Veltrix-System-Lock-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var policies: [LAPolicy] = []
        var success = false
        let lock = AuthCoordinator(defaults: defaults, legacyLock: { true }) { policy in
            policies.append(policy)
            return success
        }
        XCTAssertTrue(lock.enabled)
        XCTAssertTrue(lock.locked)
        XCTAssertTrue(defaults.bool(forKey: "deviceLockEnabled"))
        await lock.tryAutomaticUnlock()
        await lock.tryAutomaticUnlock()
        XCTAssertEqual(policies, [.deviceOwnerAuthentication])
        XCTAssertTrue(lock.locked)

        success = true
        await lock.unlockWithDevice()
        XCTAssertFalse(lock.locked)
        lock.setTimeout(60)
        let start = Date(timeIntervalSince1970: 100)
        lock.enteredBackground(at: start)
        lock.becomeActive(at: start.addingTimeInterval(59))
        XCTAssertFalse(lock.locked)
        lock.enteredBackground(at: start)
        lock.becomeActive(at: start.addingTimeInterval(60))
        XCTAssertTrue(lock.locked)
        await lock.tryAutomaticUnlock()
        XCTAssertFalse(lock.locked)
        XCTAssertEqual(policies, Array(repeating: .deviceOwnerAuthentication, count: 3))
    }

    @MainActor func testAuthorizationCancellationLeavesGateLockedAndAllowsManualRetry() async throws {
        let name = "Veltrix-Cancel-Lock-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "deviceLockEnabled")
        var calls = 0
        let lock = AuthCoordinator(defaults: defaults, testing: true) { _ in
            calls += 1
            if calls == 1 {
                throw NSError(domain: LAError.errorDomain, code: LAError.Code.userCancel.rawValue)
            }
            return true
        }
        await lock.tryAutomaticUnlock()
        XCTAssertEqual(lock.state, .locked)
        XCTAssertNil(lock.error)
        await lock.tryAutomaticUnlock()
        XCTAssertEqual(calls, 1)
        await lock.unlockWithDevice()
        XCTAssertEqual(lock.state, .unlocked)
    }

    @MainActor func testNativeTradeRequestContainsAssetAmountFiatAndSound() {
        let entry = Entry(id: UUID(), date: .now, kind: .buy, asset: "bitcoin", amount: 1, usd: 100)
        let amounts = NotificationService.OperationAmounts(quantity: "1 BTC", amount: "$100.00", balance: "$900.00")
        let notification = NotificationService.request(for: entry, filled: false, amounts: amounts)
        XCTAssertEqual(notification.identifier, entry.id.uuidString)
        XCTAssertEqual(notification.content.title, "VELTRIX · CryptoApp")
        XCTAssertEqual(notification.content.subtitle, "")
        XCTAssertEqual(notification.content.body, "Purchase BTC for $100.00.\nAvailable balance: $900.00\n1 BTC")
        XCTAssertNotNil(notification.content.sound)
        XCTAssertNil(notification.trigger)
        let privateRequest = NotificationService.request(for: entry, filled: false, amounts: nil)
        XCTAssertEqual(privateRequest.content.subtitle, "")
        XCTAssertEqual(privateRequest.content.body, entry.kind.localized + " BTC")
    }

    func testNativeDecimalInputAcceptsDotAndCommaWithoutAmbiguousGrouping() {
        XCTAssertEqual(Display.amount("0.125"), Decimal(string: "0.125"))
        XCTAssertEqual(Display.amount("0,125"), Decimal(string: "0.125"))
        XCTAssertNil(Display.amount("1,2.3"))
        XCTAssertNil(Display.amount("1 000,00"))
    }

    func testTradeSizingUsesQuotesAndPreservesExactCoinMax() throws {
        let coin = try XCTUnwrap(Decimal(string: "0.00000000000123456789"))
        XCTAssertEqual(try TradeSizing.preset(available: coin, percent: 100, sourceIsUSD: false,
                                              inputIsUSD: false, price: nil), coin)
        XCTAssertEqual(try TradeSizing.preset(available: 100, percent: 25, sourceIsUSD: true,
                                              inputIsUSD: false, price: 50), Decimal(string: "0.5"))
        XCTAssertEqual(try TradeSizing.convert(12, fromUSD: false, price: 75), 900)
        XCTAssertThrowsError(try TradeSizing.convert(12, fromUSD: true, price: 0))
    }
}
