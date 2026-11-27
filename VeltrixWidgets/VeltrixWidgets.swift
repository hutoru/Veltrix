import ActivityKit
import SwiftUI
import WidgetKit

private enum WidgetSection: String {
    case portfolio, market, change, earn
    var title: LocalizedStringKey {
        switch self {
        case .portfolio: return "Portfolio"
        case .market: return "Market Watch"
        case .change: return "Return"
        case .earn: return "Earn"
        }
    }
    var families: [WidgetFamily] {
        switch self {
        case .portfolio: return [.systemSmall, .systemMedium, .systemLarge]
        case .market, .earn: return [.systemSmall, .systemMedium]
        case .change: return [.accessoryRectangular]
        }
    }
    var route: String {
        switch self {
        case .portfolio, .change: return "portfolio"
        case .market: return "markets"
        case .earn: return "earn"
        }
    }
}

private struct WidgetEntry: TimelineEntry {
    let date: Date
    let data: WidgetData?
}

private struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry { .init(date: .now, data: nil) }
    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        completion(.init(date: .now, data: WidgetData.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        let now = Date()
        completion(Timeline(entries: [.init(date: now, data: WidgetData.load())], policy: .after(now.addingTimeInterval(1_800))))
    }
}

private struct PortfolioWidget: Widget {
    let section: WidgetSection
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: section.rawValue, provider: Provider()) { entry in
            WidgetPanel(section: section, data: entry.data)
                .widgetURL(URL(string: "veltrix://" + section.route))
        }
        .configurationDisplayName(section.title)
        .description("Portfolio data from VELTRIX.")
        .supportedFamilies(section.families)
    }
}

private struct WidgetPanel: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetFamily) private var family
    let section: WidgetSection
    let data: WidgetData?

    private var light: Bool { data?.appearance == "light" || ((data?.appearance == "system" || data == nil) && scheme == .light) }
    private var background: Color {
        light ? Color(white: 0.97) : (data?.appearance == "dark" ? .black : Color(red: 15/255, green: 17/255, blue: 27/255))
    }

    var body: some View {
        if family == .accessoryRectangular {
            VStack(alignment: .leading, spacing: 3) {
                Label("Return", systemImage: "chart.line.uptrend.xyaxis").font(.caption)
                Text(verbatim: data?.change ?? "—").font(.title2.weight(.medium)).monospacedDigit()
            }.frame(maxWidth: .infinity, alignment: .leading)
        } else if #available(iOSApplicationExtension 17.0, *) {
            panel.containerBackground(for: .widget) { background }
        } else {
            panel.padding(12).background(background)
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(section.title).font(.caption.weight(.semibold)).opacity(0.75)
            if let data {
                switch section {
                case .portfolio, .change:
                    Text(verbatim: data.balance).font(.title2.weight(.medium)).monospacedDigit()
                    Text(verbatim: data.change).font(.caption).monospacedDigit()
                    if family != .systemSmall && !data.graph.isEmpty { graph(data.graph).frame(minHeight: 20, maxHeight: 52) }
                    if family == .systemLarge { rows(data.assets, count: 5) }
                case .market: rows(data.favorites, count: 3)
                case .earn: rows(data.earn, count: 3)
                }
                Spacer(minLength: 0)
                Text(data.updated, style: .time).font(.caption2).opacity(0.65)
            } else {
                Spacer(minLength: 0)
                Text("Open VELTRIX to sync data").font(.footnote).opacity(0.8)
                Spacer(minLength: 0)
            }
        }.lineLimit(1).minimumScaleFactor(0.55)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .foregroundStyle(light ? Color.black : Color.white)
    }

    @ViewBuilder private func rows(_ rows: [WidgetData.Row], count: Int) -> some View {
        if rows.isEmpty { Text("No positions yet").font(.caption).opacity(0.7) }
        ForEach(Array(rows.prefix(count).enumerated()), id: \.offset) { _, row in
            HStack {
                Text(verbatim: row.ticker).font(.caption.weight(.semibold))
                Spacer(minLength: 5)
                Text(verbatim: row.detail).font(.caption).monospacedDigit()
            }
        }
    }

    private func graph(_ segments: [[Double]]) -> some View {
        Canvas { context, size in
            let values = segments.flatMap { $0 }
            guard values.count > 1, let floor = values.min(), let ceiling = values.max() else { return }
            var index = 0
            var outline = Path()
            for segment in segments {
                for (offset, value) in segment.enumerated() {
                    let point = CGPoint(x: size.width * CGFloat(index) / CGFloat(values.count - 1),
                                        y: ceiling == floor ? size.height / 2 : size.height * CGFloat((ceiling - value) / (ceiling - floor)))
                    if offset == 0 { outline.move(to: point) } else { outline.addLine(to: point) }
                    index += 1
                }
            }
            context.stroke(outline, with: .color(.blue), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
        }.accessibilityHidden(true)
    }
}

