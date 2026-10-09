import AppKit
import ClotheslineCore

/// A complete visual environment for the line: sky, light, rope, wood and paper.
///
/// The palette is original and intentionally restrained: pastel skies, warm
/// light and soft shadows, with one accent colour used only for selection.
struct Theme: Equatable {
    enum Ambient: Equatable {
        case none
        case motes      // drifting specks of light in a sunbeam
        case rain       // fine diagonal rain streaks
        case fireflies  // slow warm glows at night
    }

    var id: ThemeChoice
    var isDark: Bool

    // Sky
    var skyTop: NSColor
    var skyMiddle: NSColor
    var skyBottom: NSColor
    /// Sun or moon glow; position in unit coordinates of the backdrop (y-down).
    var glowColor: NSColor
    var glowPosition: CGPoint
    var glowRadius: CGFloat
    var lightRays: Bool
    var cloudColor: NSColor
    var cloudOpacity: Float
    var stars: Bool
    /// Distant hills and rooftops along the bottom edge.
    var horizonColor: NSColor
    var horizonOpacity: Float

    // Line
    var rope: NSColor
    var ropeHighlight: NSColor
    var hook: NSColor

    // Pins
    var woodLight: NSColor
    var woodDark: NSColor
    var spring: NSColor
    /// Pinned (kept) items get a painted clothespin in this colour.
    var paintedPin: NSColor

    // Paper
    var paper: NSColor
    var paperEdge: NSColor
    var ink: NSColor
    var inkSoft: NSColor
    var noteTints: [NSColor]
    var shadow: NSColor
    var shadowOpacity: Float

    var accent: NSColor
    var ambient: Ambient
    var ambientColor: NSColor

    static func resolve(_ choice: ThemeChoice, appearance: NSAppearance) -> Theme {
        switch choice {
        case .automatic:
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return dark ? .midnight : .summerAfternoon
        case .summerAfternoon: return .summerAfternoon
        case .goldenHour: return .goldenHour
        case .rainyDay: return .rainyDay
        case .midnight: return .midnight
        }
    }

    static let summerAfternoon = Theme(
        id: .summerAfternoon, isDark: false,
        skyTop: NSColor(hex: 0x7FB8F5), skyMiddle: NSColor(hex: 0xB9DCFB), skyBottom: NSColor(hex: 0xFDF1DF),
        glowColor: NSColor(hex: 0xFFF4D2), glowPosition: CGPoint(x: 0.82, y: 0.05), glowRadius: 0.5, lightRays: true,
        cloudColor: .white, cloudOpacity: 0.85, stars: false,
        horizonColor: NSColor(hex: 0x9DBBD8), horizonOpacity: 0.35,
        rope: NSColor(hex: 0xC9A47C), ropeHighlight: NSColor(hex: 0xEED8B8), hook: NSColor(hex: 0x8E6E4E),
        woodLight: NSColor(hex: 0xE9C597), woodDark: NSColor(hex: 0xB8865A), spring: NSColor(hex: 0x8C949C),
        paintedPin: NSColor(hex: 0xF08BA0),
        paper: NSColor(hex: 0xFFFDF8), paperEdge: NSColor(hex: 0xE8E1D4), ink: NSColor(hex: 0x20212B), inkSoft: NSColor(hex: 0x494653),
        noteTints: [NSColor(hex: 0xFFF6C9), NSColor(hex: 0xFFE3E6), NSColor(hex: 0xE2F3E4), NSColor(hex: 0xE4ECFF)],
        shadow: NSColor(hex: 0x2B3F66), shadowOpacity: 0.22,
        accent: NSColor(hex: 0xFF7E9D), ambient: .motes, ambientColor: NSColor(hex: 0xFFF8E0)
    )

