import PhotosUI
import SwiftUI
import UIKit

struct ProfileAvatar: View {
    var size: CGFloat
    @AppStorage("profileAvatar") private var avatar = Data()
    var body: some View {
        Group {
            if let picture = UIImage(data: avatar) {
                Image(uiImage: picture).resizable().scaledToFill()
            } else {
                VeltrixMark().fill(Color.vxHighlight).padding(size * 0.25)
            }
        }
        .frame(width: size, height: size).background(Color.vxSurface).clipShape(Circle())
        .accessibilityHidden(true)
    }
}

struct ProfileScreen: View {
    @EnvironmentObject private var model: VeltrixModel
    @AppStorage("profileName") private var name = ""
    @AppStorage("profileUsername") private var username = ""
    @AppStorage("profileAvatar") private var avatar = Data()
    @AppStorage("profileCreatedAt") private var createdAt = 0.0
    @State private var picture: PhotosPickerItem?
    @State private var photoError = false
    @State private var range = ChartRange.week
    @State private var candles = false

    private var portfolio: Portfolio { model.portfolio }
    private var trades: [Entry] { portfolio.entries.filter { [.buy, .sell, .swap].contains($0.kind) } }
    private var realizedTrades: [Entry] { trades.filter { $0.profit != nil } }
    private var samples: [ChartSample] { portfolio.chart(range: range, candles: candles) }

