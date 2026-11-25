import SwiftUI
import UIKit

enum CardCollection: String, CaseIterable {
    case origin, atlas, reserve, exclusive

    var title: LocalizedStringKey {
        switch self {
        case .origin: return "Origin"
        case .atlas: return "Atlas"
        case .reserve: return "Reserve"
        case .exclusive: return "Veltrix Exclusive"
        }
    }

    var tiers: [CardTier] {
        switch self {
        case .origin: return [.classic, .gold, .platinum, .signature, .infinite]
        case .atlas: return [.standard, .atlasGold, .atlasPlatinum, .world, .worldElite]
        case .reserve: return [.green, .reserveGold, .reservePlatinum, .centurion]
        case .exclusive: return [.black, .carbonBlack, .royalGold, .brushedSilver, .ceramicWhite, .crystalGlass, .holographic, .purple, .custom]
        }
    }
}

extension CardTier {
    var collection: CardCollection { CardCollection.allCases.first { $0.tiers.contains(self) } ?? .origin }

    var title: LocalizedStringKey { LocalizedStringKey(titleKey) }

    var titleKey: String {
        switch self {
        case .classic: return "Classic"
        case .gold, .atlasGold, .reserveGold: return "Gold"
        case .platinum, .atlasPlatinum, .reservePlatinum: return "Platinum"
        case .signature: return "Signature"
        case .infinite: return "Infinite"
        case .standard: return "Standard"
        case .world: return "World"
        case .worldElite: return "World Elite"
        case .green: return "Green"
        case .centurion: return "Centurion"
        case .black: return "Black Titanium"
        case .carbonBlack: return "Carbon Black"
        case .royalGold: return "Royal Gold"
        case .brushedSilver: return "Brushed Silver"
        case .ceramicWhite: return "Ceramic White"
        case .crystalGlass: return "Crystal Glass"
        case .holographic: return "Holographic Edition"
        case .purple: return "Purple Edition"
        case .custom: return "Custom Edition"
        }
    }

    var finish: (CardMaterial, CardTexture, UInt32, UInt32) {
        switch self {
        case .classic: return (.matte, .none, 0x30333D, 0x12141B)
        case .gold: return (.gold, .brushed, 0x997544, 0x342215)
        case .platinum: return (.silver, .brushed, 0x667382, 0x242B36)
        case .signature: return (.titanium, .engraved, 0x4F5872, 0x202136)
        case .infinite: return (.carbon, .woven, 0x26324D, 0x111624)
        case .standard: return (.matte, .engraved, 0x435466, 0x172835)
        case .atlasGold: return (.gold, .engraved, 0xBA8747, 0x3D231A)
        case .atlasPlatinum: return (.titanium, .brushed, 0x526579, 0x172831)
        case .world: return (.glass, .engraved, 0x276777, 0x112D3C)
        case .worldElite: return (.carbon, .woven, 0x39446C, 0x16182D)
        case .green: return (.ceramic, .engraved, 0x2F694F, 0x153327)
        case .reserveGold: return (.gold, .engraved, 0x9B7244, 0x49321E)
        case .reservePlatinum: return (.silver, .engraved, 0x738888, 0x313B46)
        case .centurion: return (.titanium, .engraved, 0x383C42, 0x17181B)
        case .black: return (.titanium, .brushed, 0x35353B, 0x101015)
        case .carbonBlack: return (.carbon, .woven, 0x282D32, 0x101418)
        case .royalGold: return (.gold, .brushed, 0xBA8642, 0x503014)
        case .brushedSilver: return (.silver, .brushed, 0x818C97, 0x3C4352)
        case .ceramicWhite: return (.ceramic, .none, 0xFCFBFA, 0xB7B6C2)
        case .crystalGlass: return (.glass, .engraved, 0x457781, 0x202846)
        case .holographic: return (.holographic, .engraved, 0x50466F, 0x252E4A)
        case .purple: return (.matte, .engraved, 0x6848A5, 0x231A45)
        case .custom: return (.matte, .none, 0x42404A, 0x17161C)
        }
    }

