import SwiftUI

struct OperationsScreen: View {
    @Environment(\.veltrixTheme) private var theme
    @EnvironmentObject private var model: VeltrixModel
    @State private var trade: TradeIntent?
    @State private var scanner = false
    @AppStorage("recentTradeActions") private var recentIDs = ""

    private var recent: [TradeAction] {
        recentIDs.split(separator: ",").compactMap { TradeAction(rawValue: String($0)) }
    }

    private func open(_ action: TradeAction) {
        recentIDs = ([action] + recent.filter { $0 != action }).prefix(3).map(\.rawValue).joined(separator: ",")
        Feedback.tap()
        trade = TradeIntent(action: action)
    }

    private var actions: [TradeAction] {
        let preferred = model.quickActions
        return preferred + TradeAction.allCases.filter { !preferred.contains($0) }
    }

    var body: some View {
        PageScroll(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Operations Center").font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                Text("Available balance").font(.caption).foregroundStyle(theme.muted)
                CountValue(text: model.money(try? model.portfolio.freeCash(), fixedDigits: 2))
                    .font(.largeTitle.weight(.medium)).lineLimit(1).minimumScaleFactor(0.5)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 93), spacing: 7)], spacing: 7) {
                ForEach(actions) { action in
                    Button { open(action) } label: {
                        VStack(spacing: 6) {
                            Image(systemName: action.icon).font(.system(size: 20)).accessibilityHidden(true)
                            Text(action.title).font(.subheadline.weight(.medium)).lineLimit(1).minimumScaleFactor(0.6)
                        }.padding(.horizontal, 6).frame(maxWidth: .infinity, minHeight: 66)
                            .background(theme.surface, in: RoundedRectangle(cornerRadius: 16))
                    }.buttonStyle(.plain).accessibilityIdentifier("trade.action." + action.rawValue)
                }
            }
            if !recent.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent actions").font(.headline)
                    HStack {
                        ForEach(recent) { action in
                            Button { open(action) } label: { Label(action.title, systemImage: action.icon) }
                                .buttonStyle(.bordered).lineLimit(1).minimumScaleFactor(0.6)
                        }
                    }
                }
            }
            VStack(spacing: 0) {
                Button { open(.swap) } label: { OperationsRow(title: "Quick swap", icon: "arrow.left.arrow.right") }
                Divider().overlay(theme.separator)
                Button { Feedback.tap(); scanner = true } label: { OperationsRow(title: "Scan QR code", icon: "qrcode.viewfinder") }
                Divider().overlay(theme.separator)
                NavigationLink { ActivityScreen() } label: { OperationsRow(title: "Activity", icon: "clock.arrow.circlepath") }
                    .accessibilityIdentifier("operations.activity")
                Divider().overlay(theme.separator)
                NavigationLink { CardsScreen() } label: { OperationsRow(title: "Card Studio", icon: "creditcard") }
                    .accessibilityIdentifier("operations.cards")
                Divider().overlay(theme.separator)
                NavigationLink { PortfolioAnalyticsScreen() } label: { OperationsRow(title: "Analytics", icon: "chart.xyaxis.line") }
                    .accessibilityIdentifier("operations.analytics")
                Divider().overlay(theme.separator)
                NavigationLink { ActivityScreen(showOrders: true) } label: { OperationsRow(title: "Limit orders", icon: "list.bullet.rectangle") }
                Divider().overlay(theme.separator)
                NavigationLink { EarnScreen() } label: { OperationsRow(title: "Earn", icon: "chart.bar.xaxis") }
            }.buttonStyle(.plain).panel(padding: 12)
        }
        .fullScreenCover(item: $trade) { TradeScreen(intent: $0) }
        .fullScreenCover(isPresented: $scanner) { QRScanner() }
    }
}

struct OperationsRow: View {
    @Environment(\.veltrixTheme) private var theme
    let title: LocalizedStringKey
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 26)
                .accessibilityHidden(true)
            Text(title)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.muted)
                .accessibilityHidden(true)
        }
        .font(.subheadline.weight(.medium))
        .frame(minHeight: 47)
        .contentShape(Rectangle())
    }
}
