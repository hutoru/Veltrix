import Foundation

struct WidgetData: Codable, Equatable {
    struct Row: Codable, Equatable {
        let ticker: String
        let detail: String
    }

    static let group = "group.app.veltrix.simulation"
    static var location: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
            .appendingPathComponent("VeltrixWidget.json")
    }

    let appearance: String
    let balance: String
    let change: String
    let assets: [Row]
    let favorites: [Row]
    let earn: [Row]
    let graph: [[Double]]
    let updated: Date

    static func load() -> Self? {
        guard let location, let bytes = try? Data(contentsOf: location) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: bytes)
    }
}