    var defaultDesign: CardDesign {
        let (material, texture, _, _) = finish
        var design = CardDesign(material: material, texture: texture)
        switch collection {
        case .origin: break
        case .atlas: design.markX = 0.81
        case .reserve: design.markX = 0.5; design.markY = 0.37; design.typeface = .classic
        case .exclusive: design.markX = 0.76; design.markY = 0.35; design.typeface = .mono
        }
        return design
    }
}

extension CardMaterial {
    var title: LocalizedStringKey {
        switch self {
        case .matte: return "Matte metal"
        case .titanium: return "Brushed titanium"
        case .gold: return "Gold"
        case .silver: return "Silver"
        case .carbon: return "Carbon"
        case .ceramic: return "Ceramic"
        case .glass: return "Glass"
        case .holographic: return "Holographic"
        }
    }
}

extension Color {
    init(cardRGB value: UInt32) {
        self.init(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255,
                  blue: Double(value & 255) / 255)
    }

    var cardRGB: UInt32? {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return UInt32((r * 255).clampedColor) << 16 | UInt32((g * 255).clampedColor) << 8 | UInt32((b * 255).clampedColor)
    }
}

private extension CGFloat {
    var clampedColor: CGFloat { min(255, max(0, rounded())) }
}

struct CardGrain: View {
    let texture: CardTexture
    let collection: CardCollection

    var body: some View {
        Canvas { context, size in
            var light = Path()
            var dark = Path()
            switch texture {
            case .none:
                for y in stride(from: 1.0, to: size.height, by: 3.0) {
                    for x in stride(from: y.truncatingRemainder(dividingBy: 5), to: size.width, by: 6) {
                        light.addEllipse(in: CGRect(x: x, y: y, width: 0.7, height: 0.7))
                    }
                }
            case .brushed:
                for index in 0..<Int(size.height) {
                    let y = CGFloat(index)
                    let inset = CGFloat((index * 31) % 49)
                    if index.isMultiple(of: 3) {
                        light.move(to: CGPoint(x: 0, y: y))
                        light.addLine(to: CGPoint(x: size.width - inset, y: y + 4))
                    } else {
                        dark.move(to: CGPoint(x: inset, y: y))
                        dark.addLine(to: CGPoint(x: size.width, y: y + 4))
                    }
                }
            case .woven:
                for y in stride(from: 0.0, to: size.height, by: 5.0) {
                    for x in stride(from: 0.0, to: size.width, by: 5.0) {
                        if (Int(x / 5) + Int(y / 5)).isMultiple(of: 2) {
                            light.addRect(CGRect(x: x, y: y, width: 5, height: 1.5))
                        } else {
                            dark.addRect(CGRect(x: x, y: y, width: 1.7, height: 5))
                        }
                    }
                }
            case .engraved:
                for index in 1...20 {
                    let inset = CGFloat(index) * 5
                    switch collection {
                    case .origin, .exclusive:
                        light.move(to: CGPoint(x: size.width * 0.46 + inset, y: 0))
                        light.addQuadCurve(to: CGPoint(x: size.width, y: size.height - inset / 2),
                                           control: CGPoint(x: size.width * 0.52 + inset, y: size.height * 0.58))
                    case .atlas:
                        light.move(to: CGPoint(x: size.width * 0.5 + inset, y: 0))
                        light.addLine(to: CGPoint(x: size.width * 0.28 + inset, y: size.height))
                    case .reserve:
                        light.addEllipse(in: CGRect(x: size.width * 0.5 - inset, y: size.height * 0.45 - inset,
                                                    width: inset * 2, height: inset * 2))
                    }
                }
            }
            context.stroke(light, with: .color(.white.opacity(texture == .engraved ? 0.23 : 0.16)), lineWidth: 0.45)
            context.stroke(dark, with: .color(.black.opacity(0.25)), lineWidth: 0.45)
        }
        .accessibilityHidden(true)
    }
}

struct CardPortrait: View, Equatable {
    let bytes: Data

    var body: some View {
        GeometryReader { geometry in
            if let picture = UIImage(data: bytes) {
                Image(uiImage: picture).resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            }
        }.accessibilityHidden(true)
    }
}
