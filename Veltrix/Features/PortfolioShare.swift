import SwiftUI
import UIKit

struct PortfolioShare: View {
    @Environment(\.veltrixTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var model: VeltrixModel
    @Environment(\.dismiss) private var dismiss
    let portfolio: Portfolio
    @State private var range = ChartRange.week
    @State private var candles = false
    @State private var image: UIImage?

    var body: some View {
        NavigationStack {
            PageScroll {
                signature
                VeltrixChart(samples: portfolio.chart(range: range), range: $range, candles: $candles, allowsCandles: false) {
                    model.money($0)
                }
                Button {
                    let renderer = ImageRenderer(content: shareImage)
                    renderer.scale = 2
                    image = renderer.uiImage
                } label: { Label("Share image", systemImage: "square.and.arrow.up") }
                .buttonStyle(PrimaryButtonStyle())
            }
            .navigationTitle("Share portfolio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: .init(get: { image != nil }, set: { if !$0 { image = nil } })) {
                if let image { SystemShare(items: [image]) }
            }
        }
    }

    private var signature: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                VeltrixMark().fill(theme.highlight).frame(width: 28, height: 28)
                Text(verbatim: "VELTRIX").font(.headline).tracking(2)
                Spacer()
                Text("Portfolio").font(.caption.weight(.semibold))
            }
            Text(verbatim: portfolio.name).font(.subheadline).foregroundStyle(theme.muted)
            Text(verbatim: model.money(try? portfolio.value(prices: model.prices)))
                .font(.system(size: 38, weight: .medium, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.45)
        }
        .panel()
    }

    private var shareImage: some View {
        let points = portfolio.chart(range: range)
        return VStack(alignment: .leading, spacing: 15) {
            signature
            HStack {
                Text("Portfolio history").font(.headline)
                Spacer()
                Text(verbatim: range.rawValue).font(.caption.monospaced())
            }
            if points.count > 1 {
                Canvas { context, size in
                    let values = points.map { NSDecimalNumber(decimal: $0.close).doubleValue }
                    let minValue = values.min() ?? 0
                    let span = max((values.max() ?? 0) - minValue, 1e-12)
                    let duration = max(points.last?.date.timeIntervalSince(points[0].date) ?? 1, 1)
                    var line = Path()
                    for (index, sample) in points.enumerated() {
                        let x = size.width * sample.date.timeIntervalSince(points[0].date) / duration
                        let y = size.height - 12 - (size.height - 24) * (values[index] - minValue) / span
                        if index == 0 { line.move(to: CGPoint(x: x, y: y)) }
                        else { line.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    context.stroke(line, with: .color(theme.highlight), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }
                .frame(height: 160)
            } else {
                Text("No chart data").font(.subheadline).foregroundStyle(theme.muted).frame(height: 70)
            }
            Text(verbatim: "Beyond the balance.").font(.caption).foregroundStyle(theme.muted)
        }
        .padding(24).frame(width: 420)
        .background(theme.background)
        .foregroundStyle(theme.text)
        .environment(\.veltrixTheme, theme)
        .environment(\.colorScheme, colorScheme)
    }
}

struct SystemShare: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
