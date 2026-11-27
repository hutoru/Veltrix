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
                VeltrixMark().fill(.white).padding(size * 0.25)
            }
        }
        .frame(width: size, height: size)
        .background(Color.black, in: Circle())
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

struct ProfileScreen: View {
    @Environment(\.veltrixTheme) private var theme
    @EnvironmentObject private var model: VeltrixModel
    @AppStorage("profileName") private var name = ""
    @AppStorage("profileUsername") private var username = ""
    @AppStorage("profileAvatar") private var avatar = Data()
    @AppStorage("profileCreatedAt") private var createdAt = 0.0
    @State private var picture: PhotosPickerItem?
    @State private var photoError = false
    private var portfolio: Portfolio { model.portfolio }
    private var trades: [Entry] { portfolio.entries.filter { [.buy, .sell, .swap].contains($0.kind) } }

    var body: some View {
        PageScroll {
            HStack {
                Text("Profile").font(.largeTitle.weight(.semibold))
                Spacer()
                NavigationLink {
                    SettingsScreen()
                } label: { Image(systemName: "gearshape").frame(width: 44, height: 44) }
                .accessibilityIdentifier("profile.settings").accessibilityLabel(Text("Settings"))
            }
            HStack(spacing: 14) {
                PhotosPicker(selection: $picture, matching: .images) {
                    ProfileAvatar(size: 72).overlay(alignment: .bottomTrailing) {
                        Image(systemName: "pencil.circle.fill").font(.title3).foregroundStyle(theme.highlight)
                    }
                }.accessibilityLabel(Text("Choose profile photo"))
                VStack(alignment: .leading, spacing: 5) {
                    Text(verbatim: name.isEmpty ? L.text("My profile") : name).font(.title2.weight(.semibold))
                    if !username.isEmpty { Text(verbatim: "@" + username).font(.subheadline).foregroundStyle(theme.muted) }
                    Text(verbatim: L.trades(trades.count)).font(.caption).foregroundStyle(theme.muted)
                    if createdAt > 0 {
                        LabeledContent("Profile created", value: Date(timeIntervalSince1970: createdAt).formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2).foregroundStyle(theme.muted)
                    }
                }
            }
            HStack {
                NavigationLink("Edit profile") { SettingsScreen() }.buttonStyle(.bordered)
                NavigationLink("Cards") { CardsScreen() }.buttonStyle(.bordered)
                    .accessibilityIdentifier("profile.cards")
            }
            overview
            VStack(spacing: 0) {
                NavigationLink { PortfolioAnalyticsScreen() } label: {
                    OperationsRow(title: "Analytics", icon: "chart.xyaxis.line")
                }
                Divider().overlay(theme.separator)
                NavigationLink { ActivityScreen() } label: {
                    OperationsRow(title: "Activity", icon: "clock.arrow.circlepath")
                }
                Divider().overlay(theme.separator)
                NavigationLink { favorites } label: {
                    OperationsRow(title: "Favorites", icon: "star")
                }
                Divider().overlay(theme.separator)
                NavigationLink { PortfolioWorkspace() } label: {
                    OperationsRow(title: "Portfolios", icon: "square.stack")
                }
            }.buttonStyle(.plain).panel(padding: 12)
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

    private var overview: some View {
        let now = Date()
        let amount = try? portfolio.value(prices: model.usablePrices)
        let performance = portfolio.performance(since: .distantPast, until: now, liveValue: amount, includesPoints: false)
        let daily = try? portfolio.daily(now: now, prices: model.usablePrices)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Portfolio value").font(.caption).foregroundStyle(theme.muted)
            CountValue(text: model.money(try? portfolio.value(prices: model.prices)))
                .font(.largeTitle.weight(.medium)).lineLimit(1).minimumScaleFactor(0.5)
            LabeledContent("Total return", value: model.hide ? "••••" : Display.percent(performance.change?.percent))
            LabeledContent("24h P&L", value: model.signedMoney(daily?.value))
            LabeledContent("Assets", value: String(portfolio.positions.count))
            LabeledContent("Trades", value: String(trades.count))
            LabeledContent("Realized P&L", value: model.signedMoney(try? portfolio.realized()))
            LabeledContent("Unrealized P&L", value: model.signedMoney(try? portfolio.unrealized(prices: model.prices)))
            if !model.hide { PortfolioAllocation(portfolio: portfolio) }
        }.font(.subheadline).panel()
    }

    private var favorites: some View {
        PageScroll {
            if model.favorites.isEmpty { Text("No favorites yet").foregroundStyle(theme.muted) }
            ForEach(Asset.catalog.filter { model.favorites.contains($0.id) }) { asset in
                NavigationLink(value: asset) {
                    OperationsRow(title: LocalizedStringKey(asset.name), icon: "star")
                }.buttonStyle(.plain)
            }
        }.navigationTitle("Favorites").navigationBarTitleDisplayMode(.inline)
    }
}

struct PortfolioWorkspace: View {
    @EnvironmentObject private var model: VeltrixModel
    @State private var adding = false

    var body: some View {
        PageScroll {
            ForEach(model.ledger.portfolios) { portfolio in
                Button { _ = model.execute(.selectPortfolio(portfolio.id), showFeedback: false) } label: {
                    HStack {
                        Text(verbatim: portfolio.name)
                        Spacer()
                        if portfolio.id == model.ledger.selected { Image(systemName: "checkmark") }
                    }.panel(padding: 12)
                }.buttonStyle(.plain)
                    .accessibilityAddTraits(portfolio.id == model.ledger.selected ? .isSelected : [])
            }
            Button("Create portfolio") { adding = true }.buttonStyle(PrimaryButtonStyle())
        }
        .navigationTitle("Portfolios").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $adding) { SettingsForm(panel: .newPortfolio) }
    }
}
