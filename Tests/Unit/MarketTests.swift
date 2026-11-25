import XCTest
@testable import Veltrix

final class MarketTests: XCTestCase {
    func testRateLimitHonorsRetryAfterWithoutMakingSecondRequest() async throws {
        let transport = MockTransport(status: 429, headers: ["Retry-After": "120"], data: Data())
        let client = HTTPClient(transport: transport)
        let url = try XCTUnwrap(URL(string: "https://example.test/quotes"))
        for _ in 0..<2 {
            do {
                _ = try await client.get(url)
                XCTFail("Expected backoff")
            } catch {
                XCTAssertEqual(error as? MarketError, .rateLimited)
            }
        }
        let count = await transport.requests
        XCTAssertEqual(count, 1)
    }

    func testConnectivityAndAccessDeniedSurfaceAsErrors() async throws {
        let url = try XCTUnwrap(URL(string: "https://example.test/quotes"))
        let denied = HTTPClient(transport: MockTransport(status: 401, data: Data()))
        do {
            _ = try await denied.get(url)
            XCTFail("Expected access denial")
        } catch { XCTAssertEqual(error as? MarketError, .accessDenied) }

        let offline = HTTPClient(transport: OfflineTransport())
        do {
            _ = try await offline.get(url)
            XCTFail("Expected connection error")
        } catch { XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet) }
    }

    func testProviderDecodesDecimalValuesAndDoesNotReplaceMissingFields() async throws {
        let response = Data("""
        [{"id":"bitcoin","current_price":345.0123456789,"price_change_percentage_24h":-1.25,
          "last_updated":"2026-03-05T12:08:58.966Z","price_change_24h":-4.5,
          "sparkline_in_7d":{"price":[340,347.25,345.0123456789]}},
         {"id":"ethereum","current_price":null}]
        """.utf8)
        let transport = MockTransport(status: 200, data: response)
        let provider = PublicMarketProvider(http: HTTPClient(transport: transport))
        let quotes = try await provider.quotes()
        XCTAssertEqual(quotes.first?.price, Decimal(string: "345.0123456789"))
        XCTAssertEqual(quotes.first?.change, Decimal(string: "-1.25"))
        XCTAssertNotNil(quotes.first?.updated)
        XCTAssertEqual(quotes.first?.change24hUSD, Decimal(string: "-4.5"))
        XCTAssertEqual(quotes.first?.sparkline, [340, Decimal(string: "347.25")!, Decimal(string: "345.0123456789")!])
        XCTAssertNil(quotes.last?.sparkline)
        XCTAssertNil(quotes.last?.price)
        let request = await transport.lastRequest
        XCTAssertEqual(request?.url?.path, "/api/v3/coins/markets")
    }

    func testCacheKeepsLastSavedQuotesAvailableOffline() async throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let cache = MarketCache(directory: temp)
        await cache.write([Quote(id: "bitcoin", price: 123)], key: "quotes")
        let loaded = await MarketCache(directory: temp).read([Quote].self, key: "quotes")
        XCTAssertEqual(loaded?.value.first?.price, 123)
    }

    private actor MockTransport: HTTPTransport {
        let status: Int
        let headers: [String: String]
        let data: Data
        var requests = 0
        var lastRequest: URLRequest?

        init(status: Int, headers: [String: String] = [:], data: Data) {
            self.status = status
            self.headers = headers
            self.data = data
        }

        func load(_ request: URLRequest) async throws -> (Data, URLResponse) {
            requests += 1
            lastRequest = request
            let url = try XCTUnwrap(request.url)
            let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/2", headerFields: headers))
            return (data, response)
        }
    }

    private struct OfflineTransport: HTTPTransport {
        func load(_ request: URLRequest) async throws -> (Data, URLResponse) {
            throw URLError(.notConnectedToInternet)
        }
    }
}
