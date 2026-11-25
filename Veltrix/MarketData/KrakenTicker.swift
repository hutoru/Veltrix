import Foundation

#if os(iOS)
struct TickerTick: Sendable {
    let asset: String
    let price: Decimal
    let date: Date
}

struct KrakenTicker {
    static let assets = Asset.catalog.filter { ["BTC", "ETH", "SOL", "XRP", "DOGE", "ADA", "LINK", "LTC"].contains($0.ticker) }

    func listen(_ consume: @escaping @MainActor ([TickerTick]) -> Void) async throws {
        let socket = URLSession.shared.webSocketTask(with: URL(string: "wss://ws.kraken.com/v2")!)
        socket.maximumMessageSize = 128_000
        socket.resume()
        defer { socket.cancel(with: .goingAway, reason: nil) }
        try await withTaskCancellationHandler {
            let request = Subscription(params: .init(symbol: Self.assets.map { $0.ticker + "/USD" }))
            try await socket.send(.data(JSONEncoder().encode(request)))
            var delivered = Date.distantPast
            var pending: [String: TickerTick] = [:]
            while !Task.isCancelled {
                let message = try await socket.receive()
                let data: Data
                switch message {
                case let .data(value): data = value
                case let .string(value): data = Data(value.utf8)
                @unknown default: continue
                }
                guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
                      envelope.channel == "ticker" else { continue }
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                for item in envelope.data where item.last > 0 {
                    guard let asset = Self.assets.first(where: { $0.ticker + "/USD" == item.symbol }) else { continue }
                    // A snapshot with no exchange timestamp cannot establish the age of its last trade.
                    let date = item.timestamp.flatMap(formatter.date(from:)) ?? (envelope.type == "update" ? Date() : nil)
                    if let date { pending[asset.id] = TickerTick(asset: asset.id, price: item.last, date: date) }
                }
                if !pending.isEmpty && Date().timeIntervalSince(delivered) >= 2 {
                    await consume(Array(pending.values))
                    delivered = Date()
                    pending.removeAll(keepingCapacity: true)
                }
            }
        } onCancel: {
            socket.cancel(with: .goingAway, reason: nil)
        }
    }

    private struct Subscription: Encodable {
        let method = "subscribe"
        struct Parameters: Encodable {
            let channel = "ticker"
            let symbol: [String]
            let snapshot = false
        }
        let params: Parameters
    }

    private struct Envelope: Decodable {
        struct Tick: Decodable {
            let symbol: String
            let last: Decimal
            let timestamp: String?
        }
        let channel: String
        let type: String
        let data: [Tick]
    }
}
#endif
