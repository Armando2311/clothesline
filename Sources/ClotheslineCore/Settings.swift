import Foundation

/// A keyboard shortcut as a virtual key code plus Carbon-style modifier mask.
/// Kept platform-neutral so settings can be decoded and tested anywhere.
public struct Shortcut: Codable, Equatable, Hashable, Sendable {
    public var keyCode: UInt32
    /// Carbon modifier flags: cmdKey 0x100, shiftKey 0x200, optionKey 0x800, controlKey 0x1000.
    public var modifiers: UInt32
    /// The key's printable label captured when recorded (e.g. "C").
    public var keyLabel: String

    public init(keyCode: UInt32, modifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    public static let command: UInt32 = 0x100
    public static let shift: UInt32 = 0x200
    public static let option: UInt32 = 0x800
    public static let control: UInt32 = 0x1000

    /// ⌃⌥C — "C for Clothesline". Not bound by macOS or common apps by default,
    /// unlike ⌃Space/⌃⌥Space (input sources) or ⌘⇧ letters (heavily used by apps).
    public static let defaultToggle = Shortcut(keyCode: 8, modifiers: control | option, keyLabel: "C")
    /// ⌃⌥V — hang whatever is on the clipboard.
    public static let defaultHangClipboard = Shortcut(keyCode: 9, modifiers: control | option, keyLabel: "V")

    public var displayString: String {
        var s = ""
        if modifiers & Self.control != 0 { s += "⌃" }
        if modifiers & Self.option != 0 { s += "⌥" }
        if modifiers & Self.shift != 0 { s += "⇧" }
        if modifiers & Self.command != 0 { s += "⌘" }
        return s + keyLabel
    }

    /// A global shortcut needs at least one of ⌘, ⌃ or ⌥; Shift alone would
    /// hijack ordinary typing.
    public var isValidGlobalShortcut: Bool {
        modifiers & (Self.command | Self.control | Self.option) != 0
    }
}

public enum ThemeChoice: String, Codable, CaseIterable, Sendable {
    case automatic
    case summerAfternoon
    case goldenHour
    case rainyDay
    case midnight
    case sakuraMorning
    case oceanBreeze
    case lavenderTwilight
    case liquidGlass

    public var displayName: String {
        switch self {
        case .automatic: return "Automatic (Summer / Midnight)"
        case .summerAfternoon: return "Summer Afternoon"
        case .goldenHour: return "Golden Hour"
        case .rainyDay: return "Rainy Day"
        case .midnight: return "Midnight"
        case .sakuraMorning: return "Sakura Morning"
        case .oceanBreeze: return "Ocean Breeze"
        case .lavenderTwilight: return "Lavender Twilight"
        case .liquidGlass: return "Liquid Glass"
        }
    }
}

public enum AfterDragOut: String, Codable, CaseIterable, Sendable {
    case keepOnLine
    case removeFromLine

    public var displayName: String {
        switch self {
        case .keepOnLine: return "Keep it on the line"
        case .removeFromLine: return "Take it off the line"
        }
    }
}

/// All user preferences. Decoding tolerates missing keys so that adding a
/// setting in a later version never resets the others.
public struct AppSettings: Codable, Equatable, Sendable {
    // General
    public var toggleShortcut: Shortcut? = .defaultToggle
    public var hangClipboardShortcut: Shortcut? = .defaultHangClipboard
    public var showMenuBarIcon: Bool = true
    /// Legacy preference retained for decoding; outside clicks never dismiss the line.
    public var hideWhenClickingOutside: Bool = false
    public var revealOnDragToTopEdge: Bool = true

    // Screenshots
    public var collectScreenshots: Bool = true
    public var revealOnScreenshot: Bool = true
    public var includeScreenRecordings: Bool = false
    /// A folder the user picked instead of the macOS screenshot location.
    public var customScreenshotFolder: String?
    public var customScreenshotFolderBookmark: Data?
    /// The line screenshots are hung on; `nil` means the active line.
    public var screenshotLineID: UUID?

    // Dragging
    public var afterDragOut: AfterDragOut = .keepOnLine

    // Appearance & motion
    public var appearanceStyle: AppearanceStyle = .illustrated
    public var theme: ThemeChoice = .automatic
    public var ambientEffects: Bool = true
    public var gentleBreeze: Bool = true
    public var playSounds: Bool = false

    // Cleanup
    public var retention: RetentionPolicy = RetentionPolicy()

    public init() {}

