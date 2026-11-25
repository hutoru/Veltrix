import Foundation

enum SimulationError: String, Error, Equatable, Sendable {
    case invalidAmount, precision, insufficientCash, insufficientAsset, missingQuote
    case missingRecord, duplicate, invalidPair, invalidBackup, reservedAsset
    case cardFrozen, cardLimit, cardHasBalance, alreadyRefunded, invalidName
}

enum MoneyMath {
    static func add(_ a: Decimal, _ b: Decimal) throws -> Decimal { try calculate(a, b, NSDecimalAdd) }
    static func subtract(_ a: Decimal, _ b: Decimal) throws -> Decimal { try calculate(a, b, NSDecimalSubtract) }
    static func multiply(_ a: Decimal, _ b: Decimal) throws -> Decimal { try calculate(a, b, NSDecimalMultiply) }
    static func divide(_ a: Decimal, _ b: Decimal) throws -> Decimal {
        guard b != 0 else { throw SimulationError.precision }
        return try calculate(a, b, NSDecimalDivide, rounded: true)
    }

    private static func calculate(
        _ a: Decimal, _ b: Decimal,
        _ operation: (UnsafeMutablePointer<Decimal>, UnsafePointer<Decimal>, UnsafePointer<Decimal>, Decimal.RoundingMode) -> Decimal.CalculationError,
        rounded: Bool = false
    ) throws -> Decimal {
        var lhs = a
        var rhs = b
        var result = Decimal.zero
        guard !a.isNaN, !b.isNaN else { throw SimulationError.precision }
        let status = operation(&result, &lhs, &rhs, .bankers)
        guard status == .noError || (rounded && status == .lossOfPrecision), !result.isNaN else {
            throw SimulationError.precision
        }
        if !rounded && b != 0 && result == a && operationIsInexact(a, b, operation) {
            throw SimulationError.precision
        }
        return result
    }

    private static func operationIsInexact(
        _ a: Decimal, _ b: Decimal,
        _ operation: (UnsafeMutablePointer<Decimal>, UnsafePointer<Decimal>, UnsafePointer<Decimal>, Decimal.RoundingMode) -> Decimal.CalculationError
    ) -> Bool {
        var lhs = a
        var rhs = b
        var up = Decimal.zero
        var down = Decimal.zero
        _ = operation(&up, &lhs, &rhs, .up)
        _ = operation(&down, &lhs, &rhs, .down)
        return up != down
    }

    static func round(_ value: Decimal, scale: Int) -> Decimal {
        var source = value
        var result = Decimal.zero
        NSDecimalRound(&result, &source, scale, .bankers)
        return result
    }

    static func quantity(_ value: Decimal) throws {
        guard !value.isNaN, value > 0 else { throw SimulationError.invalidAmount }
    }

    static func nonnegative(_ value: Decimal) throws {
        guard !value.isNaN, value >= 0 else { throw SimulationError.invalidAmount }
    }

    static func parse(_ text: String, separator: String) -> Decimal? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = separator == "." ? value : value.replacingOccurrences(of: separator, with: ".")
        guard normalized.range(of: #"^(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)$"#, options: .regularExpression) != nil,
              let parsed = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")),
              !parsed.isNaN else { return nil }
        func canonical(_ input: String) -> String {
            let parts = input.split(separator: ".", omittingEmptySubsequences: false)
            let whole = String(parts[0].drop(while: { $0 == "0" }))
            let fraction = parts.count == 2 ? String(parts[1].reversed().drop(while: { $0 == "0" }).reversed()) : ""
            return whole + "." + fraction
        }
        return canonical(normalized) == canonical(NSDecimalNumber(decimal: parsed).stringValue) ? parsed : nil
    }
}
