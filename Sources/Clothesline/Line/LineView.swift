import AppKit
import SwiftUI
import Combine
import QuickLookUI
import ClotheslineCore

@MainActor
protocol LineViewDelegate: AnyObject {
    func lineViewRequestsVerticalMove(_ view: LineView, delta: CGFloat)
    func lineViewRequestsHide(_ view: LineView)
    func lineViewDidInteract(_ view: LineView)
    func lineViewDragDidExit(_ view: LineView)
    func lineViewDidAcceptDrop(_ view: LineView)
    func lineViewRequestsKeyFocus(_ view: LineView)
}

/// The interactive clothesline: sky, rope, hooks and every hanging item.
///
/// Built directly on Core Animation layers inside one flipped NSView. This
/// keeps hit-testing, multi-item drag sessions and animation under precise
/// control, and lets the render server do all animation work off the main
/// thread. The view owns no data: it renders `AppModel.board` and sends user
/// intent back to the model.
final class LineView: NSView {
    weak var delegate: LineViewDelegate?
    let model: AppModel
    lazy var workflow = WorkflowActions(model: model, view: self)
    private var controls: NSHostingView<LineControls>?
    private(set) var toolbarVisible = false
    private var pointerInside = false
    private var controlsFocused = false
    private var menuTracking = false
    private var toolbarTransition = 0
    lazy var actions = ItemActions(model: model, view: self)

    // Layers
    private let sky = SkyLayer()
    private let lineLayer = CALayer()
    private let ropeBase = CAShapeLayer()
    private let ropeTwist = CAShapeLayer()
    private var hookLayers: [CALayer] = []
    private let itemsLayer = CALayer()
    private var itemLayers: [UUID: ItemLayer] = [:]
    /// Layers created since the last layout; they get placed, not moved.
    private var freshLayers: Set<UUID> = []
    private var thumbnailRetries: Set<UUID> = []
    private var hintLayer: CALayer?
    private let captionLayer = CATextLayer()
    private let lineNameLayer = CATextLayer()

    // State
    private(set) var theme: Theme = .summerAfternoon
    private var geometry = LineGeometry(width: 1200, centerHookX: nil)
    private var layout = LineLayout(geometry: LineGeometry(width: 1200, centerHookX: nil), itemWidth: 100, jitters: [])
    private var orderedIDs: [UUID] = []
    private var renderedLineID: UUID?
    private var renderedCards: [UUID: HangingItem] = [:]
    private var renderedAppearanceStyle: AppearanceStyle = .illustrated
    private var scrollOffset: Double = 0
    private var dropIndex: Int?
    private(set) var selection: Set<UUID> {
        get { model.selectedIDs }
        set { model.selectedIDs = newValue; updateSelectionAppearance() }
    }
    private var anchorID: UUID?
    private var hoveredID: UUID? { didSet { hoverChanged(from: oldValue) } }
    private let hoverCaptionDelay = Delayed()
    private var cancellables: Set<AnyCancellable> = []
    private var notchCenterX: Double?
    private var isOnScreen = false

    // Mouse tracking
    private var mouseDownPoint: CGPoint?
    private var mouseDownItem: UUID?
    private var mouseDownWasSelected = false
    private var draggingIDs: [UUID] = []
    private var internalDropHappened = false

    static let skyInsetBottom: CGFloat = 8
    static let itemWidth: Double = 100

