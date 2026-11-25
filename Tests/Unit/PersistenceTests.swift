import XCTest
@testable import Veltrix

final class PersistenceTests: XCTestCase {
    func testSQLiteSurvivesReopeningAndBackupRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("state.sqlite")
        let state = try TradingEngine.apply(.deposit(50), to: Ledger.fresh(cash: 1_000))
        do {
            let store = try CoreDataLedgerStore(url: url)
            XCTAssertNil(try store.load())
            try store.save(state)
        }
        let store = try CoreDataLedgerStore(url: url)
        XCTAssertEqual(try store.load(), state)
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
}
