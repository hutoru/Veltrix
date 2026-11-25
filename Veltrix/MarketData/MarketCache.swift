import Foundation

actor MarketCache {
    private let directory: URL?

    init(directory: URL? = try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                                                        appropriateFor: nil, create: true)) {
        self.directory = directory?.appendingPathComponent("VELTRIX market", isDirectory: true)
    }

    func read<Value: Codable & Sendable>(_ type: Value.Type, key: String) -> Cached<Value>? {
        guard let directory, let data = try? Data(contentsOf: directory.appendingPathComponent(key + ".json")) else { return nil }
        return try? JSONDecoder().decode(Cached<Value>.self, from: data)
    }

    func write<Value: Codable & Sendable>(_ value: Value, key: String) {
        guard let directory,
              let data = try? JSONEncoder().encode(Cached(value: value, saved: Date())) else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appendingPathComponent(key + ".json"), options: .atomic)
        } catch {
            // Market cache can be rebuilt from its public source.
        }
    }
}

struct Cached<Value: Codable & Sendable>: Codable, Sendable {
    let value: Value
    let saved: Date
}