    var body: some View {
        PageScroll {
            HStack {
                Text("Profile").font(.largeTitle.bold())
                Spacer()
                NavigationLink {
                    SettingsScreen()
                } label: { Image(systemName: "gearshape").frame(width: 44, height: 44) }
                .accessibilityIdentifier("profile.settings").accessibilityLabel(Text("Settings"))
            }
            HStack(spacing: 14) {
                PhotosPicker(selection: $picture, matching: .images) {
                    ProfileAvatar(size: 72).overlay(alignment: .bottomTrailing) {
                        Image(systemName: "pencil.circle.fill").font(.title3).foregroundStyle(Color.vxHighlight)
                    }
                }.accessibilityLabel(Text("Choose profile photo"))
                VStack(alignment: .leading, spacing: 5) {
                    Text(verbatim: name.isEmpty ? L.text("My profile") : name).font(.title2.bold())
                    if !username.isEmpty { Text(verbatim: "@" + username).font(.subheadline).foregroundStyle(Color.vxMuted) }
                    Text(verbatim: "\(trades.count) " + L.text("Trades")).font(.caption).foregroundStyle(Color.vxMuted)
                    if createdAt > 0 {
                        LabeledContent("Profile created", value: Date(timeIntervalSince1970: createdAt).formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2).foregroundStyle(Color.vxMuted)
                    }
                }
            }
            HStack {
                NavigationLink("Edit profile") { SettingsScreen() }.buttonStyle(.bordered)
                NavigationLink("Cards") { CardsScreen() }.buttonStyle(.bordered)
                    .accessibilityIdentifier("profile.cards")
            }
            CountValue(text: model.money(try? portfolio.value(prices: model.prices)))
                .font(.system(size: 42, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.4)
            HStack(spacing: 12) {
                metric("Available cash", value: model.money(try? portfolio.freeCash()))
                metric("Unrealized P&L", value: model.signedMoney(try? portfolio.unrealized(prices: model.prices)))
            }
            Divider().overlay(Color.vxSeparator)
            if !model.hide {
                VeltrixChart(samples: samples, range: $range, candles: $candles, allowsCandles: true,
                           ranges: [.day, .week, .month, .all]) { model.money($0) }
                LabeledContent("Realized P&L", value: model.signedMoney(periodProfit))
                allocation
            }
            Text("Open positions").font(.headline)
            if portfolio.positions.isEmpty {
                Text("No positions yet").font(.subheadline).foregroundStyle(Color.vxMuted)
            }
            ForEach(Asset.catalog.filter { portfolio.positions[$0.id] != nil }) { coin in
                NavigationLink(value: coin) {
                    HStack {
                        CoinIcon(asset: coin, url: model.quotes[coin.id]?.image, size: 30)
                        Text(verbatim: coin.name)
                        Spacer()
                        if let position = portfolio.positions[coin.id] { Text(verbatim: model.units(position.units)) }
                    }.frame(minHeight: 48).contentShape(Rectangle())
                }.buttonStyle(.plain)
                Divider().overlay(Color.vxSeparator)
            }
            let closed = Asset.catalog.filter { coin in
                portfolio.positions[coin.id] == nil && realizedTrades.contains { $0.asset == coin.id }
            }
            if !closed.isEmpty {
                Text("Closed positions").font(.headline)
                ForEach(closed) { coin in
                    let profit = try? realizedTrades.filter { $0.asset == coin.id }.compactMap(\.profit).reduce(0, MoneyMath.add)
                    NavigationLink(value: coin) {
                        HStack {
                            CoinIcon(asset: coin, url: model.quotes[coin.id]?.image, size: 30)
                            Text(verbatim: coin.name)
                            Spacer()
                            Text(verbatim: model.money(profit)).monospacedDigit()
                        }.frame(minHeight: 48).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    Divider().overlay(Color.vxSeparator)
                }
            }
            if !realizedTrades.isEmpty {
                Text("Realized trades").font(.headline)
                ForEach(realizedTrades.reversed()) { entry in
                    NavigationLink { EntryScreen(entry: entry) } label: { EntryRow(entry: entry) }
                        .buttonStyle(.plain)
                }
            }
        }
        .onAppear {
            if createdAt == 0 {
                createdAt = (model.ledger.portfolios.map(\.createdAt).min() ?? .now).timeIntervalSince1970
            }
        }
        .task(id: picture) {
            guard let picture else { return }
            do {
                guard let bytes = try await picture.loadTransferable(type: Data.self),
                      let image = UIImage(data: bytes),
                      let thumbnail = await image.byPreparingThumbnail(ofSize: CGSize(width: 224, height: 224)),
                      let encoded = thumbnail.jpegData(compressionQuality: 0.83) else { throw CocoaError(.fileReadCorruptFile) }
                try Task.checkCancellation()
                avatar = encoded
            } catch {
                if !Task.isCancelled { photoError = true }
            }
        }
        .alert("Photo unavailable", isPresented: $photoError) { Button("OK", role: .cancel) {} }
    }

    private func metric(_ label: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(Color.vxMuted)
            CountValue(text: value).font(.headline).lineLimit(1).minimumScaleFactor(0.5)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var allocation: some View {
        if let total = try? portfolio.value(prices: model.prices), total > 0 {
            let weights = Asset.catalog.compactMap { asset -> (Asset, Decimal)? in
                guard let position = portfolio.positions[asset.id], let price = model.prices[asset.id],
                      let weight = try? MoneyMath.divide(MoneyMath.multiply(price, position.units), total) else { return nil }
                return (asset, weight)
            }.sorted { $0.1 > $1.1 }
            if !weights.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Portfolio allocation").font(.headline)
                    ForEach(Array(weights.prefix(5)), id: \.0) { asset, weight in
                        HStack(spacing: 12) {
                            CoinIcon(asset: asset, url: model.quotes[asset.id]?.image, size: 24)
                            Text(verbatim: asset.ticker).font(.caption.weight(.semibold)).frame(width: 46, alignment: .leading)
                            ProgressView(value: min(1, max(0, NSDecimalNumber(decimal: weight).doubleValue)))
                            Text(verbatim: Display.percent(weight * 100)).font(.caption.monospacedDigit())
                                .frame(minWidth: 55, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    private var periodProfit: Decimal? {
        let start = range.start(from: .now) ?? .distantPast
        return try? realizedTrades.filter { $0.date >= start }.compactMap(\.profit).reduce(0, MoneyMath.add)
    }
}
