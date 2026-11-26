import Charts
import SwiftUI

struct VeltrixChart: View {
    let samples: [ChartSample]
    @Binding var range: ChartRange
    @Binding var candles: Bool
    let allowsCandles: Bool
    var height: CGFloat = 190
    var compact = false
    var mini = false
    var compareAmounts = false
    var ranges = ChartRange.allCases
    var rangeLabel: (ChartRange) -> String = { $0.displayTitle }
    var format: (Decimal) -> String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    @State private var selected: Date?
    @State private var baseline: Date?
    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1
    @State private var replay: Task<Void, Never>?
    @State private var replayCount: Int?

    private var focus: ChartSample? { selected.flatMap { date in samples.first { $0.date == date } } }
    private var anchor: ChartSample? { baseline.flatMap { date in samples.first { $0.date == date } } }
    private var visible: [ChartSample] {
        let factor = max(1, min(20, zoom * pinch))
        let count = min(samples.count, max(6, Int(Double(samples.count) / Double(factor))))
        return Array(samples.suffix(count))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            if mini {
                if let focus {
                    HStack(spacing: 6) {
                        Text(focus.date.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(Color.vxMuted)
                        Spacer(minLength: 0)
                        Text(verbatim: format(focus.close))
                    }.lineLimit(1).minimumScaleFactor(0.65)
                }
                if samples.isEmpty {
                    Text("No chart data").foregroundStyle(Color.vxMuted)
                } else {
                    plotting.frame(height: height)
                        .accessibilityLabel(Text("Historical chart"))
                        .accessibilityValue(accessibilityValue)
                }
            } else if compact {
                if !samples.isEmpty {
                    plotting.frame(height: height).allowsHitTesting(false)
                        .accessibilityLabel(Text("Portfolio performance"))
                }
            } else if samples.isEmpty || (compareAmounts && samples.count < 2) {
                EmptyPanel(icon: "waveform.path", title: "No chart data", detail: "History appears when values become available.")
            } else {
                readout
                plotting
                    .frame(height: samples.count < 3 ? min(130, height) : height)
                    .accessibilityLabel(Text("Historical chart"))
                    .accessibilityValue(accessibilityValue)
                    .accessibilityAdjustableAction { direction in
                        guard !visible.isEmpty else { return }
                        let index = visible.firstIndex { $0.date == selected } ?? visible.count - 1
                        switch direction {
                        case .increment: selected = visible[min(visible.count - 1, index + 1)].date
                        case .decrement: selected = visible[max(0, index - 1)].date
                        @unknown default: break
                        }
                    }
            }

            if !compact && !mini { controls }
        }
        .onChange(of: range) { _ in clearInteraction() }
        .onChange(of: candles) { _ in clearInteraction() }
        .onChange(of: phase) { state in if state != .active { stopReplay() } }
        .onDisappear { stopReplay() }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 2) {
                ForEach(ranges, id: \.self) { value in
                    Button {
                        range = value
                        Feedback.tap()
                    } label: {
                        Text(verbatim: rangeLabel(value)).font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .foregroundStyle(range == value ? Color.vxHighlight : Color.vxMuted)
                            .background(range == value ? Color.vxAccent.opacity(0.15) : .clear,
                                        in: RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(range == value ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
            .overlay(alignment: .top) { Rectangle().fill(Color.vxSeparator).frame(height: 1) }

            HStack(spacing: 12) {
                if allowsCandles {
                    Button {
                        candles.toggle()
                        Feedback.tap()
                    } label: {
                        Image(systemName: candles ? "chart.line.uptrend.xyaxis" : "chart.bar.xaxis")
                    }
                    .accessibilityLabel(Text(candles ? "Line chart" : "Candlestick chart"))
                }
                if !samples.isEmpty {
                    Button { replay == nil ? startReplay() : stopReplay() } label: {
                        Label(replay == nil ? "Replay" : "Stop", systemImage: replay == nil ? "play.fill" : "stop.fill")
                    }
                    .disabled(samples.count < 2)
                    Button {
                        if baseline != nil { baseline = nil }
                        else { baseline = (focus ?? visible.first)?.date }
                        Feedback.tap()
                    } label: {
                        Label(baseline == nil ? "Compare" : "Clear", systemImage: "scope")
                    }
                    if zoom > 1 {
                        Button { zoom = 1 } label: { Image(systemName: "arrow.uturn.backward") }
                            .accessibilityLabel(Text("Reset zoom"))
                    }
                }
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
            .tint(.vxHighlight)
        }
    }

    private var accessibilityValue: Text {
        if let item = focus ?? visible.last {
            return Text(verbatim: format(item.close)) + Text(" · ") + Text(item.date, style: .date)
        }
        return Text("No chart data")
    }

    private var readout: some View {
        HStack {
            if let value = focus ?? visible.last {
                VStack(alignment: .leading, spacing: 3) {
                    CountValue(text: format(value.close)).font(.title3.weight(.semibold))
                    Text(value.date.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(Color.vxMuted)
                }
            }
            Spacer()
            if let a = anchor, let b = focus, let difference = try? MoneyMath.subtractValuation(b.close, a.close) {
                if compareAmounts {
                    comparison(format(difference), value: difference)
                } else if a.close != 0,
                          let percent = try? MoneyMath.multiply(MoneyMath.divide(difference, a.close), 100) {
                    comparison(Display.percent(percent), value: percent)
                }
            }
        }
        .frame(minHeight: 38, alignment: .leading)
    }

    private func comparison(_ text: String, value: Decimal) -> some View {
        Text(verbatim: text).font(.subheadline.weight(.semibold).monospacedDigit())
            .foregroundStyle(value >= 0 ? Color.vxUp : Color.vxDown)
    }

    private var plotting: some View {
        let plotted = visible
        let data = Array(plotted.prefix(replayCount ?? plotted.count))
        let visibleChange = (plotted.last?.close ?? 0) - (plotted.first?.close ?? 0)
        let periodChange = (samples.last?.close ?? 0) - (samples.first?.close ?? 0)
        let change = MoneyMath.round(mini || compareAmounts ? periodChange : visibleChange, scale: 8)
        let trend = change == 0 ? Color.vxHighlight : (change > 0 ? Color.vxUp : Color.vxDown)
        let hasGaps = plotted.first?.series != plotted.last?.series
        let seriesSizes = Dictionary(grouping: plotted) { $0.series ?? 0 }.mapValues(\.count)
        let prices = plotted.flatMap { sample -> [Double] in
            [double(sample.low ?? sample.close), double(sample.high ?? sample.close)]
        }
        let minimum = prices.min() ?? 0
        let maximum = prices.max() ?? 0
        let padding = max((maximum - minimum) * 0.12, max(abs(maximum) * 0.0001, 1e-12))
        let first = plotted.first?.date ?? .distantPast
        let last = max(plotted.last?.date ?? first, first.addingTimeInterval(1))
        return Chart {
            ForEach(data) { sample in
                if candles, let open = sample.open, let high = sample.high, let low = sample.low {
                    let shade = sample.close >= open ? Color.vxUp : Color.vxDown
                    RuleMark(x: .value("Date", sample.date), yStart: .value("Low", double(low)), yEnd: .value("High", double(high)))
                        .foregroundStyle(shade)
                    RectangleMark(x: .value("Date", sample.date), yStart: .value("Open", double(open)),
                                  yEnd: .value("Close", double(sample.close)), width: .fixed(data.count > 100 ? 2 : 5))
                        .foregroundStyle(shade)
                    if open == sample.close {
                        PointMark(x: .value("Date", sample.date), y: .value("Price", double(open)))
                            .foregroundStyle(shade).symbolSize(8)
                    }
                } else {
                    if plotted.count >= 2 && !hasGaps { AreaMark(x: .value("Date", sample.date), yStart: .value("Floor", minimum - padding),
                             yEnd: .value("Price", double(sample.close)))
                        .interpolationMethod(.linear)
                        .foregroundStyle(LinearGradient(colors: [trend.opacity(0.19), trend.opacity(0.01)],
                                                        startPoint: .top, endPoint: .bottom)) }
                    if plotted.count >= 2 {
                        LineMark(x: .value("Date", sample.date), y: .value("Price", double(sample.close)),
                                 series: .value("Series", sample.series ?? 0))
                            .foregroundStyle(trend)
                            .interpolationMethod(.linear)
                            .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    }
                    if data.count == 1 || seriesSizes[sample.series ?? 0] == 1 ||
                        (compareAmounts && sample.date == plotted.last?.date) {
                        PointMark(x: .value("Date", sample.date), y: .value("Price", double(sample.close)))
                            .foregroundStyle(trend).symbolSize(30)
                    }
                }
            }
            if !mini, let latest = plotted.last, plotted.count > 2, replay == nil {
                RuleMark(y: .value("Latest price", double(latest.close)))
                    .foregroundStyle(trend.opacity(0.36)).lineStyle(StrokeStyle(lineWidth: 0.8, dash: [3, 4]))
            }
            if let anchor, anchor.date >= first, anchor.date <= last {
                RuleMark(x: .value("Date", anchor.date))
                    .foregroundStyle(Color.vxMuted).lineStyle(StrokeStyle(dash: [3, 3]))
            }
            if let focus, focus.date >= first, focus.date <= last {
                RuleMark(x: .value("Date", focus.date))
                    .foregroundStyle(Color.vxHighlight).lineStyle(StrokeStyle(lineWidth: 0.9))
                PointMark(x: .value("Date", focus.date), y: .value("Price", double(focus.close)))
                    .foregroundStyle(Color.vxHighlight).symbolSize(48)
            }
        }
        .chartYScale(domain: (minimum - padding)...(maximum + padding))
        .chartXScale(domain: first...last, range: .plotDimension(padding: compareAmounts ? 12 : 0))
        .chartXAxis {
            if !mini && !compact && (!compareAmounts || last.timeIntervalSince(first) >= 60) {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisValueLabel().foregroundStyle(Color.vxMuted)
                }
            }
        }
        .chartYAxis {
            if !mini && !compact {
                let ticks: AxisMarkValues = compareAmounts && minimum == maximum ? .values([minimum]) : .automatic(desiredCount: 3)
                AxisMarks(position: .trailing, values: ticks) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
                        .foregroundStyle(Color.vxMuted.opacity(0.36))
                    if let amount = value.as(Double.self), amount.isFinite {
                        AxisValueLabel { Text(verbatim: format(Decimal(amount))).font(.caption2) }
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                let plot = geometry[proxy.plotAreaFrame]
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { event in
                        guard !plotted.isEmpty, replay == nil,
                              let date: Date = proxy.value(atX: min(max(event.location.x - plot.minX, 0), plot.width)),
                              let sample = plotted.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }),
                              sample.date != selected else { return }
                        selected = sample.date
                        Feedback.tap()
                    })
                    .simultaneousGesture(MagnificationGesture()
                        .updating($pinch) { value, state, _ in state = value }
                        .onEnded { zoom = min(20, max(1, zoom * $0)) })
                    .accessibilityHidden(true)
                if replay == nil, selected == nil, let latest = plotted.last,
                   let x = proxy.position(forX: latest.date), let y = proxy.position(forY: double(latest.close)) {
                    TimelineView(.animation(minimumInterval: 1 / 24, paused: UITestMode.enabled || reduceMotion || phase != .active)) { timeline in
                        let pulse = reduceMotion ? 0.0 : (sin(timeline.date.timeIntervalSinceReferenceDate * 4) + 1) / 2
                        Canvas { context, _ in
                            let center = CGPoint(x: plot.minX + x, y: plot.minY + y)
                            let radius = 4 + pulse * 3
                            let halo = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                            context.fill(Path(ellipseIn: halo), with: .color(trend.opacity(0.2)))
                            context.fill(Path(ellipseIn: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6)), with: .color(trend))
                        }
                    }.allowsHitTesting(false).accessibilityHidden(true)
                }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: samples.count)
    }

    private func double(_ amount: Decimal) -> Double { NSDecimalNumber(decimal: amount).doubleValue }

    private func clearInteraction() {
        stopReplay()
        selected = nil
        baseline = nil
        zoom = 1
    }

    private func startReplay() {
        let count = visible.count
        guard count > 1 else { return }
        selected = nil
        replayCount = 1
        replay = Task { @MainActor in
            let steps = reduceMotion ? 12 : 48
            for step in 1...steps {
                try? await Task.sleep(nanoseconds: reduceMotion ? 180_000_000 : 45_000_000)
                guard !Task.isCancelled else { return }
                replayCount = max(1, step * count / steps)
            }
            replayCount = nil
            replay = nil
        }
    }

    private func stopReplay() {
        replay?.cancel()
        replay = nil
        replayCount = nil
    }
}
