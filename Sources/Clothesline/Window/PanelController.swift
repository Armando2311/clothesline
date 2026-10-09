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
        case peek        // new screenshot: no focus, remains available until closed
        case dragTarget  // a drag reached the top edge: stays while dragging
    }

    let model: AppModel
    let panel = ClotheslinePanel()
    let lineView: LineView
    private(set) var isVisible = false
    private var reveal: Reveal = .explicit
    private var dragMonitor: Any?
    private var mouseDownMonitor: Any?
    private var dragChangeCount = NSPasteboard(name: .drag).changeCount
    private var currentScreen: NSScreen?

    private var verticalOffsets: [String: Double] = UserDefaults.standard.dictionary(forKey: "panel.verticalOffsets") as? [String: Double] ?? [:]
    static let panelHeight: CGFloat = 210

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
        if isVisible { hide() } else { show(.explicit) }
    }

    func show(_ how: Reveal) {
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
            model.revalidate()
            screenshotRefresh?()
        } else if how == .explicit {
            reveal = .explicit
        }
        if how == .explicit {
            panel.makeKey()
            panel.makeFirstResponder(lineView)
        }
    }

    /// Hook for the app delegate to refresh screenshot preferences on reveal.
    var screenshotRefresh: (() -> Void)?

    func hide() {
        guard isVisible else { return }
        isVisible = false
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
                                       notchRect: notch, height: model.settings.appearanceStyle.panelHeight, verticalOffset: verticalOffsets[displayKey(screen)] ?? 0)
        panel.setFrame(placement.frame, display: false)
        lineView.frame = NSRect(origin: .zero, size: placement.frame.size)
        lineView.configure(notchCenterX: placement.notchCenterX)
    }

    func refreshLayout() { if isVisible { place(on: currentScreen ?? targetScreen()) } }

    @objc private func screensChanged() {
        guard isVisible else { currentScreen = nil; return }
        let screen = NSScreen.screens.contains(where: { $0 == currentScreen }) ? currentScreen! : targetScreen()
        place(on: screen)
    }

    @objc private func panelResignedKey() {
        // Picking up a file in another app deliberately leaves this destination visible.
    }

    private func displayKey(_ screen: NSScreen) -> String {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? "main"
    }

    func lineViewRequestsVerticalMove(_ view: LineView, delta: CGFloat) {
        guard isVisible, let screen = currentScreen else { return }
        reveal = .explicit
        let key = displayKey(screen)
        let top = min(screen.visibleFrame.maxY, screen.frame.maxY - screen.safeAreaInsets.top)
        let maximum = max(0, top - panel.frame.height - screen.visibleFrame.minY)
        verticalOffsets[key] = min(maximum, max(0, (top - panel.frame.maxY) - delta))
        UserDefaults.standard.set(verticalOffsets, forKey: "panel.verticalOffsets")
        place(on: screen)
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

    func lineViewDidInteract(_ view: LineView) { reveal = .explicit }
    func lineViewDragDidExit(_ view: LineView) {}
    func lineViewDidAcceptDrop(_ view: LineView) { reveal = .explicit }
    func lineViewRequestsKeyFocus(_ view: LineView) {
        reveal = .explicit
        panel.makeKey()
    }

}

@MainActor private func QLPreviewPanel_isVisible() -> Bool {
    QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible
}

@MainActor private func QLPreviewPanel_close() {
    QLPreviewPanel.shared().orderOut(nil)
}
