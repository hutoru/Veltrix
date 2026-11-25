import SwiftUI
import UIKit

struct MarketStatus: View {
    @EnvironmentObject private var model: VeltrixModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let date = model.quoteDate
            let stale = model.marketMessage != nil || (date.map { context.date.timeIntervalSince($0) > 300 } ?? true)
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Circle().fill(stale ? Color.vxMuted : Color.vxUp).frame(width: 6, height: 6)
                    if let date {
                        Text(stale ? "Saved quotes" : "CoinGecko quotes")
                        Text(date, style: .relative)
                        Text("ago")
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
            .foregroundStyle(Color.vxMuted)
        }
    }
}

struct CoinIcon: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let asset: Asset
    let url: URL?
    var size: CGFloat = 39

    var body: some View {
        Group {
            if let bundled = UIImage(named: "coin-" + asset.id) {
                Image(uiImage: bundled).resizable().scaledToFit()
            } else {
                AsyncImage(url: url, transaction: Transaction(animation: reduceMotion ? nil : .easeOut(duration: 0.18))) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit()
                    } else {
                        Text(verbatim: String(asset.ticker.prefix(2)))
                            .font(.system(size: size * 0.33, weight: .bold))
                            .foregroundStyle(Color.vxText)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .background(Color.vxSurface, in: Circle())
        .clipShape(Circle())
        .accessibilityHidden(true)
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
    let change: Decimal?

    var body: some View {
        let rounded = change.map { MoneyMath.round($0, scale: 2) }
        Text(verbatim: Display.percent(change))
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(rounded.map { $0 == 0 ? Color.vxMuted : ($0 > 0 ? .vxUp : .vxDown) } ?? .vxMuted)
    }
}


struct MarketSparkline: View {
    let values: [Decimal]
    var body: some View {
        let prices = values.map { NSDecimalNumber(decimal: $0).doubleValue }.filter(\.isFinite)
        Canvas { context, size in
            guard prices.count > 1, let minimum = prices.min(), let maximum = prices.max() else { return }
            let span = maximum - minimum
            let line = Path { path in
                for (index, price) in prices.enumerated() {
                    let x = size.width * CGFloat(index) / CGFloat(prices.count - 1)
                    let y = span > 0 ? size.height - 2 - CGFloat((price - minimum) / span) * (size.height - 4) : size.height / 2
                    if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            let rising = (prices.last ?? 0) >= (prices.first ?? 0)
            context.stroke(line, with: .color(rising ? .vxUp : .vxDown),
                           style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
        }.accessibilityHidden(true)
    }
}
