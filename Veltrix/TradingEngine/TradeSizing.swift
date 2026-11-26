import Foundation

enum TradeSizing {
    static func convert(_ amount: Decimal, fromUSD: Bool, price: Decimal) throws -> Decimal {
        guard price > 0 else { throw SimulationError.missingQuote }
        return fromUSD ? try MoneyMath.divide(amount, price) : try MoneyMath.quotedUSD(amount, at: price)
    }

    static func preset(available: Decimal, percent: Int, sourceIsUSD: Bool,
                       inputIsUSD: Bool, price: Decimal?) throws -> Decimal {
        if percent == 100 && sourceIsUSD == inputIsUSD && !sourceIsUSD { return available }
        var amount = try MoneyMath.multiply(available, Decimal(percent) / 100)
        if sourceIsUSD != inputIsUSD {
            guard let price else { throw SimulationError.missingQuote }
            amount = try convert(amount, fromUSD: sourceIsUSD, price: price)
        }
        let rounded = MoneyMath.round(amount, scale: 16, mode: .down)
        return rounded == 0 ? amount : rounded
    }
}