    enum CodingKeys: String, CodingKey {
        case toggleShortcut, hangClipboardShortcut, showMenuBarIcon, hideWhenClickingOutside, revealOnDragToTopEdge
        case collectScreenshots, revealOnScreenshot, includeScreenRecordings, customScreenshotFolder, customScreenshotFolderBookmark, screenshotLineID
        case afterDragOut, appearanceStyle, theme, ambientEffects, gentleBreeze, playSounds, retention
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        // Shortcuts: a missing key means default; an explicit null means "none".
        toggleShortcut = c.contains(.toggleShortcut) ? try c.decodeIfPresent(Shortcut.self, forKey: .toggleShortcut) : d.toggleShortcut
        hangClipboardShortcut = c.contains(.hangClipboardShortcut) ? try c.decodeIfPresent(Shortcut.self, forKey: .hangClipboardShortcut) : d.hangClipboardShortcut
        showMenuBarIcon = (try? c.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon)) ?? d.showMenuBarIcon
        hideWhenClickingOutside = (try? c.decodeIfPresent(Bool.self, forKey: .hideWhenClickingOutside)) ?? d.hideWhenClickingOutside
        revealOnDragToTopEdge = (try? c.decodeIfPresent(Bool.self, forKey: .revealOnDragToTopEdge)) ?? d.revealOnDragToTopEdge
        collectScreenshots = (try? c.decodeIfPresent(Bool.self, forKey: .collectScreenshots)) ?? d.collectScreenshots
        revealOnScreenshot = (try? c.decodeIfPresent(Bool.self, forKey: .revealOnScreenshot)) ?? d.revealOnScreenshot
        includeScreenRecordings = (try? c.decodeIfPresent(Bool.self, forKey: .includeScreenRecordings)) ?? d.includeScreenRecordings
        customScreenshotFolder = try? c.decodeIfPresent(String.self, forKey: .customScreenshotFolder)
        customScreenshotFolderBookmark = try? c.decodeIfPresent(Data.self, forKey: .customScreenshotFolderBookmark)
        screenshotLineID = try? c.decodeIfPresent(UUID.self, forKey: .screenshotLineID)
        afterDragOut = (try? c.decodeIfPresent(AfterDragOut.self, forKey: .afterDragOut)) ?? d.afterDragOut
        appearanceStyle = (try? c.decodeIfPresent(AppearanceStyle.self, forKey: .appearanceStyle)) ?? d.appearanceStyle
        theme = (try? c.decodeIfPresent(ThemeChoice.self, forKey: .theme)) ?? d.theme
        ambientEffects = (try? c.decodeIfPresent(Bool.self, forKey: .ambientEffects)) ?? d.ambientEffects
        gentleBreeze = (try? c.decodeIfPresent(Bool.self, forKey: .gentleBreeze)) ?? d.gentleBreeze
        playSounds = (try? c.decodeIfPresent(Bool.self, forKey: .playSounds)) ?? d.playSounds
        retention = (try? c.decodeIfPresent(RetentionPolicy.self, forKey: .retention)) ?? d.retention
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        // Encode shortcuts explicitly (including null) so "none" survives a round trip.
        try c.encode(toggleShortcut, forKey: .toggleShortcut)
        try c.encode(hangClipboardShortcut, forKey: .hangClipboardShortcut)
        try c.encode(showMenuBarIcon, forKey: .showMenuBarIcon)
        try c.encode(hideWhenClickingOutside, forKey: .hideWhenClickingOutside)
        try c.encode(revealOnDragToTopEdge, forKey: .revealOnDragToTopEdge)
        try c.encode(collectScreenshots, forKey: .collectScreenshots)
        try c.encode(revealOnScreenshot, forKey: .revealOnScreenshot)
        try c.encode(includeScreenRecordings, forKey: .includeScreenRecordings)
        try c.encodeIfPresent(customScreenshotFolder, forKey: .customScreenshotFolder)
        try c.encodeIfPresent(customScreenshotFolderBookmark, forKey: .customScreenshotFolderBookmark)
        try c.encodeIfPresent(screenshotLineID, forKey: .screenshotLineID)
        try c.encode(afterDragOut, forKey: .afterDragOut)
        try c.encode(appearanceStyle, forKey: .appearanceStyle)
        try c.encode(theme, forKey: .theme)
        try c.encode(ambientEffects, forKey: .ambientEffects)
        try c.encode(gentleBreeze, forKey: .gentleBreeze)
        try c.encode(playSounds, forKey: .playSounds)
        try c.encode(retention, forKey: .retention)
    }
}
