import Foundation

enum StakeTerm: Int, Codable, CaseIterable, Identifiable, Sendable {
    case flexible = 0, week = 7, month = 30, quarter = 90
    var id: Int { rawValue }
}

struct Stake: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let asset: String
    let units: Decimal
    let rate: Decimal
    let term: StakeTerm
    let opened: Date
    var creditedUntil: Date

    static let rates: [String: Decimal] = [
        "ethereum": Decimal(3) / 100, "solana": Decimal(55) / 1_000, "the-open-network": Decimal(4) / 100,
    ]
    static let minimum = Decimal(1) / 100

    var maturity: Date? {
        term == .flexible ? nil : opened.addingTimeInterval(Double(term.rawValue) * 86_400)
    }

    func rewards(at date: Date) throws -> Decimal {
        let end = min(date, maturity ?? date)
        let seconds = max(0, floor(end.timeIntervalSince(creditedUntil)))
        guard seconds.isFinite else { throw SimulationError.invalidAmount }
        return try Self.estimate(units: units, rate: rate, seconds: Decimal(seconds))
    }

    static func estimate(units: Decimal, rate: Decimal, seconds: Decimal) throws -> Decimal {
        let annual = try MoneyMath.multiply(units, rate)
        let elapsed = try MoneyMath.divide(seconds, 31_536_000)
        return MoneyMath.round(try MoneyMath.multiply(annual, elapsed), scale: 12, mode: .down)
    }
}