    init(model: AppModel) {
        self.model = model
        super.init(frame: NSRect(x: 0, y: 0, width: 1200, height: 250))
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        layer?.masksToBounds = false
        setupLayers()
        let controls = NSHostingView(rootView: LineControls(model: model, action: { [weak self] action, anchor in
            guard let self else { return }
            self.delegate?.lineViewRequestsKeyFocus(self)
            self.workflow.perform(action, from: anchor)
        }, focusChanged: { [weak self] focused in
            self?.controlsFocused = focused
            self?.refreshToolbarVisibility()
        }, verticalMove: { [weak self] delta in
            guard let self else { return }
            self.delegate?.lineViewRequestsVerticalMove(self, delta: delta)
        }))
        self.controls = controls
        controls.wantsLayer = true
        controls.isHidden = true
        controls.alphaValue = 0
        addSubview(controls)
        NotificationCenter.default.addObserver(self,selector: #selector(menuBegan),name: NSMenu.didBeginTrackingNotification,object: nil)
        NotificationCenter.default.addObserver(self,selector: #selector(menuEnded),name: NSMenu.didEndTrackingNotification,object: nil)
        model.$query.receive(on: RunLoop.main).sink { [weak self] _ in self?.scrollOffset = 0; self?.boardChanged(filtering: true) }.store(in: &cancellables)
        model.$recognizedText.receive(on: RunLoop.main).sink { [weak self] _ in self?.boardChanged(filtering: true) }.store(in: &cancellables)
        model.$selectedIDs.receive(on: RunLoop.main).sink { [weak self] _ in self?.updateSelectionAppearance() }.store(in: &cancellables)
        model.$settings.removeDuplicates { a,b in
            a.theme == b.theme && a.appearanceStyle == b.appearanceStyle && a.ambientEffects == b.ambientEffects && a.gentleBreeze == b.gentleBreeze
        }.receive(on: RunLoop.main).sink { [weak self] _ in self?.applyTheme() }.store(in: &cancellables)
        model.$settings.map(\.keepToolbarVisible).removeDuplicates().receive(on: RunLoop.main).sink { [weak self] _ in self?.refreshToolbarVisibility() }.store(in: &cancellables)
        registerForDraggedTypes(PasteboardImporter.acceptedTypes)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Clothesline")

        model.$board
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.boardChanged() }
            .store(in: &cancellables)
        model.$availability
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshAllCards() }
            .store(in: &cancellables)

        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(accessibilityOptionsChanged), name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    private var scale: CGFloat { window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }

    // MARK: - Setup

    private func setupLayers() {
        guard let root = layer else { return }
        root.addSublayer(sky)
        root.addSublayer(lineLayer)
        lineLayer.addSublayer(ropeBase)
        lineLayer.addSublayer(ropeTwist)
        root.addSublayer(itemsLayer)
        root.addSublayer(captionLayer)
        root.addSublayer(lineNameLayer)
        let none: [String: CAAction] = ["position": NSNull(), "bounds": NSNull(), "path": NSNull(), "contents": NSNull(), "frame": NSNull(), "opacity": NSNull(), "hidden": NSNull(), "string": NSNull(), "strokeEnd": NSNull()]
        for l in [lineLayer, ropeBase, ropeTwist, itemsLayer, captionLayer, lineNameLayer] as [CALayer] { l.actions = none }
        ropeBase.fillColor = nil
        ropeBase.lineWidth = 2.4
        ropeBase.lineCap = .round
        ropeBase.shadowOpacity = 0.3
        ropeBase.shadowRadius = 1.5
        ropeBase.shadowOffset = CGSize(width: 0, height: 2)
        ropeTwist.fillColor = nil
        ropeTwist.lineWidth = 1.1
        ropeTwist.lineDashPattern = [2.2, 2.4]
        ropeTwist.lineCap = .butt
        captionLayer.isHidden = true
        captionLayer.alignmentMode = .center
        captionLayer.truncationMode = .middle
        captionLayer.cornerRadius = 6
        captionLayer.zPosition = 1000
        captionLayer.font = Artwork.roundedFont(13, weight: .semibold)
        captionLayer.fontSize = 13
        lineNameLayer.alignmentMode = .left
        lineNameLayer.font = Artwork.roundedFont(10, weight: .semibold)
        lineNameLayer.fontSize = 10
        lineNameLayer.zPosition = 900
    }

    // MARK: - Placement & theme

    /// Called by the panel controller whenever the panel moves to a display.
    func configure(notchCenterX: Double?) {
        let changed = notchCenterX != self.notchCenterX
        self.notchCenterX = notchCenterX
        if changed { rebuildHooks() }
        applyTheme()
        relayout(animated: false)
    }

    func applyTheme(force: Bool = false) {
        let resolved = Theme.resolve(model.settings.theme, appearance: effectiveAppearance)
        let styleChanged = renderedAppearanceStyle != model.settings.appearanceStyle
        guard force || resolved != theme || styleChanged else { updateAmbient(); updateBreeze(); return }
        renderedAppearanceStyle = model.settings.appearanceStyle
        theme = resolved
        let compact = model.settings.appearanceStyle == .compact
        let transparent = theme.id == .liquidGlass || theme.id == .noTheme
        sky.isHidden = compact || transparent
        layer?.backgroundColor = compact && !transparent ? NSColor.windowBackgroundColor.withAlphaComponent(0.96).cgColor : nil
        let skyRect = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height - Self.skyInsetBottom)
        sky.configure(theme: theme, skyRect: skyRect, scale: scale)
        ropeBase.strokeColor = theme.rope.cgColor
        ropeBase.shadowColor = theme.shadow.cgColor
        ropeTwist.strokeColor = theme.ropeHighlight.withAlphaComponent(0.85).cgColor
        captionLayer.backgroundColor = theme.paper.withAlphaComponent(0.96).cgColor
        captionLayer.foregroundColor = theme.ink.cgColor
        captionLayer.shadowColor = theme.shadow.cgColor
        captionLayer.shadowOpacity = 0.2
        captionLayer.shadowRadius = 3
        captionLayer.contentsScale = scale
        lineNameLayer.foregroundColor = (theme.isDark ? NSColor.white.withAlphaComponent(0.75) : theme.ink.withAlphaComponent(0.7)).cgColor
        lineNameLayer.contentsScale = scale
        rebuildHooks()
        refreshAllCards()
        updateAmbient()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTheme()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        applyTheme(force: true)
    }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize != frame.size
        super.setFrameSize(newSize)
        if changed {
            applyTheme(force: true)
            relayout(animated: false)
        }
    }

    @objc private func accessibilityOptionsChanged() {
        applyTheme(force: true)
        updateAmbient()
        updateBreeze()
    }

    private func rebuildHooks() {
        hookLayers.forEach { $0.removeFromSuperlayer() }
        hookLayers = []
        let image = Artwork.hook(theme: theme, scale: scale)
        for hook in geometry.hooks {
            let l = CALayer()
            l.actions = ["position": NSNull(), "bounds": NSNull()]
            l.contents = image
            l.contentsScale = scale
            l.frame = CGRect(x: hook.x - 8, y: hook.y - 14.5, width: Artwork.hookSize.width, height: Artwork.hookSize.height)
            lineLayer.addSublayer(l)
            hookLayers.append(l)
        }
    }

    // MARK: - Visibility hooks (called by the panel controller)

    func willAppear(animated: Bool) {
        isOnScreen = true
        pointerInside = false
        controlsFocused = false
        menuTracking = false
        setToolbarVisible(model.settings.keepToolbarVisible,animated: false)
        applyTheme()
        relayout(animated: false)
        updateAmbient()
        updateBreeze()
        guard animated, !Motion.reduced else {
            if animated { fade(in: true) }
            return
        }
        // The rope draws itself across, then items drop onto it one by one.
        let draw = CABasicAnimation(keyPath: "strokeEnd")
        draw.fromValue = 0
        draw.toValue = 1
        draw.duration = 0.38
        draw.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ropeBase.add(draw, forKey: "draw")
        ropeTwist.add(draw, forKey: "draw")
        for (i, id) in orderedIDs.enumerated() {
            guard let l = itemLayers[id] else { continue }
            let delay = 0.06 + min(Double(i), 14) * 0.022
            let drop = CASpringAnimation(keyPath: "position.y")
            drop.fromValue = l.position.y - 26
            drop.toValue = l.position.y
            drop.damping = 11
            drop.stiffness = 260
            drop.mass = 0.8
            drop.duration = drop.settlingDuration
            drop.beginTime = CACurrentMediaTime() + delay
            drop.fillMode = .backwards
            l.add(drop, forKey: "appear")
            let fadeIn = CABasicAnimation(keyPath: "opacity")
            fadeIn.fromValue = 0
            fadeIn.toValue = 1
            fadeIn.duration = 0.18
            fadeIn.beginTime = drop.beginTime
            fadeIn.fillMode = .backwards
            l.add(fadeIn, forKey: "appearFade")
        }
        hintLayer.map { fadeLayer($0, in: true) }
    }

    func willDisappear() {
        isOnScreen = false
        pointerInside = false
        controlsFocused = false
        menuTracking = false
        setToolbarVisible(false,animated: false)
        hoveredID = nil
        sky.setAmbientRunning(false)
        itemLayers.values.forEach { $0.removeAnimation(forKey: "breeze") }
    }

    /// Duration of the hide animation; the controller orders the panel out after it.
    @discardableResult
    func animateDisappear() -> TimeInterval {
        guard !Motion.reduced else { return 0.12 }
        for l in itemLayers.values {
            let lift = CABasicAnimation(keyPath: "position.y")
            lift.fromValue = l.position.y
            lift.toValue = l.position.y - 14
            lift.duration = 0.16
            lift.timingFunction = CAMediaTimingFunction(name: .easeIn)
            lift.fillMode = .forwards
            lift.isRemovedOnCompletion = false
            l.add(lift, forKey: "disappear")
        }
        return 0.16
    }

    func resetAfterDisappear() {
        itemLayers.values.forEach { $0.removeAnimation(forKey: "disappear") }
    }

    private func fade(in visible: Bool) {
        guard let root = layer else { return }
        fadeLayer(root, in: visible)
    }

    private func fadeLayer(_ l: CALayer, in visible: Bool) {
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = visible ? 0 : 1
        a.toValue = visible ? 1 : 0
        a.duration = 0.15
        l.add(a, forKey: "fade")
    }

    private func updateAmbient() {
        sky.setAmbientRunning(isOnScreen && model.settings.appearanceStyle != .compact && model.settings.ambientEffects && !Motion.reduced)
    }

    /// A barely perceptible sway while the line is open. Implemented as
    /// render-server animations, so it costs no app CPU, and removed when hidden.
    func updateBreeze() {
        let on = isOnScreen && model.settings.appearanceStyle != .compact && model.settings.gentleBreeze && !Motion.reduced
        for (id, l) in itemLayers {
            l.removeAnimation(forKey: "breeze")
            guard on, let item = model.board.item(id) else { continue }
            let sway = CABasicAnimation(keyPath: "transform.rotation.z")
            let amplitude = 0.012 + abs(item.jitter(11)) * 0.01
            sway.fromValue = -amplitude
            sway.toValue = amplitude
            sway.isAdditive = true
            sway.autoreverses = true
            sway.repeatCount = .infinity
            sway.duration = 2.6 + abs(item.jitter(12)) * 1.6
            sway.timeOffset = abs(item.jitter(13)) * sway.duration
            sway.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            l.add(sway, forKey: "breeze")
        }
    }

    // MARK: - Model → layers

    private func boardChanged(filtering: Bool = false) {
        let board = model.board
        let lineChanged = renderedLineID != board.activeLineID
        renderedLineID = board.activeLineID
        let newIDs = model.visibleItems.map(\.id)
        let oldSet = Set(orderedIDs), newSet = Set(newIDs)
        let removed = orderedIDs.filter { !newSet.contains($0) }
        let added = newIDs.filter { !oldSet.contains($0) }
        orderedIDs = newIDs
        selection = selection.intersection(newSet)

        if lineChanged {
            // Switching lines: swap everything without per-item theatrics.
            itemLayers.values.forEach { $0.removeFromSuperlayer() }
            itemLayers = [:]
            renderedCards = [:]
            scrollOffset = 0
            for id in newIDs { makeLayer(for: id) }
            relayout(animated: false)
            if isOnScreen { fadeLayer(itemsLayer, in: true) }
            updateBreeze()
            updateLineName()
            updateHint(animated: false)
            return
        }

        let animate = isOnScreen && !Motion.reduced
        for id in removed {
            guard let l = itemLayers.removeValue(forKey: id) else { continue }
            renderedCards[id] = nil
            if filtering && isOnScreen {
                CATransaction.begin()
                CATransaction.setCompletionBlock { l.removeFromSuperlayer() }
                fadeLayer(l, in: false); l.opacity = 0
                CATransaction.commit()
            } else if isOnScreen { animateRemoval(of: l, style: model.lastRemovalStyle) } else { l.removeFromSuperlayer() }
        }
        for id in added { makeLayer(for: id) }
        for id in newIDs where !added.contains(id) && renderedCards[id] != board.item(id) { updateCard(for: id) }
        relayout(animated: animate && !filtering)
        if filtering { for id in added { if let l = itemLayers[id] { fadeLayer(l, in: true) } } }
        if animate && !filtering {
            for id in added where model.recentlyAdded.contains(id) {
                if let l = itemLayers[id] { animateClipOn(l) }
            }
            if !added.isEmpty { ropeReaction(dip: 1.28) } else if !removed.isEmpty { ropeReaction(dip: 0.86) }
        }
        if !added.isEmpty || !removed.isEmpty {
            updateBreeze()
            if model.settings.playSounds && isOnScreen && !filtering {
                NSSound(named: added.isEmpty ? "Pop" : "Tink")?.play()
            }
            NSAccessibility.post(element: self, notification: .layoutChanged)
        }
        updateLineName()
        updateHint(animated: animate)
    }

    @discardableResult
    private func makeLayer(for id: UUID) -> ItemLayer? {
        guard model.board.item(id) != nil else { return nil }
        let l = ItemLayer(itemID: id)
        itemsLayer.addSublayer(l)
        itemLayers[id] = l
        freshLayers.insert(id)
        updateCard(for: id)
        return l
    }

    private func refreshAllCards() {
        for id in orderedIDs { updateCard(for: id) }
        relayout(animated: false)
    }

    private func availability(of item: HangingItem) -> Artwork.Availability {
        model.availability[item.id] ?? .available
    }

    private func thumbnailSize(for item: HangingItem) -> CGSize {
        switch item.kind {
        case .pdf: return CGSize(width: 80, height: 104)
        default: return CGSize(width: 110, height: 90)
        }
    }

    private func updateCard(for id: UUID) {
        guard let item = model.board.item(id), let l = itemLayers[id] else { return }
        let avail = availability(of: item)
        var thumb: CGImage?
        var icon: NSImage?
        let wantsThumbnail = [.screenshot, .image, .pdf].contains(item.kind)
        if let url = model.url(for: item) {
            if wantsThumbnail {
                let size = thumbnailSize(for: item)
                thumb = model.thumbnails.cached(for: url, size: size, scale: scale)
                if thumb == nil {
                    model.thumbnails.thumbnail(for: url, size: size, scale: scale) { [weak self] image in
                        guard let self else { return }
                        guard image != nil else {
                            // A file that was only just written can fail once; retry a single time.
                            if self.thumbnailRetries.insert(id).inserted {
                                after(1.0) { [weak self] in self?.updateCard(for: id) }
                            }
                            return
                        }
                        self.updateCard(for: id)
                        self.relayout(animated: false)
                    }
                }
            } else if item.kind == .file {
                icon = NSWorkspace.shared.icon(forFile: url.path)
            }
        }
        let input = Artwork.CardInput(item: item, thumbnail: thumb, icon: icon, availability: avail, theme: theme, scale: scale)
        let card = model.settings.appearanceStyle == .compact ? Artwork.compactCard(input) : Artwork.card(input)
        let pin = Artwork.clothespin(theme: theme, painted: item.pinned, scale: scale)
        renderedCards[id] = item
        l.configure(card: card, pin: pin, theme: theme, scale: scale)
        l.isSelected = selection.contains(id)
        l.setAccessibilityDescription(item)
    }

    // MARK: - Layout

    func relayout(animated: Bool) {
        let width = Double(bounds.width)
        guard width > 0 else { return }
        geometry = LineGeometry(width: width, centerHookX: notchCenterX, sagScale: model.settings.appearanceStyle == .compact ? 0.15 : 0.35)
        let skyRect = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height - Self.skyInsetBottom)
        sky.configure(theme: theme, skyRect: skyRect, scale: scale)
        lineLayer.frame = bounds
        itemsLayer.frame = bounds
        let ropePath = path(for: geometry)
        ropeBase.path = ropePath
        ropeTwist.path = ropePath
        if hookLayers.count != geometry.hooks.count { rebuildHooks() }
        for (l, hook) in zip(hookLayers, geometry.hooks) {
            l.frame = CGRect(x: hook.x - 8, y: hook.y - 14.5, width: Artwork.hookSize.width, height: Artwork.hookSize.height)
        }

        let items = orderedIDs.compactMap { model.board.item($0) }
        var jitters = items.map { $0.jitter(1) }
        if let dropIndex { jitters.insert(0, at: min(dropIndex, jitters.count)) }
        layout = LineLayout(geometry: geometry, itemWidth: model.settings.appearanceStyle == .compact ? 138 : Self.itemWidth, jitters: jitters, scroll: scrollOffset, reduceMotion: Motion.reduced)
        scrollOffset = min(scrollOffset, layout.overflow)

        for (i, item) in items.enumerated() {
            guard let l = itemLayers[item.id] else { continue }
            let slotIndex = (dropIndex.map { i >= $0 } ?? false) ? i + 1 : i
            guard slotIndex < layout.slots.count else { continue }
            let slot = layout.slots[slotIndex]
            let newPos = CGPoint(x: slot.x, y: slot.y)
            let newTransform = CATransform3DMakeRotation(model.settings.appearanceStyle == .compact ? 0 : CGFloat(slot.rotation), 0, 0, 1)
            l.zPosition = CGFloat(i)
            let isFresh = freshLayers.remove(item.id) != nil
            if animated && !isFresh && l.animation(forKey: "clipOn") == nil {
                let from = l.presentation()?.position ?? l.position
                if hypot(from.x - newPos.x, from.y - newPos.y) > 0.5 {
                    let move = CASpringAnimation(keyPath: "position")
                    move.fromValue = NSValue(point: from)
                    move.toValue = NSValue(point: newPos)
                    move.damping = 18
                    move.stiffness = 240
                    move.duration = move.settlingDuration
                    l.add(move, forKey: "move")
                    // Moving along the rope makes the item swing a little.
                    swing(l, impulse: CGFloat(max(-0.08, min(0.08, (from.x - newPos.x) / 400))))
                }
            }
            l.position = newPos
            l.transform = newTransform
            l.opacity = slot.visible ? (draggingIDs.contains(item.id) ? 0.35 : 1) : 0
        }
        controls?.frame = CGRect(x: 10, y: bounds.height - 46, width: max(0,bounds.width-20), height: 40)
        positionLineName()
        positionHint()
        updateAccessibilityChildren()
    }

    private func path(for g: LineGeometry) -> CGPath {
        let p = CGMutablePath()
        for (i, s) in g.segments.enumerated() {
            if i == 0 { p.move(to: CGPoint(x: s.start.x, y: s.start.y)) }
            p.addQuadCurve(to: CGPoint(x: s.end.x, y: s.end.y), control: CGPoint(x: s.controlPoint.x, y: s.controlPoint.y))
        }
        return p
    }

    // MARK: - Animations

    private func animateClipOn(_ l: ItemLayer) {
        // Fall from above, overshoot slightly onto the rope, then settle.
        let drop = CASpringAnimation(keyPath: "position.y")
        drop.fromValue = l.position.y - 70
        drop.toValue = l.position.y
        drop.damping = 10
        drop.stiffness = 210
        drop.mass = 0.9
        drop.initialVelocity = 2
        drop.duration = drop.settlingDuration
        l.add(drop, forKey: "clipOn")
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0
        fadeIn.toValue = l.opacity
        fadeIn.duration = 0.12
        l.add(fadeIn, forKey: "clipOnFade")
        swing(l, impulse: CGFloat(0.16 * (orderedIDs.firstIndex(of: l.itemID).map { $0 % 2 == 0 ? 1 : -1 } ?? 1)))
        // Neighbours feel the rope move.
        if let i = orderedIDs.firstIndex(of: l.itemID) {
            for (offset, strength) in [(-1, 0.05), (1, -0.05), (-2, 0.025), (2, -0.025)] {
                let j = i + offset
                guard orderedIDs.indices.contains(j), let n = itemLayers[orderedIDs[j]] else { continue }
                swing(n, impulse: CGFloat(strength), delay: 0.12)
            }
        }
    }

    private func animateRemoval(of l: ItemLayer, style: AppModel.RemovalStyle) {
        let group = CAAnimationGroup()
        let fall = CABasicAnimation(keyPath: "position.y")
        let rotate = CABasicAnimation(keyPath: "transform.rotation.z")
        let fade = CABasicAnimation(keyPath: "opacity")
        switch style {
        case .unclip:
            fall.toValue = l.position.y + 90
            fall.timingFunction = CAMediaTimingFunction(controlPoints: 0.5, 0, 0.9, 0.6)
            rotate.byValue = CGFloat(l.itemID.uuid.0 % 2 == 0 ? 0.35 : -0.35)
            rotate.isAdditive = true
        case .delivered:
            fall.toValue = l.position.y - 40
            fall.timingFunction = CAMediaTimingFunction(name: .easeIn)
            rotate.byValue = 0
        }
        fade.toValue = 0
        group.animations = [fall, rotate, fade]
        group.duration = Motion.reduced ? 0.15 : 0.36
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        if Motion.reduced { group.animations = [fade] }
        CATransaction.begin()
        CATransaction.setCompletionBlock { l.removeFromSuperlayer() }
        l.add(group, forKey: "remove")
        CATransaction.commit()
    }

    /// An additive spring on rotation: the item swings and comes to rest.
    private func swing(_ l: CALayer, impulse: CGFloat, delay: CFTimeInterval = 0) {
        guard !Motion.reduced, abs(impulse) > 0.002 else { return }
        let s = CASpringAnimation(keyPath: "transform.rotation.z")
        s.fromValue = impulse
        s.toValue = 0
        s.isAdditive = true
        s.damping = 4.5
        s.stiffness = 60
        s.mass = 0.6
        s.duration = min(s.settlingDuration, 3)
        if delay > 0 {
            s.beginTime = CACurrentMediaTime() + delay
            s.fillMode = .backwards
        }
        l.add(s, forKey: "swing-\(UUID().uuidString.prefix(6))")
    }

    /// The rope dips (or springs up) and settles, as when weight is added or removed.
    private func ropeReaction(dip: Double) {
        guard !Motion.reduced else { return }
        let from = path(for: LineGeometry(width: geometry.width, centerHookX: notchCenterX, sagScale: dip))
        for shape in [ropeBase, ropeTwist] {
            let a = CASpringAnimation(keyPath: "path")
            a.fromValue = from
            a.toValue = shape.path
            a.damping = 7
            a.stiffness = 140
            a.mass = 0.7
            a.duration = a.settlingDuration
            shape.add(a, forKey: "rope")
        }
    }

    // MARK: - Line name & empty state

    private func updateLineName() {
        lineNameLayer.isHidden = true
        lineNameLayer.string = ""
        positionLineName()
    }

    private func positionLineName() {
        let x = (geometry.hooks.first?.x ?? 30) + 14
        lineNameLayer.frame = CGRect(x: x, y: 3, width: 220, height: 14)
    }

    var lineNameRect: CGRect { lineNameLayer.isHidden ? .zero : lineNameLayer.frame.insetBy(dx: -4, dy: -3) }

    private func updateHint(animated: Bool) {
        if orderedIDs.isEmpty {
            if hintLayer == nil {
                let l = CALayer()
                l.actions = ["position": NSNull(), "bounds": NSNull(), "contents": NSNull()]
                l.anchorPoint = CGPoint(x: 0.5, y: 0)
                itemsLayer.addSublayer(l)
                hintLayer = l
                let pin = CALayer()
                pin.name = "pin"
                pin.actions = ["position": NSNull(), "bounds": NSNull(), "contents": NSNull()]
                l.addSublayer(pin)
                if animated { fadeLayer(l, in: true) }
            }
            configureHint()
        } else if let h = hintLayer {
            hintLayer = nil
            if animated {
                CATransaction.begin()
                CATransaction.setCompletionBlock { h.removeFromSuperlayer() }
                fadeLayer(h, in: false)
                h.opacity = 0
                CATransaction.commit()
            } else {
                h.removeFromSuperlayer()
            }
        }
    }

    private func configureHint() {
        guard let l = hintLayer else { return }
        let shortcut = model.settings.toggleShortcut?.displayString ?? "the menu bar icon"
        let (image, size) = Artwork.hintTag(
            text: model.isSearching ? "No matching items" : "Drop anything here",
            detail: model.isSearching ? "Try another word or clear the search" : "Screenshots hang themselves · \(shortcut) shows or hides the line",
            theme: theme, scale: scale)
        let top = Artwork.pinSize.height - Artwork.pinGrip
        l.bounds = CGRect(x: 0, y: 0, width: size.width, height: size.height + top)
        l.contents = nil
        let card = l.sublayers?.first { $0.name == "card" } ?? {
            let c = CALayer()
            c.name = "card"
            c.actions = ["position": NSNull(), "bounds": NSNull(), "contents": NSNull()]
            c.shadowOpacity = theme.shadowOpacity
            c.shadowRadius = 3
            c.shadowOffset = CGSize(width: 0, height: 2)
            l.insertSublayer(c, at: 0)
            return c
        }()
        card.frame = CGRect(x: 0, y: top, width: size.width, height: size.height)
        card.contents = image
        card.contentsScale = scale
        card.shadowColor = theme.shadow.cgColor
        if let pin = l.sublayers?.first(where: { $0.name == "pin" }) {
            pin.frame = CGRect(x: (size.width - Artwork.pinSize.width) / 2, y: 0, width: Artwork.pinSize.width, height: Artwork.pinSize.height)
            pin.contents = Artwork.clothespin(theme: theme, painted: false, scale: scale)
            pin.contentsScale = scale
        }
        positionHint()
    }

    private func positionHint() {
        guard let l = hintLayer else { return }
        // Hang the hint in the middle of the widest usable stretch of rope.
        let interval = geometry.usableIntervals.max { ($0.upperBound - $0.lowerBound) < ($1.upperBound - $1.lowerBound) }
        let x = interval.map { ($0.lowerBound + $0.upperBound) / 2 } ?? geometry.width / 2
        let y = geometry.ropeY(atX: x) - Double(Artwork.pinRopeY)
        l.position = CGPoint(x: x, y: y)
        l.transform = CATransform3DMakeRotation(CGFloat(geometry.ropeAngle(atX: x) * 0.5), 0, 0, 1)
    }

    // MARK: - Selection

    private func updateSelectionAppearance() {
        for (id, l) in itemLayers { l.isSelected = selection.contains(id) }
        updateAccessibilityChildren()
        if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible {
            QLPreviewPanel.shared().reloadData()
        }
    }

    var selectedItems: [HangingItem] {
        orderedIDs.filter { selection.contains($0) }.compactMap { model.board.item($0) }
    }

    func select(_ ids: Set<UUID>) { selection = ids }

    private func selectRange(to id: UUID) {
        guard let anchor = anchorID, let a = orderedIDs.firstIndex(of: anchor), let b = orderedIDs.firstIndex(of: id) else {
            selection = [id]
            anchorID = id
            return
        }
        selection = Set(orderedIDs[min(a, b)...max(a, b)])
    }

    // MARK: - Hit testing

    func itemID(at point: CGPoint) -> UUID? {
        // Topmost (highest zPosition) first.
        for id in orderedIDs.reversed() {
            guard let l = itemLayers[id], l.opacity > 0.01, let root = layer else { continue }
            let p = root.convert(point, to: l)
            if l.containsItemPoint(p) { return id }
        }
        return nil
    }

    /// The item's card rectangle in view coordinates (axis-aligned bounds).
    func rect(for id: UUID) -> CGRect? {
        guard let l = itemLayers[id], let root = layer else { return nil }
        return root.convert(l.bounds, from: l)
    }

    // MARK: - Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        pointerInside = true
        refreshToolbarVisibility()
        let p = convert(event.locationInWindow, from: nil)
        hoveredID = itemID(at: p)
        delegate?.lineViewDidInteract(self)
    }

    override func mouseEntered(with event: NSEvent) {
        pointerInside = true
        refreshToolbarVisibility()
        delegate?.lineViewDidInteract(self)
    }

    override func mouseExited(with event: NSEvent) {
        pointerInside = false
        refreshToolbarVisibility()
        hoveredID = nil
    }

    @objc private func menuBegan() {
        guard toolbarVisible else { return }
        menuTracking = true
    }
    @objc private func menuEnded() {
        menuTracking = false
        refreshToolbarVisibility()
    }
    private func refreshToolbarVisibility() {
        setToolbarVisible(isOnScreen && (model.settings.keepToolbarVisible || pointerInside || controlsFocused || menuTracking),animated: true)
    }
    func setToolbarVisible(_ visible: Bool, animated: Bool) {
        guard let controls else { return }
        guard visible != toolbarVisible || !animated else { return }
        toolbarVisible = visible
        toolbarTransition += 1
        let transition = toolbarTransition
        let currentSlide = controls.layer?.presentation()?.transform.m42
        controls.layer?.removeAnimation(forKey: "toolbarSlide")
        let duration = animated ? (Motion.reduced ? 0.1 : 0.18) : 0
        if visible { controls.isHidden = false }
        if duration == 0 {
            controls.alphaValue = visible ? 1 : 0
            controls.isHidden = !visible
        } else {
            if !Motion.reduced, let layer = controls.layer {
                let slide = CABasicAnimation(keyPath: "transform.translation.y")
                slide.fromValue = currentSlide ?? (visible ? 8 : 0)
                slide.toValue = visible ? 0 : 8
                slide.duration = duration
                slide.timingFunction = CAMediaTimingFunction(controlPoints: 0.2,0.8,0.2,1)
                layer.add(slide,forKey: "toolbarSlide")
            }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2,0.8,0.2,1)
                controls.animator().alphaValue = visible ? 1 : 0
            },completionHandler: { [weak self,weak controls] in
                MainActor.assumeIsolated {
                    guard let self, self.toolbarTransition == transition else { return }
                    controls?.isHidden = !visible
                }
            })
        }
        updateAccessibilityChildren()
    }

    private func hoverChanged(from old: UUID?) {
        if let old, let l = itemLayers[old] { l.isHovered = false }
        captionLayer.isHidden = true
        hoverCaptionDelay.cancel()
        guard let id = hoveredID, let l = itemLayers[id] else { return }
        l.isHovered = true
        swing(l, impulse: 0.035)
        hoverCaptionDelay.schedule(after: 0.55) { [weak self] in self?.showCaption(for: id) }
    }

    private func showCaption(for id: UUID) {
        guard hoveredID == id, let item = model.board.item(id), let r = rect(for: id) else { return }
        var parts = [item.title]
        switch availability(of: item) {
        case .missing: parts.append("File not found")
        case .offline: parts.append("Drive not connected")
        case .available:
            if let url = model.url(for: item), let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                parts.append(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
            } else if item.kind == .link, let link = item.link {
                parts = [link]
            }
        }
        if item.pinned { parts.append("Pinned") }
        let text = parts.joined(separator: " · ")
        let width = min(320, max(80, CGFloat(text.count) * 5.8 + 20))
        let y = min(bounds.height - Self.skyInsetBottom - 22, r.maxY + 4)
        captionLayer.string = text
        captionLayer.frame = CGRect(x: max(6, min(bounds.width - width - 6, r.midX - width / 2)), y: y, width: width, height: 18)
        captionLayer.isHidden = false
    }

    override func mouseDown(with event: NSEvent) {
        delegate?.lineViewDidInteract(self)
        delegate?.lineViewRequestsKeyFocus(self)
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)
        captionLayer.isHidden = true

        if lineNameRect.contains(p) {
            showLinesMenu(at: p)
            return
        }

        let hit = itemID(at: p)
        mouseDownPoint = p
        mouseDownItem = hit
        mouseDownWasSelected = hit.map { selection.contains($0) } ?? false

        guard let id = hit else {
            if !event.modifierFlags.contains(.command) && !event.modifierFlags.contains(.shift) { selection = [] }
            return
        }
        if event.clickCount == 2 {
            actions.open([model.board.item(id)].compactMap { $0 })
            return
        }
        if event.modifierFlags.contains(.command) {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
            anchorID = id
        } else if event.modifierFlags.contains(.shift) {
            selectRange(to: id)
        } else if !selection.contains(id) {
            selection = [id]
            anchorID = id
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint, let id = mouseDownItem else { return }
        let p = convert(event.locationInWindow, from: nil)
        guard hypot(p.x - start.x, p.y - start.y) > 4 else { return }
        mouseDownPoint = nil
        if !selection.contains(id) { selection = [id] }
        beginDrag(event: event)
    }

    override func mouseUp(with event: NSEvent) {
        // A plain click on an already-selected item narrows the selection to it.
        if let id = mouseDownItem, mouseDownPoint != nil, mouseDownWasSelected,
           !event.modifierFlags.contains(.command), !event.modifierFlags.contains(.shift), event.clickCount == 1 {
            selection = [id]
            anchorID = id
        }
        mouseDownPoint = nil
        mouseDownItem = nil
    }

    override func rightMouseDown(with event: NSEvent) {
        delegate?.lineViewDidInteract(self)
        let p = convert(event.locationInWindow, from: nil)
        if let id = itemID(at: p) {
            if !selection.contains(id) { selection = [id]; anchorID = id }
            NSMenu.popUpContextMenu(actions.menu(for: selectedItems), with: event, for: self)
        } else {
            NSMenu.popUpContextMenu(actions.lineMenu(), with: event, for: self)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard layout.overflow > 0 else { return }
        let dx = event.scrollingDeltaX, dy = event.scrollingDeltaY
        let delta = abs(dx) > abs(dy) ? -dx : -dy
        let factor: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 12
        scrollOffset = min(max(0, scrollOffset + Double(delta * factor)), layout.overflow)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        relayout(animated: false)
        CATransaction.commit()
    }

    private func showLinesMenu(at point: CGPoint) {
        actions.linesMenu().popUp(positioning: nil, at: NSPoint(x: lineNameRect.minX, y: lineNameRect.maxY + 4), in: self)
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        delegate?.lineViewDidInteract(self)
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command), handleCommandKey(event) { return }
        switch Int(event.keyCode) {
        case 123: moveFocus(by: -1, extend: flags.contains(.shift))  // ←
        case 124: moveFocus(by: 1, extend: flags.contains(.shift))   // →
        case 49: toggleQuickLook()                                    // space
        case 51, 117: actions.removeFromLine(selectedItems)           // ⌫ ⌦
        case 36, 76: actions.open(selectedItems)                      // ↩
        case 53: delegate?.lineViewRequestsHide(self)                  // ⎋
        case 48: model.cycleLine(by: flags.contains(.shift) ? -1 : 1) // ⇥
        default:
            if event.charactersIgnoringModifiers?.lowercased() == "p", !selection.isEmpty {
                model.togglePinned(selection)
            } else {
                super.keyDown(with: event)
            }
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.isKeyWindow == true, window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        if event.modifierFlags.contains(.command), handleCommandKey(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    private func handleCommandKey(_ event: NSEvent) -> Bool {
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let shift = event.modifierFlags.contains(.shift)
        switch chars {
        case ",": workflow.perform(.settings); return true
        case "f": focusSearch(); return true
        case "a": selection = Set(orderedIDs); return true
        case "c": if !selection.isEmpty { _ = DragWriters.copyToPasteboard(selectedItems, model: model) }; return true
        case "v": PasteboardImporter.importContents(of: .general, into: model, source: .clipboard); return true
        case "z": if !shift { model.undoLastRemoval() }; return true
        case "w": delegate?.lineViewRequestsHide(self); return true
        case "o": actions.open(selectedItems); return true
        case "r": actions.reveal(selectedItems); return true
        case "y": toggleQuickLook(); return true
        case "[": model.cycleLine(by: -1); return true
        case "]": model.cycleLine(by: 1); return true
        default:
            if let n = Int(chars), n >= 1, n <= 9, n <= model.board.lines.count {
                model.activate(lineID: model.board.lines[n - 1].id)
                return true
            }
            if event.keyCode == 51 { // ⌘⌫ = remove from line
                actions.removeFromLine(selectedItems)
                return true
            }
            return false
        }
    }

    private func moveFocus(by delta: Int, extend: Bool) {
        guard !orderedIDs.isEmpty else { return }
        let current = anchorID.flatMap { orderedIDs.firstIndex(of: $0) }
            ?? (delta > 0 ? -1 : orderedIDs.count)
        let next = max(0, min(orderedIDs.count - 1, current + delta))
        let id = orderedIDs[next]
        if extend {
            selection.insert(id)
        } else {
            selection = [id]
        }
        anchorID = id
        if let l = itemLayers[id] { swing(l, impulse: CGFloat(delta) * 0.04) }
        scrollToReveal(id)
    }

    func focusSearch() {
        setToolbarVisible(true,animated: false)
        delegate?.lineViewRequestsKeyFocus(self)
        NotificationCenter.default.post(name: .clotheslineSearch, object: nil)
    }
    func scrollPage(_ direction: Double) {
        scrollOffset = min(max(0, scrollOffset + direction * max(100,geometry.usableLength * 0.7)),layout.overflow)
        relayout(animated: false)
    }

    private func scrollToReveal(_ id: UUID) {
        guard layout.overflow > 0, let i = orderedIDs.firstIndex(of: id), i < layout.slots.count else { return }
        let x = layout.slots[i].x
        let margin = 120.0
        if x < margin { scrollOffset = max(0, scrollOffset - (margin - x)) }
        if x > geometry.width - margin { scrollOffset = min(layout.overflow, scrollOffset + (x - (geometry.width - margin))) }
        relayout(animated: true)
    }

    // MARK: - Quick Look

    func toggleQuickLook() {
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            if selection.isEmpty, let first = orderedIDs.first { selection = [first] }
            delegate?.lineViewRequestsKeyFocus(self)
            window?.makeFirstResponder(self)
            panel.makeKeyAndOrderFront(nil)
        }
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self
        // Keep Quick Look above the line.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }

    private var previewURLs: [URL] {
        selectedItems.compactMap { actions.previewURL(for: $0) }
    }

    // MARK: - Dragging out

    private func beginDrag(event: NSEvent) {
        let items = selectedItems
        var dragItems: [NSDraggingItem] = []
        var ids: [UUID] = []
        for (n, item) in items.enumerated() {
            guard let writer = DragWriters.writer(for: item, model: model), let l = itemLayers[item.id], let r = rect(for: item.id) else { continue }
            let dragItem = NSDraggingItem(pasteboardWriter: writer)
            let image = l.snapshot(scale: scale)
            // Stack multiple items slightly so the drag reads as a bundle.
            let frame = NSRect(origin: CGPoint(x: r.midX - l.bounds.width / 2 + CGFloat(n) * 3, y: r.midY - l.bounds.height / 2 + CGFloat(n) * 3), size: l.bounds.size)
            dragItem.setDraggingFrame(frame, contents: image)
            dragItems.append(dragItem)
            ids.append(item.id)
        }
        guard !dragItems.isEmpty else {
            NSSound.beep()
            return
        }
        draggingIDs = ids
        internalDropHappened = false
        let session = beginDraggingSession(with: dragItems, event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .pile
        relayout(animated: false)
    }

    // MARK: - Dropping in

    private func insertionIndex(for sender: NSDraggingInfo) -> Int {
        let p = convert(sender.draggingLocation, from: nil)
        let slots = dropIndex == nil ? layout.slots : layout.slots.enumerated().filter { $0.offset != dropIndex }.map(\.element)
        return LineLayout.insertionIndex(forX: Double(p.x), in: slots)
    }

    private func internalIDs(_ sender: NSDraggingInfo) -> [UUID]? {
        if (sender.draggingSource as? LineView) === self { return draggingIDs }
        if let grid = sender.draggingSource as? CollectionDragView, grid.model === model { return grid.draggingIDs }
        return nil
    }
    private func isInternal(_ sender: NSDraggingInfo) -> Bool { internalIDs(sender) != nil }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        delegate?.lineViewDidInteract(self)
        if model.isSearching && isInternal(sender) { return [] }
        if !isInternal(sender) {
            guard PasteboardImporter.canImport(sender.draggingPasteboard) else { return [] }
        }
        updateDropIndex(insertionIndex(for: sender))
        return isInternal(sender) ? .move : .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if model.isSearching && isInternal(sender) { return [] }
        if !isInternal(sender) && !PasteboardImporter.canImport(sender.draggingPasteboard) { return [] }
        updateDropIndex(insertionIndex(for: sender))
        return isInternal(sender) ? .move : .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        updateDropIndex(nil)
        delegate?.lineViewDragDidExit(self)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let index = dropIndex ?? orderedIDs.count
        updateDropIndex(nil, animated: false)
        if isInternal(sender) {
            guard !model.isSearching else { return false }
            internalDropHappened = true
            (sender.draggingSource as? CollectionDragView)?.didDropInternally = true
            let moving = Set(internalIDs(sender) ?? [])
            let before = orderedIDs.prefix(index).filter { !moving.contains($0) }.count
            model.move(moving, toPosition: before)
            return true
        }
        let ids = PasteboardImporter.importContents(of: sender.draggingPasteboard, into: model, source: .drop, at: model.isSearching ? nil : index)
        delegate?.lineViewDidAcceptDrop(self)
        if !ids.isEmpty { model.query = ""; selection = Set(ids) }
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        updateDropIndex(nil)
    }

    private func updateDropIndex(_ index: Int?, animated: Bool = true) {
        guard index != dropIndex else { return }
        dropIndex = index
        relayout(animated: animated && !Motion.reduced)
    }

    // MARK: - Accessibility

    private var accessibilityItems: [ItemAccessibilityElement] = []

    private func updateAccessibilityChildren() {
        accessibilityItems = orderedIDs.compactMap { id in
            guard let item = model.board.item(id), let r = rect(for: id) else { return nil }
            let e = ItemAccessibilityElement(itemID: id, view: self)
            e.setAccessibilityLabel("\(item.kind.displayName): \(item.title)\(item.pinned ? ", pinned" : "")")
            e.setAccessibilityFrameInParentSpace(r)
            e.setAccessibilitySelected(selection.contains(id))
            return e
        }
        setAccessibilityChildren(accessibilityItems + (toolbarVisible ? (controls.map { [$0 as Any] } ?? []) : []))
    }

    fileprivate func accessibilityPress(_ id: UUID) {
        selection = [id]
        anchorID = id
        toggleQuickLook()
    }
}

// MARK: - NSDraggingSource

extension LineView: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        DragPolicy.operation(items: draggingIDs.compactMap { model.board.item($0) },context: context,modifiers: NSEvent.modifierFlags)
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        let ids = draggingIDs
        draggingIDs = []
        defer { relayout(animated: false) }
        guard !internalDropHappened else { return }
        if operation.contains(.move) {
            // The file now lives where it was dropped; its old location is gone.
            model.remove(Set(ids), style: .delivered, undoable: false)
        } else if operation != [] && model.settings.afterDragOut == .removeFromLine {
            model.remove(Set(ids), style: .delivered)
        }
    }
}

