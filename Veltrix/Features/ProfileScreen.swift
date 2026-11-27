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
}
