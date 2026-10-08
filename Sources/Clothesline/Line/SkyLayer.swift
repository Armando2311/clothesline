import AppKit

/// The illustrated sky behind the line: a drawer of sky hanging from the top of
/// the display, with a soft sun or moon glow, clouds, distant rooftops and an
/// optional, very sparse ambient particle effect.
///
/// Everything except the particles is static bitmap/gradient content, so an
/// open line costs nothing per frame. Particles run entirely in the render
/// server and are stopped whenever the line is hidden or Reduce Motion is on.
final class SkyLayer: CALayer {
    static let cornerRadius: CGFloat = 22

    private let shadowLayer = CALayer()
    private let content = CALayer()
    private let gradient = CAGradientLayer()
    private let glow = CAGradientLayer()
    private let atmosphere = CALayer()
    private let rim = CAGradientLayer()
    private let emitter = CAEmitterLayer()
    private var configuredKey: String?

    override init() {
        super.init()
        let none: [String: CAAction] = ["position": NSNull(), "bounds": NSNull(), "contents": NSNull(), "path": NSNull(), "colors": NSNull(), "frame": NSNull(), "shadowPath": NSNull()]
        for l in [shadowLayer, content, gradient, glow, atmosphere, rim, emitter] as [CALayer] { l.actions = none }
        actions = none
        addSublayer(shadowLayer)
        addSublayer(content)
        content.addSublayer(gradient)
        content.addSublayer(glow)
        content.addSublayer(atmosphere)
        content.addSublayer(emitter)
        content.addSublayer(rim)
        content.masksToBounds = true
        glow.type = .radial
        atmosphere.contentsGravity = .resize
        shadowLayer.shadowOpacity = 0.28
        shadowLayer.shadowRadius = 16
        shadowLayer.shadowOffset = CGSize(width: 0, height: 6)
        emitter.renderMode = .additive
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError("not supported") }

    /// The drawer shape: square top (flush with the menu bar), rounded bottom.
    static func drawerPath(_ rect: CGRect) -> CGPath {
        let r = min(cornerRadius, rect.height / 2, rect.width / 2)
        let p = CGMutablePath()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }

    func configure(theme: Theme, skyRect: CGRect, scale: CGFloat) {
        let key = "\(theme.id)-\(Int(skyRect.width))x\(Int(skyRect.height))@\(scale)-\(Motion.reduceTransparency)"
        frame = skyRect
        let local = CGRect(origin: .zero, size: skyRect.size)
        let shape = Self.drawerPath(local)
        shadowLayer.frame = local
        shadowLayer.shadowPath = shape
        shadowLayer.shadowColor = theme.shadow.cgColor
        content.frame = local
        let mask = CAShapeLayer()
        mask.path = shape
        content.mask = mask
        guard key != configuredKey else { return }
        configuredKey = key
        contentsScale = scale

        gradient.frame = local
        gradient.colors = [theme.skyTop.cgColor, theme.skyMiddle.cgColor, theme.skyBottom.cgColor]
        gradient.locations = [0, 0.55, 1]
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)

        // Sun or moon glow as a large radial gradient.
        let radius = max(local.width, local.height) * theme.glowRadius
        let center = CGPoint(x: theme.glowPosition.x * local.width, y: theme.glowPosition.y * local.height)
        glow.frame = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        glow.colors = [theme.glowColor.withAlphaComponent(0.85).cgColor, theme.glowColor.withAlphaComponent(0.25).cgColor, theme.glowColor.withAlphaComponent(0).cgColor]
        glow.locations = [0, 0.18, 1]
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 1, y: 1)

        atmosphere.frame = local
        atmosphere.contentsScale = scale
        atmosphere.contents = Artwork.atmosphere(theme: theme, size: local.size, scale: scale)

        // A thin highlight along the bottom rim catches the light.
        rim.frame = CGRect(x: 0, y: local.height - 2, width: local.width, height: 2)
        rim.colors = [NSColor.white.withAlphaComponent(0).cgColor, NSColor.white.withAlphaComponent(theme.isDark ? 0.12 : 0.35).cgColor]

        configureEmitter(theme: theme, size: local.size, scale: scale)
    }

    private func configureEmitter(theme: Theme, size: CGSize, scale: CGFloat) {
        emitter.frame = CGRect(origin: .zero, size: size)
        let cell = CAEmitterCell()
        cell.contents = Artwork.particle(theme: theme, scale: scale)
        cell.name = "ambient"
        switch theme.ambient {
        case .none:
            emitter.emitterCells = nil
            return
        case .rain:
            emitter.emitterShape = .line
            emitter.emitterPosition = CGPoint(x: size.width / 2, y: -10)
            emitter.emitterSize = CGSize(width: size.width * 1.2, height: 1)
            cell.birthRate = Float(size.width / 25)
            cell.lifetime = 0.9
            cell.velocity = 420
            cell.velocityRange = 60
            cell.emissionLongitude = .pi / 2 + 0.18
            cell.scale = 0.6
            cell.scaleRange = 0.3
            cell.alphaRange = 0.3
            cell.alphaSpeed = -0.3
            cell.color = NSColor.white.withAlphaComponent(0.35).cgColor
        case .motes:
            emitter.emitterShape = .rectangle
            emitter.emitterPosition = CGPoint(x: size.width / 2, y: size.height / 2)
            emitter.emitterSize = size
            cell.birthRate = Float(size.width / 700)
            cell.lifetime = 10
            cell.velocity = 6
            cell.velocityRange = 4
            cell.emissionRange = .pi * 2
            cell.scale = 0.35
            cell.scaleRange = 0.2
            cell.alphaSpeed = -0.08
            cell.color = NSColor.white.withAlphaComponent(0.7).cgColor
            cell.spin = 0
        case .fireflies:
            emitter.emitterShape = .rectangle
            emitter.emitterPosition = CGPoint(x: size.width / 2, y: size.height * 0.62)
            emitter.emitterSize = CGSize(width: size.width, height: size.height * 0.5)
            cell.birthRate = Float(size.width / 900)
            cell.lifetime = 8
            cell.velocity = 5
            cell.velocityRange = 4
            cell.emissionRange = .pi * 2
            cell.scale = 0.45
            cell.scaleRange = 0.2
            cell.alphaRange = 0.4
            cell.alphaSpeed = -0.1
            cell.color = NSColor.white.withAlphaComponent(0.85).cgColor
        }
        emitter.emitterCells = [cell]
        emitter.birthRate = 0
    }

    /// Starts or stops ambient particles. Stopped means zero cost.
    func setAmbientRunning(_ running: Bool) {
        if running {
            emitter.beginTime = CACurrentMediaTime()
            emitter.birthRate = 1
            emitter.isHidden = false
        } else {
            emitter.birthRate = 0
            emitter.isHidden = true
        }
    }
}
