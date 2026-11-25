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
        let lock = AppLock(defaults: defaults, legacyLock: { true }) { policy in
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

    @MainActor func testNativeTradeRequestContainsAssetAmountFiatAndSound() {
        let entry = Entry(id: UUID(), date: .now, kind: .buy, asset: "bitcoin", amount: 1, usd: 100)
        let notification = OperationNotifications.request(for: entry, filled: false, amounts: "1 BTC · $100.00")
        XCTAssertEqual(notification.identifier, entry.id.uuidString)
        XCTAssertEqual(notification.content.title, "Veltrix")
        XCTAssertTrue(notification.content.body.contains("Bitcoin · 1 BTC · $100.00"))
        XCTAssertNotNil(notification.content.sound)
        XCTAssertNil(notification.trigger)
        let privateRequest = OperationNotifications.request(for: entry, filled: false, amounts: nil)
        XCTAssertFalse(privateRequest.content.body.contains("Bitcoin"))
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
