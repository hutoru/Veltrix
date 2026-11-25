import SwiftUI

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
    let asset: Asset
    let url: URL?
    var size: CGFloat = 39

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFit()
            } else {
                Text(verbatim: String(asset.ticker.prefix(2)))
                    .font(.system(size: size * 0.33, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.vxHighlight)
            }
        }
        .frame(width: size, height: size)
        .background(Color.vxAccent.opacity(0.12), in: Circle())
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
        Text(verbatim: Display.percent(change))
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(change.map { $0 >= 0 ? Color.vxUp : .vxDown } ?? .vxMuted)
    }
}
