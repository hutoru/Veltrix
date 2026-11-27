import Foundation

enum L {
    static func text(_ key: String) -> String { NSLocalizedString(key, comment: "") }
    static func format(_ key: String, _ args: CVarArg...) -> String {
        String(format: text(key), locale: .current, arguments: args)
    }

    static func trades(_ count: Int, language: String = Bundle.main.preferredLocalizations.first ?? "en") -> String {
        if language.hasPrefix("ru") {
            let digits = count.magnitude
            let last = digits % 10
            let noun: String
            if (11...14).contains(digits % 100) { noun = "сделок" }
            else if last == 1 { noun = "сделка" }
            else if (2...4).contains(last) { noun = "сделки" }
            else { noun = "сделок" }
            return "\(count) \(noun)"
        }
        return "\(count) " + text(count == 1 ? "Trade" : "Trades")
    }
}

enum FinancialFormatter {
    static func pricePrecision(_ amount: Decimal, minimum: Int) -> Int {
        guard amount != 0, abs(amount) < 1 else { return minimum }
        var scaled = abs(amount)
        var places = 3
        while scaled < 1 && places < 12 {
            scaled *= 10
            places += 1
        }
        return max(minimum, places)
    }

    static func number(_ number: Decimal, maximum: Int = 8) -> String {
        let format = NumberFormatter()
        format.numberStyle = .decimal
        format.maximumFractionDigits = maximum
        format.minimumFractionDigits = 0
        return format.string(from: NSDecimalNumber(decimal: number)) ?? "—"
    }

    static func money(_ value: Decimal, currency: String, digits: Int, minimum: Int? = nil,
                      locale: Locale = .current) -> String {
        let format = NumberFormatter()
        format.locale = locale
        format.numberStyle = .currency
        format.currencyCode = currency
        format.maximumFractionDigits = digits
        format.minimumFractionDigits = minimum ?? digits
        format.minusSign = "−"
        if let symbol = ["USD": "$", "EUR": "€", "RUB": "₽"][currency] {
            let prefix = currency == "USD" ? symbol : ""
            let suffix = currency == "USD" ? "" : "\u{00A0}" + symbol
            format.positivePrefix = prefix
            format.negativePrefix = "−" + prefix
            format.positiveSuffix = suffix
            format.negativeSuffix = suffix
        }
        let displayedValue = value < 0 && MoneyMath.round(value, scale: digits) == 0 ? .zero : value
        return format.string(from: NSDecimalNumber(decimal: displayedValue)) ?? "—"
    }

    static func percent(_ value: Decimal?) -> String {
        guard let value else { return "—" }
        let format = NumberFormatter()
        format.numberStyle = .percent
        format.maximumFractionDigits = 2
        format.minimumFractionDigits = 2
        let rounded = MoneyMath.round(value, scale: 2)
        format.positivePrefix = rounded > 0 ? "+" : ""
        format.minusSign = "−"
        return format.string(from: NSDecimalNumber(decimal: rounded / 100)) ?? "—"
    }

    static func input(_ number: Decimal) -> String {
        NSDecimalNumber(decimal: number).stringValue.replacingOccurrences(of: ".", with: Locale.current.decimalSeparator ?? ".")
    }

    static func amount(_ text: String) -> Decimal? {
        MoneyMath.parse(text.replacingOccurrences(of: ",", with: "."), separator: ".")
    }

    static func error(_ error: Error) -> String {
        if let issue = error as? SimulationError {
            switch issue {
            case .invalidAmount: return L.text("Enter a valid amount.")
            case .precision: return L.text("The amount exceeds the supported decimal precision.")
            case .insufficientCash: return L.text("Insufficient available balance.")
            case .insufficientAsset: return L.text("Insufficient available assets.")
            case .missingQuote: return L.text("Price unavailable. Refresh markets and try again.")
            case .missingRecord: return L.text("This record is no longer available.")
            case .duplicate: return L.text("This operation was already recorded.")
            case .invalidPair: return L.text("Choose two different available assets.")
            case .invalidBackup: return L.text("This file is not a valid VELTRIX backup.")
            case .reservedAsset: return L.text("Cancel the orders reserving this asset first.")
            case .cardFrozen: return L.text("Unfreeze the card first.")
            case .cardLimit: return L.text("The amount exceeds the card’s payment limit.")
            case .cardHasBalance: return L.text("Return the card balance before deleting it.")
            case .alreadyRefunded: return L.text("This payment was already refunded.")
            case .invalidName: return L.text("Enter a name.")
            case .invalidAddress: return L.text("Check the address format for the selected network.")
            }
        }
        if let issue = error as? MarketError {
            switch issue {
            case .rateLimited: return L.text("Market source is rate limited. Try again later.")
            case .accessDenied: return L.text("Market access denied. Check the optional API key in Settings.")
            default: return L.text("Market data is temporarily unavailable.")
            }
        }
        if error is URLError { return L.text("Connection unavailable. Showing the latest saved data.") }
        return L.text("The operation couldn’t be completed.")
    }
}

typealias Display = FinancialFormatter
