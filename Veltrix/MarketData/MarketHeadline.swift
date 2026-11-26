import Foundation

struct MarketHeadline: Identifiable {
    let title: String
    let url: URL
    let date: Date?
    var id: URL { url }

    static func fetch() async throws -> [MarketHeadline] {
        let url = URL(string: "https://www.coindesk.com/arc/outboundfeeds/rss/")!
        let request = URLRequest(url: url, timeoutInterval: 8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
              data.count <= 2_000_000 else { throw URLError(.badServerResponse) }
        try Task.checkCancellation()
        let feed = HeadlinesParser()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = feed
        guard parser.parse() else { throw URLError(.cannotDecodeContentData) }
        return Array(feed.headlines.prefix(4))
    }
}

private final class HeadlinesParser: NSObject, XMLParserDelegate {
    private var item = false
    private var field = ""
    private var title = ""
    private var link = ""
    private var published = ""
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter
    }()
    private(set) var headlines: [MarketHeadline] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName: String?, attributes attributeDict: [String: String]) {
        if elementName == "item" {
            item = true
            title = ""
            link = ""
            published = ""
        }
        field = item ? elementName : ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if field == "title" { title += string }
        if field == "link" { link += string }
        if field == "pubDate" { published += string }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let value = String(data: CDATABlock, encoding: .utf8) {
            self.parser(parser, foundCharacters: value)
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        field = ""
        guard elementName == "item" else { return }
        item = false
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https", let host = url.host?.lowercased(),
              host == "coindesk.com" || host.hasSuffix(".coindesk.com"),
              !headlines.contains(where: { $0.url == url }) else { return }
        let date = dateFormatter.date(from: published.trimmingCharacters(in: .whitespacesAndNewlines))
        headlines.append(MarketHeadline(title: title, url: url, date: date))
    }
}
