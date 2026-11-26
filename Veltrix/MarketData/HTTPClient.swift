import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum MarketError: Error, Equatable, Sendable {
    case invalidResponse, unavailable, rateLimited, accessDenied, http(Int)
}

protocol HTTPTransport: Sendable {
    func load(_ request: URLRequest) async throws -> (Data, URLResponse)
}

struct SessionTransport: HTTPTransport {
    var session: URLSession = .shared
    func load(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

actor HTTPClient {
    private let transport: any HTTPTransport
    private var cooldown: [String: Date] = [:]
    private struct RequestKey: Hashable {
        let url: URL
        let headers: [String: String]

        func hash(into hasher: inout Hasher) {
            hasher.combine(url)
            for (key, value) in headers.sorted(by: { $0.key < $1.key }) {
                hasher.combine(key)
                hasher.combine(value)
            }
        }
    }

    private var requests: [RequestKey: Task<(Data, URLResponse), Error>] = [:]

    init(transport: any HTTPTransport = SessionTransport()) { self.transport = transport }

    func get(_ url: URL, headers: [String: String] = [:]) async throws -> Data {
        let host = url.host ?? ""
        if let until = cooldown[host], until > Date() { throw MarketError.rateLimited }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 18)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let key = RequestKey(url: url, headers: request.allHTTPHeaderFields ?? [:])
        let (data, response) = try await response(for: request, key: key)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw MarketError.invalidResponse }
        switch response.statusCode {
        case 200..<300: return data
        case 401, 403: throw MarketError.accessDenied
        case 429:
            let retry = response.value(forHTTPHeaderField: "Retry-After")
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
            let seconds = retry.flatMap(Double.init) ?? retry.flatMap(formatter.date(from:))?.timeIntervalSinceNow ?? 60
            let deadline = Date().addingTimeInterval(max(1, seconds.isFinite ? seconds : 60))
            cooldown[host] = max(deadline, cooldown[host] ?? .distantPast)
            throw MarketError.rateLimited
        default: throw MarketError.http(response.statusCode)
        }
    }

    private func response(for request: URLRequest, key: RequestKey) async throws -> (Data, URLResponse) {
        if let pending = requests[key] { return try await pending.value }

        let transport = transport
        let retryDelays: [UInt64] = [250_000_000, 500_000_000]
        let pending = Task {
            for delay in retryDelays {
                do {
                    let result = try await transport.load(request)
                    if let response = result.1 as? HTTPURLResponse, [500, 502, 503, 504].contains(response.statusCode) {
                        try await Task.sleep(nanoseconds: delay)
                    } else {
                        return result
                    }
                } catch let error as URLError where [.timedOut, .networkConnectionLost, .cannotConnectToHost].contains(error.code) {
                    try await Task.sleep(nanoseconds: delay)
                }
            }
            return try await transport.load(request)
        }
        requests[key] = pending
        defer { requests[key] = nil }
        return try await pending.value
    }
}