@available(iOSApplicationExtension 16.1, *)
private struct ActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: OperationAttributes.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: context.attributes.symbol).foregroundStyle(tint(context.state.stage))
                    Text(verbatim: context.attributes.title).font(.headline)
                    Spacer()
                    Text(verbatim: "VELTRIX").font(.caption.weight(.semibold)).tracking(1)
                }
                HStack {
                    Text(verbatim: context.attributes.amount ?? context.attributes.quantity ?? context.attributes.ticker)
                        .monospacedDigit()
                    Spacer()
                    Text(verbatim: context.state.status).foregroundStyle(tint(context.state.stage))
                }.font(.subheadline)
                track(context.state.stage)
            }.lineLimit(1).minimumScaleFactor(0.55).padding(14).foregroundStyle(.white)
                .activityBackgroundTint(.black)
                .widgetURL(link(context.attributes.operationID))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.attributes.symbol).foregroundStyle(tint(context.state.stage))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(verbatim: "VELTRIX").font(.caption.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(verbatim: context.attributes.title).fontWeight(.medium)
                            Spacer()
                            Text(verbatim: context.attributes.amount ?? context.attributes.quantity ?? context.attributes.ticker).monospacedDigit()
                        }
                        track(context.state.stage)
                        Text(verbatim: context.state.status).font(.caption).foregroundStyle(tint(context.state.stage))
                    }.lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: context.attributes.symbol).foregroundStyle(tint(context.state.stage))
            } compactTrailing: {
                Text(verbatim: context.attributes.ticker).font(.caption.weight(.medium))
            } minimal: {
                Image(systemName: context.state.stage == .saved ? "checkmark" : context.attributes.symbol)
                    .foregroundStyle(tint(context.state.stage))
            }.widgetURL(link(context.attributes.operationID))
        }
    }

    private func track(_ stage: OperationAttributes.ContentState.Stage) -> some View {
        let step = stage == .saved ? 4 : (stage == .waiting ? 2 : 1)
        return HStack(spacing: 4) {
            ForEach(0..<4) { index in
                Capsule().fill(index < step ? tint(stage) : .white.opacity(0.2)).frame(height: 3)
            }
        }.accessibilityHidden(true)
    }

    private func tint(_ stage: OperationAttributes.ContentState.Stage) -> Color {
        switch stage {
        case .saved: return .green
        case .failed: return .red
        case .cancelled: return .gray
        case .processing, .waiting: return Color(red: 0.25, green: 0.5, blue: 1)
        }
    }

    private func link(_ id: UUID) -> URL? { URL(string: "veltrix://activity/" + id.uuidString) }
}

@main struct VeltrixWidgets: WidgetBundle {
    var body: some Widget {
        PortfolioWidget(section: .portfolio)
        PortfolioWidget(section: .market)
        PortfolioWidget(section: .change)
        PortfolioWidget(section: .earn)
        ActivityWidget()
    }
}
