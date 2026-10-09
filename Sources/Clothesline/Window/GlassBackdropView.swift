import AppKit

/// A stable frosted desktop backdrop with a separate, lightweight glass finish.
/// The frost never follows key-window or item-selection state.
final class GlassBackdropView: NSView {
    let backdrop = NSVisualEffectView()
    private let surface: NSView
    private let interactiveContent: NSView
    private let rim = CAShapeLayer()
    private let sheen = CAGradientLayer()
    private let sheenMask = CAShapeLayer()
    private static let radius: CGFloat = 22

    init(content: NSView, frame: NSRect) {
        interactiveContent = content
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: CGRect(origin: .zero,size: frame.size))
            glass.style = .clear
            glass.cornerRadius = Self.radius
            glass.contentView = content
            surface = glass
        } else { surface = content }
        #else
        surface = content
        #endif
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = Self.radius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        backdrop.material = .popover
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.isEmphasized = false
        backdrop.frame = bounds
        backdrop.autoresizingMask = [.width,.height]
        addSubview(backdrop)
        surface.frame = bounds
        surface.autoresizingMask = [.width,.height]
        content.autoresizingMask = [.width,.height]
        addSubview(surface)

        // Subtle highlights distinguish the edge without tinting or obscuring files.
        rim.fillColor = nil
        rim.lineWidth = 1
        sheen.startPoint = CGPoint(x: 0.15,y: 1)
        sheen.endPoint = CGPoint(x: 0.8,y: 0)
        sheen.mask = sheenMask
        sheenMask.fillColor = nil
        sheenMask.lineWidth = 1.4
        sheenMask.strokeColor = NSColor.white.cgColor
        for l in [rim,sheen,sheenMask] as [CALayer] {
            l.actions = ["path": NSNull(),"frame": NSNull(),"colors": NSNull(),"strokeColor": NSNull()]
        }
        layer?.addSublayer(rim)
        layer?.addSublayer(sheen)
        updateFinish()
    }
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        // Native effect surfaces can own tracking inside their content. Track the
        // outer glass region too, including while dragging into the destination.
        addTrackingArea(NSTrackingArea(rect: bounds,options: [.mouseEnteredAndExited,.mouseMoved,.activeAlways,.inVisibleRect,.enabledDuringMouseDrag],owner: interactiveContent,userInfo: nil))
    }

    override func layout() {
        super.layout()
        let rect = bounds.insetBy(dx: 0.75,dy: 0.75)
        let path = CGPath(roundedRect: rect,cornerWidth: Self.radius,cornerHeight: Self.radius,transform: nil)
        rim.frame = bounds
        rim.path = path
        sheen.frame = bounds
        sheenMask.frame = bounds
        sheenMask.path = path
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateFinish()
    }
    private func updateFinish() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua,.aqua]) == .darkAqua
        rim.strokeColor = NSColor.white.withAlphaComponent(dark ? 0.16 : 0.28).cgColor
        sheen.colors = [NSColor.white.withAlphaComponent(dark ? 0.45 : 0.65).cgColor,
                        NSColor.white.withAlphaComponent(0.03).cgColor,
                        NSColor(calibratedRed: 0.7,green: 0.82,blue: 1,alpha: 0.2).cgColor]
        sheen.locations = [0,0.5,1]
    }
}
