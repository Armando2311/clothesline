import AppKit
import QuickLookUI
import ClotheslineCore

/// Shows, hides and positions the line.
///
/// Reveal reasons decide focus: an explicit reveal (shortcut, menu) makes the
/// panel key so the keyboard works immediately; automatic reveals (a new
/// screenshot, a drag reaching the top edge) only "peek" and never take focus
/// away from what you are doing.
@MainActor
final class PanelController: NSObject, LineViewDelegate {
    enum Reveal {
        case explicit    // shortcut or menu: interactive, takes key focus
        case peek        // new screenshot: brief, no focus, auto-hides
        case dragTarget  // a drag reached the top edge: stays while dragging
    }

    let model: AppModel
    let panel = ClotheslinePanel()
    let lineView: LineView
    private(set) var isVisible = false
    private var reveal: Reveal = .explicit
    private let autoHide = Delayed()
    private var clickMonitor: Any?
    private var dragMonitor: Any?
    private var mouseDownMonitor: Any?
    private var dragChangeCount = NSPasteboard(name: .drag).changeCount
    private var mouseInside = false
    private var currentScreen: NSScreen?

    static let panelHeight: CGFloat = 252

    init(model: AppModel) {
        self.model = model
        lineView = LineView(model: model)
        super.init()
        panel.contentView = lineView
        lineView.delegate = self

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        nc.addObserver(self, selector: #selector(panelResignedKey), name: NSWindow.didResignKeyNotification, object: panel)
        installDragEdgeMonitor()
    }

    // MARK: - Show / hide

    func toggle() {
        if isVisible && reveal == .explicit { hide() } else { show(.explicit) }
    }

    func show(_ how: Reveal) {
        autoHide.cancel()
        let screen = targetScreen()
        let wasVisible = isVisible
        if !wasVisible || screen != currentScreen { place(on: screen) }
        if !wasVisible {
            reveal = how
            lineView.resetAfterDisappear()
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            isVisible = true
            lineView.willAppear(animated: true)
            installClickOutsideMonitor()
            model.revalidate()
            screenshotRefresh?()
        } else if how == .explicit {
            reveal = .explicit
        }
        if how == .explicit {
            panel.makeKey()
            panel.makeFirstResponder(lineView)
        } else if how == .peek {
            scheduleAutoHide(after: 2.8)
        }
    }

    /// Hook for the app delegate to refresh screenshot preferences on reveal.
    var screenshotRefresh: (() -> Void)?

    func hide() {
        guard isVisible else { return }
        autoHide.cancel()
        isVisible = false
        removeClickOutsideMonitor()
        if QLPreviewPanel_isVisible() { QLPreviewPanel_close() }
        let duration = lineView.animateDisappear()
        lineView.willDisappear()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration + 0.06
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isVisible else { return }
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
                self.lineView.resetAfterDisappear()
            }
        })
    }

    private func scheduleAutoHide(after delay: TimeInterval) {
        guard reveal != .explicit else { return }
        autoHide.schedule(after: delay) { [weak self] in
            guard let self, self.reveal != .explicit else { return }
            if self.mouseInside {
                // Wait until the pointer leaves.
                self.scheduleAutoHide(after: 1.0)
            } else {
                self.hide()
            }
        }
    }

    // MARK: - Placement

    /// The display under the pointer: where the user's attention is.
    private func targetScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func place(on screen: NSScreen) {
        currentScreen = screen
        var notch: CGRect?
        if #available(macOS 12.0, *), screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            // The camera housing is the gap between the two auxiliary areas.
            // Only their widths are used, so this doesn't depend on which
            // coordinate space the areas are reported in.
            let f = screen.frame
            let width = f.width - left.width - right.width
            if width > 0 {
                notch = CGRect(x: f.minX + left.width, y: f.maxY - screen.safeAreaInsets.top, width: width, height: screen.safeAreaInsets.top)
            }
        }
        let safeTop: Double
        if #available(macOS 12.0, *) { safeTop = Double(screen.safeAreaInsets.top) } else { safeTop = 0 }
        let placement = PanelPlacement(screenFrame: screen.frame, visibleFrame: screen.visibleFrame, safeAreaTop: safeTop,
                                       notchRect: notch, height: Double(Self.panelHeight))
        panel.setFrame(placement.frame, display: false)
        lineView.frame = NSRect(origin: .zero, size: placement.frame.size)
        lineView.configure(notchCenterX: placement.notchCenterX)
    }

    @objc private func screensChanged() {
        guard isVisible else { currentScreen = nil; return }
        let screen = NSScreen.screens.contains(where: { $0 == currentScreen }) ? currentScreen! : targetScreen()
        place(on: screen)
    }

    @objc private func panelResignedKey() {
        // Another app took focus; if the user clicked elsewhere the click
        // monitor hides the line. Nothing else to do.
    }

    // MARK: - Click outside

    private func installClickOutsideMonitor() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isVisible, self.model.settings.hideWhenClickingOutside else { return }
                // Global monitors only see clicks in *other* apps, so this is a
                // click outside the line by definition.
                self.hide()
            }
        }
    }

    private func removeClickOutsideMonitor() {
        if let m = clickMonitor { NSEvent.removeMonitor(m) }
        clickMonitor = nil
    }

    // MARK: - Drag to the top edge

    /// Watches for a drag in another app reaching the top edge of a display.
    /// Global monitors for mouse events need no special permission. A drag is
    /// recognised by the drag pasteboard changing after the mouse went down,
    /// so ordinary mouse movement along the menu bar never reveals the line.
    private func installDragEdgeMonitor() {
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.dragChangeCount = NSPasteboard(name: .drag).changeCount
            }
        }
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
            MainActor.assumeIsolated { self?.handleGlobalDrag(event) }
        }
    }

    private func handleGlobalDrag(_ event: NSEvent) {
        if event.type == .leftMouseUp {
            if isVisible && reveal == .dragTarget { scheduleAutoHide(after: 0.6) }
            return
        }
        guard model.settings.revealOnDragToTopEdge, !isVisible else { return }
        guard NSPasteboard(name: .drag).changeCount != dragChangeCount else { return }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) else { return }
        if mouse.y >= screen.frame.maxY - 4 {
            show(.dragTarget)
        }
    }

    // MARK: - LineViewDelegate

    func lineViewRequestsHide(_ view: LineView) { hide() }

    func lineViewDidInteract(_ view: LineView) {
        mouseInside = true
        if reveal != .explicit {
            // Interacting with a peeked line keeps it open until the pointer leaves.
            autoHide.cancel()
            scheduleAutoHide(after: 1.6)
        }
        trackMouseExit()
    }

    func lineViewDragDidExit(_ view: LineView) {
        mouseInside = false
        if reveal == .dragTarget { scheduleAutoHide(after: 0.9) }
    }

    func lineViewDidAcceptDrop(_ view: LineView) {
        if reveal == .dragTarget { scheduleAutoHide(after: 1.4) }
    }

    func lineViewRequestsKeyFocus(_ view: LineView) {
        if reveal != .explicit {
            reveal = .explicit
            autoHide.cancel()
        }
        panel.makeKey()
    }

    private var exitCheck = Delayed()

    /// Lightweight pointer-exit detection while peeking: a check every half
    /// second, only while a peeked line is visible and under the pointer.
    private func trackMouseExit() {
        exitCheck.schedule(after: 0.5) { [weak self] in
            guard let self, self.isVisible else { return }
            self.mouseInside = NSMouseInRect(NSEvent.mouseLocation, self.panel.frame, false)
            if self.mouseInside && self.reveal != .explicit { self.trackMouseExit() }
        }
    }
}

@MainActor private func QLPreviewPanel_isVisible() -> Bool {
    QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible
}

@MainActor private func QLPreviewPanel_close() {
    QLPreviewPanel.shared().orderOut(nil)
}
