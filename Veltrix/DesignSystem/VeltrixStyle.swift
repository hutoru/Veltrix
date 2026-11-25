import SwiftUI
import UIKit

extension Color {
    static let vxBackground = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: 0x080809) : UIColor(rgb: 0xF6F6F8) })
    static let vxText = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: 0xF8F8FA) : UIColor(rgb: 0x17171C) })
    static let vxCard = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: 0x121214) : .white })
    static let vxSurface = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: 0x1C1C1E) : UIColor(rgb: 0xEDEDEF) })
    static let vxMuted = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: 0x929299) : UIColor(rgb: 0x64646B) })
    static let vxSeparator = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: 0x242426) : UIColor(rgb: 0xDEDEE2) })
    static let vxAccent = Color(uiColor: UIColor(rgb: 0x7955FF))
    static let vxHighlight = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: 0xB69FFF) : UIColor(rgb: 0x5532CE) })
    static let vxUp = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: 0x30D158) : UIColor(rgb: 0x12773B) })
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var tint: Color = .vxAccent
    var ink: Color = .white
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(ink)
            .background(tint, in: RoundedRectangle(cornerRadius: 12))
            .opacity(configuration.isPressed ? 0.76 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: configuration.isPressed)
    }
}

struct PageHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.largeTitle.weight(.semibold)).accessibilityAddTraits(.isHeader)
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
                .foregroundStyle(Color.vxText)
                .frame(width: 44, height: 44)
                .background(Color.vxCard, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}

struct CountValue: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: text)
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
            .background(Color.vxCard, in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(.primary.opacity(0.06), lineWidth: 1).allowsHitTesting(false))
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
            VStack(alignment: .leading, spacing: 16, content: content)
                .foregroundStyle(Color.vxText)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 24)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
        }
        .background(Color.vxBackground.ignoresSafeArea())
    }
}


struct NumericPad: View {
    let allowsDecimal: Bool
    var keyHeight: CGFloat = 44
    let onInput: (String) -> Void
    let onDelete: () -> Void
    private var separator: String { Locale.current.decimalSeparator ?? "." }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 7) {
            ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", separator, "0", "delete"], id: \.self) { key in
                if key != separator || allowsDecimal {
                    Button {
                        if key == "delete" { onDelete() } else { onInput(key) }
                        Feedback.tap()
                    } label: {
                        Group {
                            if key == "delete" { Image(systemName: "delete.left") }
                            else { Text(verbatim: key) }
                        }
                        .font(.system(size: 22, weight: .medium).monospacedDigit())
                        .frame(maxWidth: .infinity, minHeight: keyHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(key == "delete" ? Text("Delete digit") : Text(verbatim: key))
                    .accessibilityIdentifier("keypad." + key)
                } else {
                    Color.clear.frame(height: keyHeight)
                }
            }
        }
    }
}
