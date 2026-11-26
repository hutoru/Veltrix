import SwiftUI

struct VeltrixBalanceCard: View {
    @EnvironmentObject private var model: VeltrixModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var balanceSize: CGFloat = 47
    @AppStorage("homeChartVisible") private var chartVisible = true
    @Binding var range: ChartRange
    let portfolio: Portfolio
    let value: Decimal?
    let openChart: () -> Void

    var body: some View {
        let now = Date()
        let liveValue = try? portfolio.value(prices: model.usablePrices)
        let period = portfolio.performance(since: range.start(from: now) ?? .distantPast,
                                           until: now, liveValue: liveValue).change
        let samples = portfolio.chart(range: range, performance: true, liveValue: liveValue, now: now)
        let hasLine = zip(samples, samples.dropFirst()).contains { pair in
            pair.0.series == pair.1.series && pair.1.date.timeIntervalSince(pair.0.date) >= 30
        }
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text("Portfolio value").font(.subheadline.weight(.medium))
                Button {
                    withAnimation(reduceMotion || UITestMode.enabled ? nil : .easeOut(duration: 0.2)) {
                        model.hide.toggle()
                    }
                    Feedback.tap()
                } label: {
                    Image(systemName: model.hide ? "eye.slash" : "eye")
                        .font(.footnote).frame(width: 44, height: 44)
                }
                .accessibilityLabel(Text(model.hide ? "Show balances" : "Hide balances"))
                Spacer(minLength: 2)
                Menu {
                    Picker("Display currency", selection: $model.currency) {
                        ForEach(Fiat.currencies, id: \.self) { code in
                            Text(verbatim: code).tag(code)
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(verbatim: model.currency)
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                    }
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .padding(.horizontal, 10).frame(minHeight: 44)
                }
                .accessibilityLabel(Text("Display currency"))
            }
            .foregroundStyle(Color.vxHighlight)
            CountValue(text: model.money(value, fixedDigits: 2))
                .font(.system(size: balanceSize, weight: .semibold))
                .tracking(-1.5).lineLimit(1).minimumScaleFactor(0.25)
                .accessibilityIdentifier("portfolio.total")
            if !model.hide {
                HStack(spacing: 7) {
                    if let period, hasLine || period.value != 0 {
                        Text(verbatim: model.signedMoney(period.value))
                        ChangeText(change: period.percent)
                    } else {
                        Text("Not enough history").foregroundStyle(Color.vxMuted)
                    }
                }.font(.subheadline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.65)
                if chartVisible && hasLine {
                    VeltrixChart(samples: samples, range: $range, candles: .constant(false), allowsCandles: false,
                                 height: 62, mini: true) { model.signedMoney($0) }
                        .allowsHitTesting(false)
                }
                chartControls
            }
            HStack(spacing: 6) {
                Text("Available cash").foregroundStyle(Color.vxMuted)
                CountValue(text: model.money(try? portfolio.freeCash(), fixedDigits: 2))
                    .lineLimit(1).minimumScaleFactor(0.4)
            }.font(.caption.monospacedDigit())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chartControls: some View {
        HStack(spacing: 4) {
            ForEach([ChartRange.day, .week, .month, .all], id: \.self) { period in
                Button {
                    range = period
                    Feedback.tap()
                } label: {
                    Text(LocalizedStringKey(period.displayTitle))
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundStyle(range == period ? Color.vxText : Color.vxMuted)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(range == period ? Color.vxText.opacity(0.11) : .clear, in: Capsule())
                }
                .accessibilityAddTraits(range == period ? .isSelected : [])
            }
            Button {
                chartVisible.toggle()
                Feedback.tap()
            } label: {
                Image(systemName: chartVisible ? "waveform.path" : "eye.slash")
                    .font(.caption.weight(.medium))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(Text(chartVisible ? "Hide portfolio chart" : "Show portfolio chart"))
            Button(action: openChart) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption.weight(.medium))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(Text("Portfolio history"))
        }
    }

}
