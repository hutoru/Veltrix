import ImageIO
import SwiftUI
import UIKit

struct MarketStatus: View {
    @Environment(\.veltrixTheme) private var theme
    @EnvironmentObject private var model: VeltrixModel

    var body: some View {
        if UITestMode.enabled {
            status(at: .now)
        } else {
            TimelineView(.periodic(from: .now, by: 30)) { status(at: $0.date) }
        }
    }

    private func status(at now: Date) -> some View {
        let date = model.quoteDate
        let stale = model.usablePrices.isEmpty || (date.map { now.timeIntervalSince($0) > 300 } ?? true)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Circle().fill(stale ? theme.muted : theme.positive).frame(width: 6, height: 6)
                if let date {
                    Text(stale ? "Saved quotes" : "Market quotes")
                    if !UITestMode.enabled {
                        Text(date, style: .relative)
                        Text("ago")
                    }
                } else {
                    Text(model.loading ? "Updating market data" : "Awaiting market data")
                }
            }
            if let message = model.marketMessage { Text(verbatim: message) }
            if let date = model.rates[model.currency]?.date, model.currency != "USD" {
                Text("FX reference date · \(date)")
            }
        }
        .font(.caption)
        .foregroundStyle(theme.muted)
    }
}

struct CoinIcon: View {
    @Environment(\.veltrixTheme) private var theme
    @Environment(\.displayScale) private var displayScale
    @State private var loaded: LoadedIcon?
    let asset: Asset
    let url: URL?
    var size: CGFloat = 39

    private struct LoadedIcon {
        let url: URL
        let image: UIImage
    }

    var body: some View {
        let imageURL = UITestMode.enabled ? nil : url
        Group {
            if let loaded, loaded.url == imageURL {
                Image(uiImage: loaded.image).resizable().scaledToFit()
            } else if let bundled = UIImage(named: "coin-" + asset.id) {
                let nativePoints = CGFloat(bundled.cgImage?.width ?? 50) / displayScale
                Image(uiImage: bundled).resizable().scaledToFit()
                    .frame(width: min(size, nativePoints), height: min(size, nativePoints))
            } else {
                Text(verbatim: String(asset.ticker.prefix(2)))
                    .font(.system(size: size * 0.33, weight: .medium))
                    .foregroundStyle(theme.text)
            }
        }
        .frame(width: size, height: size)
        .background(theme.elevated, in: Circle())
        .clipShape(Circle())
        .accessibilityHidden(true)
        .task(id: imageURL) {
            guard let imageURL, let image = await CoinImageCache.shared.image(at: imageURL),
                  !Task.isCancelled else { return }
            loaded = LoadedIcon(url: imageURL, image: image)
        }
    }
}

@MainActor private final class CoinImageCache {
    static let shared = CoinImageCache()

    private let images = NSCache<NSURL, UIImage>()
    private var pending: [URL: Task<UIImage?, Never>] = [:]
    private let session: URLSession

    private init() {
        images.totalCostLimit = 12 * 1024 * 1024
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 4 * 1024 * 1024, diskCapacity: 32 * 1024 * 1024,
                                  directory: try? FileManager.default.url(for: .cachesDirectory,
                                                                         in: .userDomainMask,
                                                                         appropriateFor: nil, create: true)
                                      .appendingPathComponent("CoinImages", isDirectory: true))
        config.timeoutIntervalForRequest = 10
        session = URLSession(configuration: config)
    }

    func image(at url: URL) async -> UIImage? {
        guard url.scheme == "https" else { return nil }
        if let image = images.object(forKey: url as NSURL) { return image }
        if let task = pending[url] { return await task.value }
        let task = Task { [session] in
            guard let (data, response) = try? await session.data(from: url),
                  let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
                  data.count <= 2 * 1024 * 1024,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: 256
                  ] as CFDictionary) else { return nil as UIImage? }
            return UIImage(cgImage: thumbnail)
        }
        pending[url] = task
        let image = await task.value
        if let image, let bitmap = image.cgImage {
            images.setObject(image, forKey: url as NSURL, cost: bitmap.bytesPerRow * bitmap.height)
        }
        pending[url] = nil
        return image
    }
}

struct AssetPicker: View {
    let title: LocalizedStringKey
    @Binding var asset: String
    var assets = Asset.catalog

    var body: some View {
        Picker(title, selection: $asset) {
            ForEach(assets) { asset in
                Text(verbatim: "\(asset.ticker) · \(asset.name)").tag(asset.id)
            }
        }
    }
}

struct ChangeText: View {
    @Environment(\.veltrixTheme) private var theme
    let change: Decimal?

    var body: some View {
        let rounded = change.map { MoneyMath.round($0, scale: 2) }
        Text(verbatim: Display.percent(change))
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(rounded.map { $0 == 0 ? theme.muted : ($0 > 0 ? theme.positive : theme.negative) } ?? theme.muted)
    }
}


struct MarketSparkline: View {
    @Environment(\.veltrixTheme) private var theme
    let values: [Decimal]
    var measuredChange: Decimal? = nil
    var body: some View {
        let prices = values.map { NSDecimalNumber(decimal: $0).doubleValue }.filter(\.isFinite)
        Canvas { context, size in
            guard prices.count > 1, let minimum = prices.min(), let maximum = prices.max() else { return }
            let span = maximum - minimum
            let width = max(0, size.width - 4)
            let chartHeight = max(0, size.height - 6)
            let points = prices.enumerated().map { index, price in
                CGPoint(x: 2 + width * CGFloat(index) / CGFloat(prices.count - 1),
                        y: span > 0 ? 3 + (1 - CGFloat((price - minimum) / span)) * chartHeight : size.height / 2)
            }
            guard let start = points.first, let end = points.last else { return }
            let line = Path { path in
                path.move(to: start)
                for index in 1..<points.count {
                    let previous = points[index - 1]
                    let current = points[index]
                    let offset = (current.x - previous.x) / 3
                    path.addCurve(to: current,
                                  control1: CGPoint(x: previous.x + offset, y: previous.y),
                                  control2: CGPoint(x: current.x - offset, y: current.y))
                }
            }
            let change = measuredChange.map { MoneyMath.round($0, scale: 2) } ?? (values.last ?? 0) - (values.first ?? 0)
            let color: Color = change == 0 ? theme.muted : (change > 0 ? theme.positive : theme.negative)
            var fill = line
            fill.addLine(to: CGPoint(x: end.x, y: size.height))
            fill.addLine(to: CGPoint(x: start.x, y: size.height))
            fill.closeSubpath()
            context.fill(fill, with: .linearGradient(Gradient(colors: [color.opacity(0.23), .clear]),
                                                     startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            context.stroke(line, with: .color(color),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            context.fill(Path(ellipseIn: CGRect(x: end.x - 2, y: end.y - 2, width: 4, height: 4)), with: .color(color))
        }.accessibilityHidden(true)
    }
}
