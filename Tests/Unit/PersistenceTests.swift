import XCTest
@testable import Veltrix

final class PersistenceTests: XCTestCase {
    func testSQLiteSurvivesReopeningAndBackupRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("state.sqlite")
        let state = try TradingEngine.apply(.deposit(50), to: Ledger.fresh(cash: 1_000))
        try autoreleasepool {
            let store = try CoreDataLedgerStore(url: url)
            XCTAssertNil(try store.load())
            try store.save(state)
        }
        try autoreleasepool {
            let store = try CoreDataLedgerStore(url: url)
            XCTAssertEqual(try store.load(), state)
        }
        let data = try SimulationBackup.export(state)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("VELTRIX · Simulation"))
        XCTAssertEqual(try SimulationBackup.load(data), state)
    }

    func testCorruptBackupCannotReplaceLedger() throws {
        XCTAssertThrowsError(try SimulationBackup.load(Data("{}".utf8)))
        var invalid = Ledger.fresh()
        invalid.portfolios[0].cash = -1
        let data = try SimulationBackup.export(invalid)
        XCTAssertThrowsError(try SimulationBackup.load(data)) {
            XCTAssertEqual($0 as? SimulationError, .invalidBackup)
        }
    }

    @MainActor func testOnSetPortfolioKeepsLedgerAndActivitySeparate() async throws {
        let name = "Veltrix-OnSet-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let storage = try CoreDataLedgerStore(inMemory: true)
        let model = VeltrixModel(defaults: defaults, store: storage, testing: true)
        XCTAssertTrue(model.execute(.deposit(125)))
        let main = model.ledger
        XCTAssertEqual(model.notificationEntries.count, 1)

        model.setOnSet(true)
        XCTAssertTrue(model.onSet)
        XCTAssertNotEqual(model.ledger.selected, main.selected)
        XCTAssertTrue(model.notificationEntries.isEmpty)
        XCTAssertTrue(model.execute(.deposit(30)))
        XCTAssertTrue(model.execute(.createCard(.black, "On-set card", nil)))
        model.clearNotifications()
        let filming = model.ledger

        model.setOnSet(false)
        XCTAssertFalse(model.onSet)
        XCTAssertEqual(model.ledger, main)
        XCTAssertEqual(try storage.load(), main)
        XCTAssertEqual(model.notificationEntries.count, 1)
        XCTAssertTrue(model.cards.isEmpty)

        model.setOnSet(true)
        XCTAssertEqual(model.ledger, filming)
        XCTAssertEqual(model.cards.first?.name, "On-set card")
        XCTAssertTrue(model.notificationEntries.isEmpty)
    }

    func testCardDesignRoundTripKeepsExistingCardsReadable() throws {
        let old = try TradingEngine.apply(.createCard(.platinum, "Original", 100), to: Ledger.fresh())
        let existing = try XCTUnwrap(old.cards.first)
        let originalBackup = try SimulationBackup.export(old)
        XCTAssertNil(try SimulationBackup.load(originalBackup).cards.first?.design)
        let design = CardDesign(material: .holographic, texture: .engraved, tint: 0x7955FF)
        let revised = try TradingEngine.apply(.configureCard(existing.id, "Edited", 100, tier: .custom, design: design), to: old)
        let restored = try SimulationBackup.load(SimulationBackup.export(revised))
        XCTAssertEqual(restored.cards.first?.id, existing.id)
        XCTAssertEqual(restored.cards.first?.design, design)
        XCTAssertEqual(restored.cards.first?.tier, .custom)
    }

    func testCardCatalogAndPrimaryCardSurviveReopening() throws {
        let tiers = CardCollection.allCases.flatMap(\.tiers)
        XCTAssertEqual(CardCollection.allCases.map { $0.tiers.count }, [5, 5, 4, 8])
        XCTAssertEqual(Set(tiers).count, 22)
        let state = try tiers.reduce(Ledger.fresh()) { ledger, tier in
            try TradingEngine.apply(.createCard(tier, tier.rawValue, 100, design: tier.defaultDesign), to: ledger)
        }
        let primary = try XCTUnwrap(state.cards.last?.id)
        let updated = try TradingEngine.apply(.setPrimaryCard(primary), to: state)
        let storage = try CoreDataLedgerStore(inMemory: true)
        try storage.save(updated)
        let loaded = try XCTUnwrap(storage.load())
        XCTAssertEqual(loaded.cards.map(\.tier), tiers)
        XCTAssertEqual(loaded.cards.map(\.design), tiers.map { Optional($0.defaultDesign) })
        XCTAssertEqual(loaded.portfolios.first?.primaryCardID, primary)
        let restored = try SimulationBackup.load(SimulationBackup.export(loaded))
        XCTAssertEqual(restored, updated)
        XCTAssertNil(try TradingEngine.apply(.deleteCard(primary), to: restored).portfolios.first?.primaryCardID)
    }

    func testRussianTradeCountInflection() {
        for (count, expected) in [(0, "0 сделок"), (1, "1 сделка"), (2, "2 сделки"), (5, "5 сделок"),
                                  (11, "11 сделок"), (14, "14 сделок"), (21, "21 сделка"),
                                  (104, "104 сделки"), (111, "111 сделок")] {
            XCTAssertEqual(L.trades(count, language: "ru"), expected)
        }
    }

    @MainActor func testFailedSaveDoesNotPublishLedgerOrNotify() throws {
        let name = "Veltrix-Failed-Save-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let initial = Ledger.fresh()
        let store = FailingStore(initial: initial)
        var notificationCount = 0
        let model = VeltrixModel(defaults: defaults, store: store, testing: true) { _, _, _ in
            notificationCount += 1
        }
        XCTAssertFalse(model.execute(.deposit(100)))
        XCTAssertEqual(model.ledger, initial)
        XCTAssertEqual(notificationCount, 0)
    }

    private final class FailingStore: LedgerStore {
        let initial: Ledger
        init(initial: Ledger) { self.initial = initial }
        func load() throws -> Ledger? { initial }
        func save(_ ledger: Ledger) throws { throw CocoaError(.fileWriteUnknown) }
    }

    @MainActor func testNotificationsFollowSuccessfulSaveAndHonorPrivacy() async throws {
        let name = "Veltrix-Notifications-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let storage = try CoreDataLedgerStore(inMemory: true)
        var notifications: [(Entry, NotificationService.OperationAmounts?)] = []
        let model = VeltrixModel(defaults: defaults, store: storage, testing: true) { entry, _, amount in
            let saved = try? storage.load()
            XCTAssertTrue(saved?.portfolios.first?.entries.contains(where: { $0.id == entry.id }) == true)
            notifications.append((entry, amount))
        }
        model.pushOperations = true
        model.privateNotifications = true
        model.hideNotificationBalance = true
        let operation = UUID()
        XCTAssertTrue(model.execute(.deposit(100), id: operation))
        XCTAssertFalse(model.execute(.deposit(100), id: operation))
        XCTAssertFalse(model.execute(.deposit(0)))
        XCTAssertEqual(notifications.map { $0.0.id }, [operation])
        XCTAssertNil(notifications.first?.1)

        model.privateNotifications = false
        XCTAssertTrue(model.execute(.deposit(20)))
        XCTAssertEqual(notifications.count, 2)
        XCTAssertNotNil(notifications.last?.1)
        XCTAssertNil(notifications.last?.1?.balance)

        model.hide = true
        defaults.set(true, forKey: "deviceLockEnabled")
        model.hideNotificationBalance = false
        XCTAssertTrue(model.execute(.deposit(25)))
        XCTAssertEqual(notifications.count, 3)
        XCTAssertNotNil(notifications.last?.1?.amount)
        XCTAssertNotNil(notifications.last?.1?.balance)
    }

    func testCardCatalogContains22DistinctDesignsAndPreservesLegacyTier() throws {
        let collections = CardCollection.allCases
        XCTAssertEqual(collections.map { $0.tiers.count }, [5, 5, 4, 8])
        let tiers = collections.flatMap(\.tiers)
        XCTAssertEqual(Set(tiers).count, 22)
        XCTAssertTrue(tiers.allSatisfy { $0.defaultDesign.isValid })
        let ledger = try tiers.reduce(Ledger.fresh()) { ledger, tier in
            try TradingEngine.apply(.createCard(tier, tier.rawValue, nil, design: tier.defaultDesign), to: ledger)
        }
        let decoded = try SimulationBackup.load(SimulationBackup.export(ledger))
        XCTAssertEqual(decoded.cards.map(\.tier), tiers)
        XCTAssertEqual(try JSONDecoder().decode(CardTier.self, from: Data("\"purple\"".utf8)), .purple)
    }
}
