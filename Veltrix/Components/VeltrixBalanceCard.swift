import SwiftUI

struct PortfolioBalanceHeader: View {
    @Environment(\.veltrixTheme) private var theme
    @EnvironmentObject private var model: VeltrixModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var slide: CGFloat = 0
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
        .offset(x: reduceMotion ? 0 : slide)
        .simultaneousGesture(DragGesture(minimumDistance: 22)
            .updating($slide) { gesture, state, _ in
                guard model.ledger.portfolios.count > 1, abs(gesture.translation.width) > abs(gesture.translation.height) * 2 else { return }
                state = min(20, max(-20, gesture.translation.width * 0.18))
            }
            .onEnded { gesture in
                guard abs(gesture.translation.width) > max(55, abs(gesture.translation.height) * 2) else { return }
                let portfolios = model.ledger.portfolios
                guard portfolios.count > 1, let index = portfolios.firstIndex(where: { $0.id == portfolio.id }) else { return }
                let next = index + (gesture.translation.width < 0 ? 1 : -1)
                guard portfolios.indices.contains(next) else { return }
                if model.execute(.selectPortfolio(portfolios[next].id), showFeedback: false) { Feedback.tap() }
            })
        .overlay(alignment: .top) {
            if model.ledger.portfolios.count > 1 {
                HStack(spacing: 4) {
                    ForEach(model.ledger.portfolios.prefix(8)) { item in
                        Circle().fill(item.id == portfolio.id ? theme.text : theme.separator).frame(width: 4, height: 4)
                    }
                }.padding(.top, 2).allowsHitTesting(false).accessibilityHidden(true)
            }
        }
    }
}
