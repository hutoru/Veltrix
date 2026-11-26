import SwiftUI

struct GlobalSearchScreen: View {
    @EnvironmentObject private var model: VeltrixModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var trade: TradeIntent?
    @FocusState private var focused: Bool

    private var term: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        PageScroll {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.vxMuted)
                TextField("Search assets and operations", text: $query)
                    .focused($focused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("global.search")
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Clear search"))
                }
            }
            .padding(.leading, 12)
            .frame(minHeight: 48)
            .background(Color.vxCard, in: RoundedRectangle(cornerRadius: 15))
            results
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .onAppear { if query.isEmpty { focused = true } }
        .fullScreenCover(item: $trade) { TradeScreen(intent: $0) }
    }

    @ViewBuilder private var results: some View {
        let favorites = Asset.catalog.filter { model.favorites.contains($0.id) }
        let recent = model.recentAssets.filter { !model.favorites.contains($0.id) }
        let assets = term.isEmpty ? favorites + recent : Asset.catalog.filter { asset in
            let available = !asset.isTokenizedStock || model.quotes[asset.id]?.price != nil
                || model.portfolio.positions[asset.id] != nil
            return available && matches(asset.name, asset.ticker)
        }
        let actions = TradeAction.allCases.filter { matches($0.rawValue, L.text($0.rawValue.capitalized)) }
        let entries = term.isEmpty ? [] : model.portfolio.entries.reversed().filter {
            $0.kind != .adjustment && matches($0.kind.localized, Asset.ticker($0.asset), model.hide ? "" : $0.note)
        }
        let cards = term.isEmpty || model.hide ? [] : model.cards.filter { matches($0.name) }
        let showSettings = matches(L.text("Settings"))
        let showCards = matches(L.text("Cards"))
        let showActivity = matches(L.text("Activity"))
        if !assets.isEmpty {
            Text("Assets").font(.headline)
            ForEach(assets) { asset in
                NavigationLink(value: asset) {
                    HStack(spacing: 10) {
                        CoinIcon(asset: asset, url: model.quotes[asset.id]?.image, size: 34)
                        Text(verbatim: asset.name)
                        Spacer()
                        Text(verbatim: asset.ticker).foregroundStyle(Color.vxMuted)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("global.asset." + asset.ticker)
            }
        }
        if !actions.isEmpty {
            Text("Operations Center").font(.headline)
            ForEach(actions) { action in
                Button {
                    focused = false
                    trade = TradeIntent(action: action)
                } label: {
                    OperationsRow(title: action.title, icon: action.icon)
                }
                .buttonStyle(.plain)
            }
        }
        if !entries.isEmpty {
            Text("Activity").font(.headline)
            ForEach(Array(entries.prefix(30))) { entry in
                NavigationLink { EntryScreen(entry: entry) } label: { EntryRow(entry: entry) }
                    .buttonStyle(.plain)
            }
        }
        ForEach(cards) { card in
            NavigationLink { CardsScreen(initialCard: card.id) } label: {
                OperationsRow(title: LocalizedStringKey(card.name), icon: "creditcard")
            }
            .buttonStyle(.plain)
        }
        if showCards {
            NavigationLink { CardsScreen() } label: { OperationsRow(title: "Cards", icon: "creditcard") }
                .buttonStyle(.plain)
        }
        if showActivity {
            NavigationLink { ActivityScreen() } label: { OperationsRow(title: "Activity", icon: "clock") }
                .buttonStyle(.plain)
        }
        if showSettings {
            NavigationLink { SettingsScreen() } label: { OperationsRow(title: "Settings", icon: "gearshape") }
                .buttonStyle(.plain)
        }
        if !term.isEmpty && assets.isEmpty && actions.isEmpty && entries.isEmpty && cards.isEmpty
            && !showCards && !showActivity && !showSettings {
            Text("No results").foregroundStyle(Color.vxMuted)
        }
    }

    private func matches(_ terms: String...) -> Bool {
        term.isEmpty || terms.contains { $0.localizedCaseInsensitiveContains(term) }
    }
}
