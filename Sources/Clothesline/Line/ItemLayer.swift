import AppKit
import ClotheslineCore

/// One hanging item: a clothespin gripping a paper card.
///
/// The layer's anchor point sits exactly where the pin meets the rope, so
/// rotating the layer swings the item around the pin like real laundry.
/// Coordinates are y-down (the host view is flipped).
final class ItemLayer: CALayer {
    let itemID: UUID
    let pinLayer = CALayer()
    let cardLayer = CALayer()
    let selectionLayer = CAShapeLayer()
    private(set) var cardSize: CGSize = .zero
    private(set) var cardOutline: CGPath = CGMutablePath()
    private var theme: Theme?

    /// Distance from the pin's top to the card's top edge.
    static var cardTop: CGFloat { Artwork.pinSize.height - Artwork.pinGrip }

    init(itemID: UUID) {
        self.itemID = itemID
        super.init()
        commonInit()
    }

    override init(layer: Any) {
        // Used by Core Animation for presentation copies.
        if let other = layer as? ItemLayer {
            itemID = other.itemID
        } else {
            itemID = UUID()
        }
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    private func commonInit() {
        masksToBounds = false
        selectionLayer.fillColor = nil
        selectionLayer.lineWidth = 2.5
        selectionLayer.lineJoin = .round
        selectionLayer.opacity = 0
        selectionLayer.shadowOpacity = 0.9
        selectionLayer.shadowRadius = 5
        selectionLayer.shadowOffset = .zero
        cardLayer.shadowOffset = CGSize(width: 0, height: 3)
        cardLayer.shadowRadius = 3.5
        cardLayer.contentsGravity = .resize
        pinLayer.contentsGravity = .resize
        pinLayer.shadowOpacity = 0.25
        pinLayer.shadowRadius = 1.2
        pinLayer.shadowOffset = CGSize(width: 0.5, height: 1.2)
        pinLayer.zPosition = 2
        selectionLayer.zPosition = 1
        addSublayer(selectionLayer)
        addSublayer(cardLayer)
        addSublayer(pinLayer)
        // No implicit animations on internal sublayers; motion is explicit.
        let none: [String: CAAction] = ["position": NSNull(), "bounds": NSNull(), "contents": NSNull(), "path": NSNull(), "hidden": NSNull(), "shadowPath": NSNull(), "frame": NSNull()]
        [pinLayer, cardLayer, selectionLayer].forEach { $0.actions = none }
        actions = ["position": NSNull(), "bounds": NSNull(), "transform": NSNull(), "anchorPoint": NSNull(), "zPosition": NSNull(), "opacity": NSNull()]
    }

    func configure(card: Artwork.Card, pin: CGImage?, theme: Theme, scale: CGFloat) {
        self.theme = theme
        cardSize = card.size
        cardOutline = card.outline
        let width = max(card.size.width, Artwork.pinSize.width)
        let height = Self.cardTop + card.size.height
        bounds = CGRect(x: 0, y: 0, width: width, height: height)
        anchorPoint = CGPoint(x: 0.5, y: Artwork.pinRopeY / height)
        contentsScale = scale

        pinLayer.frame = CGRect(x: (width - Artwork.pinSize.width) / 2, y: 0, width: Artwork.pinSize.width, height: Artwork.pinSize.height)
        pinLayer.contents = pin
        pinLayer.contentsScale = scale
        pinLayer.shadowColor = theme.shadow.cgColor

        let cardFrame = CGRect(x: (width - card.size.width) / 2, y: Self.cardTop, width: card.size.width, height: card.size.height)
        cardLayer.frame = cardFrame
        cardLayer.contents = card.image
        cardLayer.contentsScale = scale
        cardLayer.shadowPath = card.outline
        cardLayer.shadowColor = theme.shadow.cgColor
        cardLayer.shadowOpacity = theme.shadowOpacity

        var t = CGAffineTransform(translationX: cardFrame.minX, y: cardFrame.minY)
        selectionLayer.frame = bounds
        selectionLayer.path = card.outline.copy(using: &t)
        selectionLayer.strokeColor = theme.accent.cgColor
        selectionLayer.shadowColor = theme.accent.cgColor
    }

    var isSelected: Bool = false {
        didSet {
            guard isSelected != oldValue else { return }
            Motion.animate(selectionLayer, keyPath: "opacity", to: isSelected ? Float(1) : Float(0), duration: 0.16)
        }
    }

    var isHovered: Bool = false {
        didSet {
            guard isHovered != oldValue, let theme else { return }
            Motion.animate(cardLayer, keyPath: "shadowRadius", to: isHovered ? 6.0 : 3.5, duration: 0.18)
            Motion.animate(cardLayer, keyPath: "shadowOpacity", to: isHovered ? min(1, theme.shadowOpacity + 0.12) : theme.shadowOpacity, duration: 0.18)
        }
    }

    /// The card's frame in this layer's coordinates.
    var cardFrame: CGRect { cardLayer.frame }

    /// Hit test in this layer's own coordinate space (rotation is handled by
    /// converting the point into the layer first).
    func containsItemPoint(_ p: CGPoint) -> Bool {
        if pinLayer.frame.insetBy(dx: -3, dy: 0).contains(p) { return true }
        var t = CGAffineTransform(translationX: cardFrame.minX, y: cardFrame.minY)
        guard let path = cardOutline.copy(using: &t) else { return cardFrame.contains(p) }
        return path.contains(p)
    }

    /// Renders the pin and card into one image for the drag preview.
    func snapshot(scale: CGFloat) -> NSImage {
        let size = bounds.size
        let image = NSImage(size: size, flipped: true) { [weak self] _ in
            guard let self, let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let cf = self.cardFrame
            if let card = self.cardLayer.contents {
                // swiftlint:disable:next force_cast
                ctx.saveGState()
                ctx.translateBy(x: cf.minX, y: cf.maxY)
                ctx.scaleBy(x: 1, y: -1)
                ctx.draw(card as! CGImage, in: CGRect(origin: .zero, size: cf.size))
                ctx.restoreGState()
            }
            if let pin = self.pinLayer.contents {
                let pf = self.pinLayer.frame
                ctx.saveGState()
                ctx.translateBy(x: pf.minX, y: pf.maxY)
                ctx.scaleBy(x: 1, y: -1)
                ctx.draw(pin as! CGImage, in: CGRect(origin: .zero, size: pf.size))
                ctx.restoreGState()
            }
            return true
        }
        return image
    }
}
