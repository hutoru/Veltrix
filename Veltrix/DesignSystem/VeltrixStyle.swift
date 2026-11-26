import SwiftUI
import UIKit

enum VeltrixTheme {
    static let background = adaptive(0x080809, 0xF6F6F8)
    static let secondaryBackground = adaptive(0x101012, 0xF0F0F2)
    static let surface = adaptive(0x171719, 0xFFFFFF)
    static let elevated = adaptive(0x1C1C1E, 0xEDEDEF)
    static let border = adaptive(0x2C2C30, 0xDEDEE2)
    static let text = adaptive(0xFFFFFF, 0x171719)
    static let muted = adaptive(0x96969C, 0x64646B)
    static let metallic = adaptive(0xC4C7CC, 0x52545A)
    static let positive = adaptive(0x30D158, 0x12773B)
    static let negative = adaptive(0xFF453A, 0xB9222C)
    static let buttonInk = adaptive(0x080809, 0xFFFFFF)
    static let darkBackground = Color(uiColor: UIColor(rgb: 0x080809))

    private static func adaptive(_ dark: UInt32, _ light: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension Color {
    static let vxDarkBackground = VeltrixTheme.darkBackground
    static let vxBackground = VeltrixTheme.background
    static let vxText = VeltrixTheme.text
    static let vxCard = VeltrixTheme.surface
    static let vxSurface = VeltrixTheme.elevated
    static let vxMuted = VeltrixTheme.muted
    static let vxSeparator = VeltrixTheme.border
    static let vxAccent = VeltrixTheme.text
    static let vxHighlight = VeltrixTheme.metallic
    static let vxUp = VeltrixTheme.positive
    static let vxDown = VeltrixTheme.negative
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
    var ink: Color = VeltrixTheme.buttonInk
    var height: CGFloat = 48
    var cornerRadius: CGFloat = 12
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: height)
            .foregroundStyle(ink)
            .background(tint, in: RoundedRectangle(cornerRadius: cornerRadius))
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
        TimelineView(.animation(minimumInterval: 1 / 24, paused: UITestMode.enabled || reduceMotion || phase != .active)) { timeline in
            let pulse = UITestMode.enabled || reduceMotion ? 0.5 : (sin(timeline.date.timeIntervalSinceReferenceDate * 4) + 1) / 2
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
            .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(Color.vxSeparator, lineWidth: 1).allowsHitTesting(false))
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
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(.primary.opacity(0.11), lineWidth: 1).allowsHitTesting(false))
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


extension View {
    @MainActor func dismissibleKeyboard() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { Keyboard.dismiss() }
                    .accessibilityIdentifier("keyboard.done")
            }
        }
    }
}

@MainActor enum Keyboard {
    static func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
