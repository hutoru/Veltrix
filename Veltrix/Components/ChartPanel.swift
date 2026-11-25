import Charts
import SwiftUI

struct ChartPanel: View {
    let samples: [ChartSample]
    @Binding var range: ChartRange
    @Binding var candles: Bool
    let allowsCandles: Bool
    var height: CGFloat = 190
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
            if samples.isEmpty {
                EmptyPanel(icon: "waveform.path", title: "No chart data", detail: "History appears when values become available.")
            } else {
                readout
                plotting
                    .frame(height: height)
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

            HStack(spacing: 2) {
                ForEach(ChartRange.allCases, id: \.self) { value in
                    Button {
                        range = value
                        Feedback.tap()
                    } label: {
                        Text(verbatim: value.rawValue).font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .foregroundStyle(range == value ? Color.vxHighlight : Color.vxMuted)
                            .background(range == value ? Color.vxAccent.opacity(0.15) : .clear,
                                        in: RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(range == value ? .isSelected : [])
                }
            }
            .padding(3)
            .background(Color.vxSurface, in: RoundedRectangle(cornerRadius: 12))

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
        .onChange(of: range) { _ in clearInteraction() }
        .onChange(of: candles) { _ in clearInteraction() }
        .onChange(of: phase) { state in if state != .active { stopReplay() } }
        .onDisappear { stopReplay() }
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
                    Text(verbatim: format(value.close)).font(.headline.monospacedDigit())
                    Text(value.date.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(Color.vxMuted)
                }
            }
            Spacer()
            if let a = anchor, let b = focus, a.close != 0,
               let change = try? MoneyMath.multiply(MoneyMath.divide(MoneyMath.subtract(b.close, a.close), a.close), 100) {
                Text(verbatim: Display.percent(change)).font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(change >= 0 ? Color.vxUp : Color.vxDown)
            }
        }
        .frame(minHeight: 38, alignment: .leading)
    }

    private var plotting: some View {
        let plotted = visible
        let data = Array(plotted.prefix(replayCount ?? plotted.count))
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
                    AreaMark(x: .value("Date", sample.date), yStart: .value("Floor", minimum - padding),
                             yEnd: .value("Price", double(sample.close)))
                        .foregroundStyle(LinearGradient(colors: [.vxAccent.opacity(0.43), .vxAccent.opacity(0.01)],
                                                        startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Date", sample.date), y: .value("Price", double(sample.close)))
                        .foregroundStyle(Color.vxHighlight)
                        .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round))
                    if data.count == 1 {
                        PointMark(x: .value("Date", sample.date), y: .value("Price", double(sample.close)))
                            .foregroundStyle(Color.vxHighlight).symbolSize(30)
                    }
                }
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
        .chartXScale(domain: first...last)
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
        .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in AxisGridLine() } }
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
