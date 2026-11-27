import SwiftUI
import UIKit

enum VeltrixAppearance: String, CaseIterable, Identifiable {
    case midnight, obsidian = "dark", light, system

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .midnight: return "Midnight Blue"
        case .obsidian: return "Obsidian Black"
        case .light: return "Light"
        case .system: return "System"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .midnight, .obsidian: return .dark
        case .light: return .light
        case .system: return nil
        }
    }
}

struct VeltrixTheme {
    let background: Color
    let surface: Color
    let elevated: Color
    let text: Color
    let muted: Color
    let accent: Color
    let separator: Color
    let positive: Color
    let negative: Color
    let highlight: Color
    let buttonInk: Color
    let navigationSelection: Color

    init(_ appearance: VeltrixAppearance) {
        func color(_ midnight: UInt32, _ obsidian: UInt32, _ light: UInt32) -> Color {
            let rgb: UInt32
            switch appearance {
            case .midnight: rgb = midnight
            case .obsidian: rgb = obsidian
            case .light: rgb = light
            case .system:
                return Color(uiColor: UIColor { traits in
                    UIColor(rgb: traits.userInterfaceStyle == .dark ? obsidian : light)
                })
            }
            return Color(uiColor: UIColor(rgb: rgb))
        }

        background = color(0x0F111B, 0x000000, 0xFFFFFF)
        surface = color(0x191D2B, 0x19191B, 0xF2F2F5)
        elevated = color(0x242938, 0x242426, 0xE8E8EC)
        text = color(0xF5F6FA, 0xFFFFFF, 0x101012)
        muted = color(0x9298AB, 0x96969C, 0x666670)
        accent = color(0x397BFF, 0x77A4FF, 0x1756C6)
        separator = color(0x303649, 0x27272C, 0xE0E0E5)
        positive = color(0x30D158, 0x30D158, 0x12773B)
        negative = color(0xFF5252, 0xFF453A, 0xB9222C)
        highlight = color(0xC4CBDD, 0xD2D2D7, 0x52525A)
        buttonInk = color(0x0F111B, 0x080809, 0xFFFFFF)
        navigationSelection = color(0x121624, 0x101012, 0xDADDE5)
    }
}

private struct VeltrixThemeKey: EnvironmentKey {
    static let defaultValue = VeltrixTheme(.midnight)
}

extension EnvironmentValues {
    var veltrixTheme: VeltrixTheme {
        get { self[VeltrixThemeKey.self] }
        set { self[VeltrixThemeKey.self] = newValue }
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255,
                  blue: CGFloat(rgb & 255) / 255, alpha: 1)
    }
}

enum Feedback {
    private static var enabled: Bool { UserDefaults.standard.object(forKey: "hapticsEnabled") as? Bool ?? true }

    static func tap() {
        if enabled { UISelectionFeedbackGenerator().selectionChanged() }
    }

    static func success() {
        if enabled { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    }

    static func failure() {
        if enabled { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    }
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
    @Environment(\.veltrixTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var tint: Color? = nil
    var ink: Color? = nil
    var height: CGFloat = 48
    var cornerRadius: CGFloat = 12
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: height)
            .foregroundStyle(ink ?? theme.buttonInk)
            .background(tint ?? theme.text, in: RoundedRectangle(cornerRadius: cornerRadius))
            .opacity(configuration.isPressed ? 0.76 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: configuration.isPressed)
    }
}

struct PageHeader<Trailing: View>: View {
    @Environment(\.veltrixTheme) private var theme
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.largeTitle.weight(.semibold)).accessibilityAddTraits(.isHeader)
                Text(detail).font(.subheadline).foregroundStyle(theme.muted)
            }
            Spacer(minLength: 0)
            trailing().padding(.top, 6)
        }
    }
}

struct EmptyPanel: View {
    @Environment(\.veltrixTheme) private var theme
    let icon: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: icon).font(.title3).foregroundStyle(theme.highlight)
                .frame(width: 42, height: 42).background(theme.accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 13))
            Text(title).font(.headline)
            Text(detail).font(.footnote).foregroundStyle(theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }
}

struct IconButton: View {
    @Environment(\.veltrixTheme) private var theme
    let icon: String
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.text)
                .frame(width: 44, height: 44)
                .background(theme.surface, in: Circle())
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
        .animation(reduceMotion || UITestMode.enabled ? nil : .easeInOut(duration: 0.22), value: text)
    }
}

struct Skeleton: View {
    @Environment(\.veltrixTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: UITestMode.enabled || reduceMotion || phase != .active)) { timeline in
            let pulse = UITestMode.enabled || reduceMotion ? 0.5 : (sin(timeline.date.timeIntervalSinceReferenceDate * 4) + 1) / 2
            RoundedRectangle(cornerRadius: 9)
                .fill(LinearGradient(colors: [theme.elevated, theme.accent.opacity(0.07 + 0.12 * pulse), theme.elevated],
                                     startPoint: .leading, endPoint: .trailing))
        }
        .accessibilityLabel(Text("Loading"))
    }
}

extension View {
    func panel(padding: CGFloat = 16) -> some View {
        modifier(PanelSurface(padding: padding))
    }

    func glass(radius: CGFloat) -> some View {
        modifier(GlassSurface(radius: radius))
    }
}

private struct PanelSurface: ViewModifier {
    @Environment(\.veltrixTheme) private var theme
    let padding: CGFloat

    func body(content: Content) -> some View {
        content.padding(padding)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 15))
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .strokeBorder(theme.separator, lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

private struct GlassSurface: ViewModifier {
    @Environment(\.veltrixTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let radius: CGFloat

    @ViewBuilder func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius)
        if reduceTransparency {
            content.background(theme.elevated, in: shape)
        } else {
            #if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                content.glassEffect(.regular.tint(theme.surface.opacity(0.48)), in: shape)
            } else {
                fallback(content, shape: shape)
            }
            #else
            fallback(content, shape: shape)
            #endif
        }
    }

    private func fallback(_ content: Content, shape: RoundedRectangle) -> some View {
        content
            .background(theme.surface.opacity(0.56), in: shape)
            .background(.regularMaterial, in: shape)
            .overlay(shape.strokeBorder(theme.separator.opacity(0.65), lineWidth: 1).allowsHitTesting(false))
    }
}

struct PageScroll<Content: View>: View {
    @Environment(\.veltrixTheme) private var theme
    var spacing: CGFloat = 16
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing, content: content)
                .foregroundStyle(theme.text)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 24)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
        }
        .background(theme.background.ignoresSafeArea())
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
