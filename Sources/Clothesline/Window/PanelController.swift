import AppKit
import QuickLookUI
import Combine
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
    private var visibilityTransition = 0
    private var escapeMonitor: Any?
    private var glassContainer: NSView?
    private var dragMonitor: Any?
    private var mouseDownMonitor: Any?
    private var dragChangeCount = NSPasteboard(name: .drag).changeCount
    private var currentScreen: NSScreen?
    private var pointerMonitor: Any?
    private var localPointerMonitor: Any?
    private var externalDragActive = false
    private var shakeGesture = ShakeGesture()
    private var cancellables: Set<AnyCancellable> = []

    private var verticalOffsets: [String: Double] = UserDefaults.standard.dictionary(forKey: "panel.verticalOffsets") as? [String: Double] ?? [:]
    static let panelHeight: CGFloat = 210

    init(model: AppModel) {
        self.model = model
        lineView = LineView(model: model)
        lineView.autoresizingMask = [.width, .height]
        super.init()
        panel.contentView = lineView
        lineView.delegate = self

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        nc.addObserver(self, selector: #selector(panelResignedKey), name: NSWindow.didResignKeyNotification, object: panel)
        NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(accessibilityChanged),name:NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,object:nil)
        installDragEdgeMonitor()
        model.$board.receive(on: RunLoop.main).sink { [weak self] _ in self?.refreshLayout(force: false, animated: true) }.store(in: &cancellables)
        model.$query.receive(on: RunLoop.main).sink { [weak self] _ in self?.refreshLayout(force: false, animated: true) }.store(in: &cancellables)
        model.$searchFilters.receive(on: RunLoop.main).sink { [weak self] _ in self?.refreshLayout(force: false, animated: true) }.store(in: &cancellables)
        model.$collapsedGroupIDs.receive(on:RunLoop.main).sink { [weak self] _ in self?.refreshLayout(force: false, animated: true) }.store(in:&cancellables)
        model.$settings.removeDuplicates { a,b in a.theme == b.theme && a.appearanceStyle == b.appearanceStyle && a.cardScale == b.cardScale && a.panelLayout == b.panelLayout && a.noThemeClickThrough == b.noThemeClickThrough }.receive(on: RunLoop.main).sink { [weak self] _ in self?.refreshLayout(animated: true) }.store(in: &cancellables)
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode
            let windowNumber = event.windowNumber
            let consumed = MainActor.assumeIsolated {
                guard let self, self.isVisible, keyCode == 53, windowNumber == self.panel.windowNumber else { return false }
                self.hide()
                return true
            }
            return consumed ? nil : event
        }
    }

    deinit {
        for monitor in [escapeMonitor,dragMonitor,mouseDownMonitor,pointerMonitor,localPointerMonitor].compactMap({ $0 }) { NSEvent.removeMonitor(monitor) }
    }

    // MARK: - Show / hide

    func toggle() {
        if isVisible { hide() } else { show(.explicit) }
    }

    func show(_ how: Reveal) {
        refreshEnvironment()
        let screen = targetScreen()
        let wasVisible = isVisible
        if !wasVisible || screen != currentScreen { place(on: screen) }
        if !wasVisible {
            visibilityTransition += 1
            reveal = how
            lineView.resetAfterDisappear()
            if !panel.isVisible { panel.alphaValue = 0 }
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Motion.reduced ? 0.12 : 0.2
                context.timingFunction = Motion.timing
                panel.animator().alphaValue = 1
            }
            isVisible = true
            syncClickThroughMonitoring()
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
        visibilityTransition += 1
        let transition = visibilityTransition
        stopClickThroughMonitoring()
        if QLPreviewPanel_isVisible() { QLPreviewPanel_close() }
        let duration = lineView.animateDisappear()
        lineView.willDisappear()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration + 0.06
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isVisible, self.visibilityTransition == transition else { return }
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

    private func place(on screen: NSScreen, force: Bool = true, animated: Bool = false) {
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
        var placement = PanelPlacement(screenFrame: screen.frame, visibleFrame: screen.visibleFrame, safeAreaTop: safeTop,
                                       notchRect: notch, height: model.settings.appearanceStyle.panelHeight + max(0, AdaptivePanel.cardScale(model.settings.cardScale) - 1) * 150, verticalOffset: verticalOffsets[displayKey(screen)] ?? 0)
        let fittedWidth = AdaptivePanel.width(available: placement.frame.width, itemCount: model.ropeItems.count,
            cardWidth: (model.settings.appearanceStyle == .compact ? 138 : 100) * AdaptivePanel.cardScale(model.settings.cardScale), fitted: model.settings.panelLayout == .fitted)
        let canvasWidth = placement.frame.width
        let inset = (placement.frame.width - fittedWidth) / 2
        placement.frame.origin.x += inset
        placement.frame.size.width = fittedWidth
        placement.notchCenterX = placement.notchCenterX.map { $0 - inset }
        // Content changes call this on every add or removal; when the panel
        // keeps its size there is nothing to do (the line view animates the
        // change itself).
        if !force, panel.frame == placement.frame, lineView.frame.size == placement.frame.size,
           placedNotchCenterX == placement.notchCenterX { return }
        placedNotchCenterX = placement.notchCenterX
        if animated && isVisible && !Motion.reduced && !lineView.hasActiveDrag && panel.frame.size != placement.frame.size {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Motion.duration()
                context.timingFunction = Motion.timing
                panel.animator().setFrame(placement.frame, display: true)
            }
        } else {
            panel.setFrame(placement.frame, display: false)
            lineView.frame = NSRect(origin: .zero, size: placement.frame.size)
        }
        lineView.configure(notchCenterX: placement.notchCenterX, canvasWidth: canvasWidth)
    }

    private var placedNotchCenterX: Double?

    /// - Parameter force: re-place even if the panel's frame would not change
    ///   (settings such as card size affect the layout inside the same frame).
    func refreshLayout(force: Bool = true, animated: Bool = false) {
        if force { refreshEnvironment() }
        if isVisible { place(on: currentScreen ?? targetScreen(), force: force, animated: animated) }
    }

    /// Put the interactive line inside native glass, preserving its responder and drag surface.
    private func refreshEnvironment() {
        let glass = model.settings.theme == .liquidGlass && !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        panel.hasShadow = glass
        if glass && glassContainer == nil {
            let frame = panel.contentView?.frame ?? lineView.frame
            lineView.removeFromSuperview()
            let container = GlassBackdropView(content: lineView,frame: frame)
            lineView.autoresizingMask = [.width,.height]
            glassContainer = container
            panel.contentView = container
        } else if !glass && glassContainer != nil {
            lineView.removeFromSuperview()
            panel.contentView = lineView
            glassContainer = nil
        }
        lineView.applyTheme()
        syncClickThroughMonitoring()
    }

    @objc private func accessibilityChanged() {
        refreshEnvironment()
        lineView.applyTheme(force:true)
        lineView.updateBreeze()
    }

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
            externalDragActive = false
            shakeGesture.reset()
            updateClickThrough()
            return
        }
        externalDragActive = NSPasteboard(name: .drag).changeCount != dragChangeCount
        if externalDragActive { panel.ignoresMouseEvents = false }
        guard externalDragActive, !isVisible else { return }
        let mouse = NSEvent.mouseLocation
        if model.settings.revealOnShake && shakeGesture.update(x: mouse.x,time: event.timestamp) {
            show(.dragTarget)
            return
        }
        guard model.settings.revealOnDragToTopEdge else { return }
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) else { return }
        if mouse.y >= screen.frame.maxY - 4 {
            show(.dragTarget)
        }
    }

    // MARK: - Optional empty-space pass-through

    /// Pass-through needs pointer tracking, so it only runs while it can matter:
    /// the line is open with No Theme and "click through empty space" enabled.
    /// It is purely event-driven. While the panel ignores the mouse, moves over
    /// the area are delivered to the app underneath and reach the global
    /// monitor; while it does not, they reach the local monitor. No timer.
    private var clickThroughWanted: Bool {
        isVisible && model.settings.theme == .noTheme && model.settings.noThemeClickThrough
    }

    private func syncClickThroughMonitoring() {
        guard clickThroughWanted else {
            stopClickThroughMonitoring()
            return
        }
        if pointerMonitor == nil {
            pointerMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateClickThrough() }
            }
        }
        if localPointerMonitor == nil {
            localPointerMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
                MainActor.assumeIsolated { self?.updateClickThrough() }
                return event
            }
        }
        updateClickThrough()
    }

    /// True while pointer monitors for No Theme pass-through are installed.
    var isTrackingPointerForClickThrough: Bool { pointerMonitor != nil || localPointerMonitor != nil }

    private func stopClickThroughMonitoring() {
        if let pointerMonitor { NSEvent.removeMonitor(pointerMonitor); self.pointerMonitor = nil }
        if let localPointerMonitor { NSEvent.removeMonitor(localPointerMonitor); self.localPointerMonitor = nil }
        panel.ignoresMouseEvents = false
    }

    private func updateClickThrough() {
        guard isVisible, model.settings.theme == .noTheme, model.settings.noThemeClickThrough,
              !externalDragActive, !lineView.hasActiveDrag,
              !(NSEvent.pressedMouseButtons & 1 != 0 && NSPasteboard(name: .drag).changeCount != dragChangeCount) else {
            panel.ignoresMouseEvents = false
            return
        }
        let point = lineView.convert(panel.convertPoint(fromScreen: NSEvent.mouseLocation),from: nil)
        panel.ignoresMouseEvents = lineView.bounds.contains(point) && !lineView.containsInteractiveSurface(point)
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