// MARK: - Quick Look data source

extension LineView: QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { previewURLs.count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        previewURLs[index] as NSURL
    }

    func previewPanel(_ panel: QLPreviewPanel!, sourceFrameOnScreenFor item: QLPreviewItem!) -> NSRect {
        guard let url = item.previewItemURL, let window,
              let entry = selectedItems.first(where: { actions.previewURL(for: $0) == url }),
              let r = rect(for: entry.id) else { return .zero }
        return window.convertToScreen(convert(r, to: nil))
    }

    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        if event.type == .keyDown, [123, 124].contains(Int(event.keyCode)) {
            keyDown(with: event)
            return true
        }
        return false
    }
}

// MARK: - Accessibility element

final class ItemAccessibilityElement: NSAccessibilityElement {
    let itemID: UUID
    weak var view: LineView?

    init(itemID: UUID, view: LineView) {
        self.itemID = itemID
        self.view = view
        super.init()
        setAccessibilityRole(.button)
        setAccessibilityParent(view)
    }

    override func accessibilityPerformPress() -> Bool {
        MainActor.assumeIsolated { view?.accessibilityPress(itemID) }
        return true
    }
}

private extension ItemLayer {
    func setAccessibilityDescription(_ item: HangingItem) {
        name = "\(item.kind.displayName) \(item.title)"
    }
}