    static let goldenHour = Theme(
        id: .goldenHour, isDark: false,
        skyTop: NSColor(hex: 0xE98D6B), skyMiddle: NSColor(hex: 0xF7BE86), skyBottom: NSColor(hex: 0xFFE6C2),
        glowColor: NSColor(hex: 0xFFD889), glowPosition: CGPoint(x: 0.18, y: 0.9), glowRadius: 0.6, lightRays: true,
        cloudColor: NSColor(hex: 0xFFE2CC), cloudOpacity: 0.7, stars: false,
        horizonColor: NSColor(hex: 0xB0656A), horizonOpacity: 0.32,
        rope: NSColor(hex: 0xA97C55), ropeHighlight: NSColor(hex: 0xE7BF8E), hook: NSColor(hex: 0x6E4A33),
        woodLight: NSColor(hex: 0xE6B37E), woodDark: NSColor(hex: 0xA8703F), spring: NSColor(hex: 0x8A7F7A),
        paintedPin: NSColor(hex: 0xE2574C),
        paper: NSColor(hex: 0xFFF8EE), paperEdge: NSColor(hex: 0xEBD9C2), ink: NSColor(hex: 0x29201F), inkSoft: NSColor(hex: 0x55413B),
        noteTints: [NSColor(hex: 0xFFEFC4), NSColor(hex: 0xFFDCCF), NSColor(hex: 0xF3E6C9), NSColor(hex: 0xFCE0E8)],
        shadow: NSColor(hex: 0x6B2A1E), shadowOpacity: 0.26,
        accent: NSColor(hex: 0xFF6A4D), ambient: .motes, ambientColor: NSColor(hex: 0xFFE7B0)
    )

    static let rainyDay = Theme(
        id: .rainyDay, isDark: false,
        skyTop: NSColor(hex: 0x5E6F91), skyMiddle: NSColor(hex: 0x8A9BB6), skyBottom: NSColor(hex: 0xC9D3E0),
        glowColor: NSColor(hex: 0xE6EEF8), glowPosition: CGPoint(x: 0.5, y: 0.0), glowRadius: 0.7, lightRays: false,
        cloudColor: NSColor(hex: 0xD7DEE8), cloudOpacity: 0.55, stars: false,
        horizonColor: NSColor(hex: 0x4F5D78), horizonOpacity: 0.35,
        rope: NSColor(hex: 0x8C7D6D), ropeHighlight: NSColor(hex: 0xBDB1A2), hook: NSColor(hex: 0x5C5148),
        woodLight: NSColor(hex: 0xC9A986), woodDark: NSColor(hex: 0x8E6E52), spring: NSColor(hex: 0x7E8790),
        paintedPin: NSColor(hex: 0x6FA8DC),
        paper: NSColor(hex: 0xF7F8FA), paperEdge: NSColor(hex: 0xD9DEE5), ink: NSColor(hex: 0x202A38), inkSoft: NSColor(hex: 0x465266),
        noteTints: [NSColor(hex: 0xEEF2D8), NSColor(hex: 0xE3E9F3), NSColor(hex: 0xF1E4E8), NSColor(hex: 0xE2EEEA)],
        shadow: NSColor(hex: 0x1D2638), shadowOpacity: 0.28,
        accent: NSColor(hex: 0x7DB9EA), ambient: .rain, ambientColor: NSColor(hex: 0xE9F1FB)
    )

    static let midnight = Theme(
        id: .midnight, isDark: true,
        skyTop: NSColor(hex: 0x0B1430), skyMiddle: NSColor(hex: 0x18264D), skyBottom: NSColor(hex: 0x2F4374),
        glowColor: NSColor(hex: 0xCADBFF), glowPosition: CGPoint(x: 0.14, y: 0.12), glowRadius: 0.35, lightRays: false,
        cloudColor: NSColor(hex: 0x6E7FA8), cloudOpacity: 0.35, stars: true,
        horizonColor: NSColor(hex: 0x070C1E), horizonOpacity: 0.6,
        rope: NSColor(hex: 0x9C8A74), ropeHighlight: NSColor(hex: 0xD3C6B4), hook: NSColor(hex: 0x6F6252),
        woodLight: NSColor(hex: 0xC6A27C), woodDark: NSColor(hex: 0x86664A), spring: NSColor(hex: 0xA8B2C2),
        paintedPin: NSColor(hex: 0xF2C14E),
        paper: NSColor(hex: 0xEDEBE6), paperEdge: NSColor(hex: 0xC9C6C0), ink: NSColor(hex: 0x202331), inkSoft: NSColor(hex: 0x43475B),
        noteTints: [NSColor(hex: 0xEDE6C4), NSColor(hex: 0xE6D7DD), NSColor(hex: 0xD6E3DA), NSColor(hex: 0xD8DEEE)],
        shadow: NSColor(hex: 0x000000), shadowOpacity: 0.45,
        accent: NSColor(hex: 0x9DB8FF), ambient: .fireflies, ambientColor: NSColor(hex: 0xFFE9A3)
    )
}
