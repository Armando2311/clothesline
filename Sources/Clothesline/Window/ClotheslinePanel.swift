import AppKit

/// The borderless floating window that holds the line.
///
/// Why an `NSPanel` with `.nonactivatingPanel`:
/// - It can become the key window (for keyboard navigation and Quick Look)
///   *without* activating Clothesline, so the app you were using stays
///   frontmost and keeps its menu bar.
/// - `.canJoinAllSpaces` + `.fullScreenAuxiliary` let it appear on every Space,
///   including over full-screen apps; `.stationary` keeps it out of Mission
///   Control's window shuffle and `.ignoresCycle` out of ⌘`.
/// - Level `.statusBar` floats it above normal and floating windows but below
///   menus, alerts and the screen saver.
final class ClotheslinePanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 250),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        becomesKeyOnlyIfNeeded = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isExcludedFromWindowsMenu = true
        setAccessibilityLabel("Clothesline")
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
