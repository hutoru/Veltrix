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
}
