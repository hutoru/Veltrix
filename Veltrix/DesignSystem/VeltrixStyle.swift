import SwiftUI
import UIKit

extension Color {
    static let vxBackground = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: 0x0B0B0D) : UIColor(rgb: 0xF4F2FA) })
    static let vxCard = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: 0x17171C) : .white })
    static let vxSurface = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: 0x212128) : UIColor(rgb: 0xEBE7F6) })
    static let vxMuted = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: 0x8E8E93) : UIColor(rgb: 0x655E75) })
    static let vxAccent = Color(uiColor: UIColor(rgb: 0x7955FF))
    static let vxHighlight = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: 0xB69FFF) : UIColor(rgb: 0x5532CE) })
    static let vxUp = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: 0x22C55E) : UIColor(rgb: 0x12773B) })
    static let vxDown = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: 0xFF453A) : UIColor(rgb: 0xB9222C) })
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255,
                  blue: CGFloat(rgb & 255) / 255, alpha: 1)
    }
}

enum Feedback {
    static func tap() { UISelectionFeedbackGenerator().selectionChanged() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func failure() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}

struct VeltrixMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        func polygon(_ points: [(CGFloat, CGFloat)]) {
            guard let first = points.first else { return }
            path.move(to: CGPoint(x: rect.width * first.0 + rect.minX, y: rect.height * first.1 + rect.minY))
            for point in points.dropFirst() {
                path.addLine(to: CGPoint(x: rect.width * point.0 + rect.minX, y: rect.height * point.1 + rect.minY))
            }
            path.closeSubpath()
        }
        polygon([(0.03, 0.17), (0.27, 0.17), (0.58, 0.73), (0.47, 0.94)])
        polygon([(0.36, 0.17), (0.97, 0.17), (0.65, 0.66), (0.53, 0.45), (0.67, 0.26), (0.41, 0.26)])
        return path
    }
}

struct OrbitLines: View {
    var opacity = 0.26

    var body: some View {
        Canvas { context, size in
            let pivot = CGPoint(x: size.width * 0.77, y: size.height * 0.25)
            for index in 0..<15 {
                let radius = CGFloat(index) * 10 + 28
                var orbit = Path()
                orbit.move(to: CGPoint(x: size.width, y: pivot.y - radius))
                orbit.addQuadCurve(to: CGPoint(x: pivot.x - radius, y: size.height),
                                   control: CGPoint(x: pivot.x - radius * 0.62, y: pivot.y - radius))
                context.stroke(orbit, with: .color(.white.opacity(opacity * (1 - Double(index) / 18))), lineWidth: 0.65)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded))
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(.white)
            .background(Color.vxAccent.gradient, in: RoundedRectangle(cornerRadius: 15))
            .opacity(configuration.isPressed ? 0.76 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.76), value: configuration.isPressed)
    }
}

struct SimBadge: View {
    var inverted = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "circle.dotted")
            Text("Simulation")
                .textCase(.uppercase)
                .tracking(1.3)
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(inverted ? .white : Color.vxHighlight)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(inverted ? Color.white.opacity(0.14) : Color.vxAccent.opacity(0.12), in: Capsule())
        .accessibilityLabel(Text("Simulation · Virtual funds"))
    }
}

struct PageHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.system(.largeTitle, design: .rounded).weight(.bold)).accessibilityAddTraits(.isHeader)
                Text(detail).font(.subheadline).foregroundStyle(Color.vxMuted)
            }
            Spacer(minLength: 0)
            trailing().padding(.top, 6)
        }
    }
}

struct EmptyPanel: View {
    let icon: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: icon).font(.title3).foregroundStyle(Color.vxHighlight)
                .frame(width: 42, height: 42).background(Color.vxAccent.opacity(0.13), in: RoundedRectangle(cornerRadius: 13))
            Text(title).font(.headline)
            Text(detail).font(.footnote).foregroundStyle(Color.vxMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }
}

struct IconButton: View {
    let icon: String
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.vxHighlight)
                .frame(width: 44, height: 44)
                .background(Color.vxSurface, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}

struct CountValue: View {
    let text: String

    var body: some View {
        Group {
            if #available(iOS 17.0, *) {
                Text(verbatim: text).contentTransition(.numericText())
            } else {
                Text(verbatim: text).contentTransition(.interpolate)
            }
        }
        .monospacedDigit()
        .animation(.easeOut(duration: 0.25), value: text)
    }
}

struct Skeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: reduceMotion || phase != .active)) { timeline in
            let pulse = reduceMotion ? 0.5 : (sin(timeline.date.timeIntervalSinceReferenceDate * 4) + 1) / 2
            RoundedRectangle(cornerRadius: 9)
                .fill(LinearGradient(colors: [.vxSurface, .vxAccent.opacity(0.07 + 0.12 * pulse), .vxSurface],
                                     startPoint: .leading, endPoint: .trailing))
        }
        .accessibilityLabel(Text("Loading"))
    }
}

extension View {
    func panel(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .background(Color.vxCard, in: RoundedRectangle(cornerRadius: 21))
            .overlay(RoundedRectangle(cornerRadius: 21).strokeBorder(.primary.opacity(0.06), lineWidth: 1))
    }

    func glass(radius: CGFloat) -> some View {
        modifier(GlassSurface(radius: radius))
    }
}

private struct GlassSurface: ViewModifier {
    let radius: CGFloat

    @ViewBuilder func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius))
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    private func fallback(_ content: Content) -> some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(.primary.opacity(0.11), lineWidth: 1))
    }
}

struct PageScroll<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22, content: content)
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 20)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
        }
        .background(Color.vxBackground.ignoresSafeArea())
    }
}
