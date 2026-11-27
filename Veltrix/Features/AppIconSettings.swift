import SwiftUI
import UIKit

struct AppIconSettings: View {
    @Environment(\.veltrixTheme) private var theme
    @State private var active: String?
    @State private var error = false
    @State private var updating = false

    private struct Icon: Identifiable {
        let id: String
        let title: LocalizedStringKey
        let background: UInt32
        let ink: UInt32
        var name: String? { id == "AppIcon" ? nil : id }
    }

    private let icons: [Icon] = [
        .init(id: "AppIcon", title: "Obsidian Black", background: 0x000000, ink: 0xFFFFFF),
        .init(id: "VXWhite", title: "Pure White", background: 0xF4F5F7, ink: 0x13151A),
        .init(id: "VXMidnight", title: "Midnight Blue", background: 0x151A2D, ink: 0xBCD3FF),
        .init(id: "VXTitanium", title: "Titanium", background: 0x4A4D55, ink: 0xEEF0F4),
        .init(id: "VXCarbon", title: "Carbon", background: 0x1F2023, ink: 0xD2D4D9),
        .init(id: "VXGold", title: "Royal Gold", background: 0x21190E, ink: 0xF2C875),
        .init(id: "VXOcean", title: "Ocean Blue", background: 0x103762, ink: 0xD1EBFF),
        .init(id: "VXMono", title: "Monochrome", background: 0x303237, ink: 0xD9DBE0)
    ]

    var body: some View {
        PageScroll {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 106))], spacing: 10) {
                ForEach(icons) { icon in
                    Button { select(icon) } label: {
                        VStack(spacing: 8) {
                            VeltrixMark().fill(Color(cardRGB: icon.ink))
                                .frame(width: 27, height: 27).frame(width: 58, height: 58)
                                .background(Color(cardRGB: icon.background), in: RoundedRectangle(cornerRadius: 14))
                                .overlay(alignment: .topTrailing) {
                                    if active == icon.name {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.accent)
                                            .offset(x: 5, y: -5).accessibilityHidden(true)
                                    }
                                }
                            Text(icon.title).font(.caption.weight(.medium)).lineLimit(1).minimumScaleFactor(0.65)
                        }.frame(maxWidth: .infinity).panel(padding: 10)
                    }.buttonStyle(.plain)
                        .disabled(updating)
                        .accessibilityAddTraits(active == icon.name ? .isSelected : [])
                }
            }
        }
        .navigationTitle("App icon").navigationBarTitleDisplayMode(.inline)
        .onAppear { active = UIApplication.shared.alternateIconName }
        .alert("App icon unavailable", isPresented: $error) { Button("OK", role: .cancel) {} }
    }

    private func select(_ icon: Icon) {
        guard icon.name != active else { return }
        guard UIApplication.shared.supportsAlternateIcons else { error = true; return }
        updating = true
        UIApplication.shared.setAlternateIconName(icon.name) { issue in
            Task { @MainActor in
                updating = false
                if issue == nil { active = UIApplication.shared.alternateIconName; Feedback.success() }
                else { error = true; Feedback.failure() }
            }
        }
    }
}
