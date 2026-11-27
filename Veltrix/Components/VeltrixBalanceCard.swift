import SwiftUI

struct PortfolioBalanceHeader: View {
    @Environment(\.veltrixTheme) private var theme
    @EnvironmentObject private var model: VeltrixModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var balanceSize: CGFloat = 46

    let portfolio: Portfolio
    let value: Decimal?

    var body: some View {
        let now = Date()
        let change = portfolio.performance(since: .distantPast, until: now,
                                           liveValue: try? portfolio.value(prices: model.usablePrices),
                                           includesPoints: false).change
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Menu {
                    ForEach(model.ledger.portfolios) { item in
                        Button {
                            _ = model.execute(.selectPortfolio(item.id), showFeedback: false)
                        } label: {
                            if item.id == portfolio.id { Label(item.name, systemImage: "checkmark") }
                            else { Text(verbatim: item.name) }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(verbatim: portfolio.name).font(.subheadline)
                            .lineLimit(1)
                        Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(theme.muted)
                    .frame(minHeight: 44)
                }
                .accessibilityLabel(Text("Portfolios"))
                .accessibilityValue(Text(verbatim: portfolio.name))
                Spacer(minLength: 4)
                Button {
                    withAnimation(reduceMotion || UITestMode.enabled ? nil : .easeOut(duration: 0.2)) {
                        model.hide.toggle()
                    }
                    Feedback.tap()
                } label: {
                    Image(systemName: model.hide ? "eye.slash" : "eye")
                        .font(.subheadline)
                        .foregroundStyle(theme.muted)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(model.hide ? "Show balances" : "Hide balances"))
            }

            CountValue(text: model.money(value, fixedDigits: 2))
                .font(.system(size: balanceSize, weight: .medium))
                .tracking(-1.2)
                .lineLimit(1)
                .minimumScaleFactor(0.3)
                .accessibilityIdentifier("portfolio.total")

            if !model.hide {
                if let change {
                    let tint: Color = change.value < 0 ? theme.negative : (change.value > 0 ? theme.positive : theme.muted)
                    HStack(spacing: 6) {
                        CountValue(text: model.signedMoney(change.value, fixedDigits: 2))
                            .foregroundStyle(tint)
                        if let percent = change.percent {
                            CountValue(text: Display.percent(percent))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(tint)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(tint.opacity(0.13), in: Capsule())
                        }
                    }
                    .font(.subheadline.weight(.medium).monospacedDigit())
                    .lineLimit(1).minimumScaleFactor(0.65)
                } else {
                    Text("Not enough history").font(.subheadline).foregroundStyle(theme.muted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
