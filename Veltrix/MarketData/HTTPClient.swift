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

    init(transport: any HTTPTransport = SessionTransport()) { self.transport = transport }

    func get(_ url: URL, headers: [String: String] = [:]) async throws -> Data {
        let host = url.host ?? ""
        if let until = cooldown[host], until > Date() { throw MarketError.rateLimited }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 18)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let (data, response) = try await transport.load(request)
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
            cooldown[host] = Date().addingTimeInterval(max(1, seconds.isFinite ? seconds : 60))
            throw MarketError.rateLimited
        default: throw MarketError.http(response.statusCode)
        }
    }
}
