import SwiftUI

struct OperationsScreen: View {
    @State private var trade: TradeIntent?
    @State private var scanner = false

    var body: some View {
        PageScroll {
            Text("Operations Center")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(TradeAction.allCases) { action in
                    Button {
                        Feedback.tap()
                        trade = TradeIntent(action: action)
                    } label: {
                        OperationsRow(title: action.title, icon: action.icon)
                    }
                    .accessibilityIdentifier("trade.action." + action.rawValue)
                    Divider().overlay(Color.vxSeparator)
                }
                Button {
                    Feedback.tap()
                    scanner = true
                } label: {
                    OperationsRow(title: "Scan QR code", icon: "qrcode.viewfinder")
                }
            }
            .buttonStyle(.plain)
            VStack(spacing: 0) {
                NavigationLink { ActivityScreen() } label: {
                    OperationsRow(title: "Activity", icon: "clock.arrow.circlepath")
                }
                .accessibilityIdentifier("operations.activity")
                Divider().overlay(Color.vxSeparator)
                NavigationLink { CardsScreen() } label: {
                    OperationsRow(title: "Cards", icon: "creditcard")
                }
                .accessibilityIdentifier("operations.cards")
                Divider().overlay(Color.vxSeparator)
                NavigationLink { PortfolioAnalyticsScreen() } label: {
                    OperationsRow(title: "Analytics", icon: "chart.xyaxis.line")
                }
                .accessibilityIdentifier("operations.analytics")
            }
            .buttonStyle(.plain)
        }
        .fullScreenCover(item: $trade) { TradeScreen(intent: $0) }
        .fullScreenCover(isPresented: $scanner) { QRScanner() }
    }
}

struct OperationsRow: View {
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
                .foregroundStyle(Color.vxMuted)
                .accessibilityHidden(true)
        }
        .font(.subheadline.weight(.medium))
        .frame(minHeight: 47)
        .contentShape(Rectangle())
    }
}
