import Foundation

struct LocalPaymentRequest: Codable, Equatable, Identifiable, Sendable {
    static let prefix = "VELTRIX-TEST:v1:"

    let id: UUID
    let recipient: UUID
    let asset: String
    let network: TransferNetwork
    let units: Decimal

    var payload: String { Self.prefix + id.uuidString }

    var isValid: Bool {
        TransferNetwork.available(for: asset).contains(network) && (try? MoneyMath.quantity(units)) != nil
    }

    static func identifier(from payload: String) -> UUID? {
        guard payload.hasPrefix(prefix), payload.utf8.count == prefix.utf8.count + 36 else { return nil }
        return UUID(uuidString: String(payload.dropFirst(prefix.count)))
    }
}

enum TransferNetwork: String, CaseIterable, Codable, Sendable {
    case bitcoin = "Bitcoin"
    case ethereum = "Ethereum"
    case solana = "Solana"

    static func available(for asset: String) -> [TransferNetwork] {
        switch asset {
        case "bitcoin": return [.bitcoin]
        case "ethereum", "chainlink": return [.ethereum]
        case "solana": return [.solana]
        case "tether", "usd-coin": return [.ethereum, .solana]
        default: return []
        }
    }

    func accepts(_ address: String) -> Bool {
        let expression: String
        switch self {
        case .bitcoin:
            expression = "^(?:[13][1-9A-HJ-NP-Za-km-z]{25,34}|bc1[ac-hj-np-z02-9]{11,87}|BC1[AC-HJ-NP-Z02-9]{11,87})$"
        case .ethereum: expression = "^0x[0-9a-fA-F]{40}$"
        case .solana: expression = "^[1-9A-HJ-NP-Za-km-z]{32,44}$"
        }
        return address.range(of: expression, options: .regularExpression) != nil
    }
}
