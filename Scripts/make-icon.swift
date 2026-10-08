#!/usr/bin/env swift
// Draws the Clothesline app icon at every size an .iconset needs.
// Usage: swift Scripts/make-icon.swift <output.iconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func drawIcon(in ctx: CGContext, size s: CGFloat) {
    // Big Sur style: a rounded square inset from the canvas with a soft shadow.
    let inset = s * 0.09
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = rect.width * 0.225
    let shape = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: NSColor.black.withAlphaComponent(0.3).cgColor)
    ctx.addPath(shape)
    ctx.setFillColor(color(0x7FB8F5).cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let space = CGColorSpace(name: CGColorSpace.sRGB)
    // Sky (y-up: top of icon is maxY).
    let sky = CGGradient(colorsSpace: space, colors: [color(0xFDF1DF).cgColor, color(0xB9DCFB).cgColor, color(0x6FAEF2).cgColor] as CFArray, locations: [0, 0.45, 1])!
    ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.maxY), options: [])
    // Sun glow.
    let sunC = CGPoint(x: rect.minX + rect.width * 0.78, y: rect.minY + rect.height * 0.8)
    let glow = CGGradient(colorsSpace: space, colors: [color(0xFFF6D8).cgColor, color(0xFFF6D8, 0).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: sunC, startRadius: 0, endCenter: sunC, endRadius: rect.width * 0.45, options: [])
    // Clouds.
    for (cx, cy, r) in [(0.25, 0.3, 0.1), (0.34, 0.27, 0.13), (0.45, 0.3, 0.09), (0.72, 0.22, 0.08), (0.8, 0.24, 0.1)] as [(CGFloat, CGFloat, CGFloat)] {
        let c = CGPoint(x: rect.minX + rect.width * cx, y: rect.minY + rect.height * cy)
        let g = CGGradient(colorsSpace: space, colors: [NSColor.white.withAlphaComponent(0.9).cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: rect.width * r, options: [])
    }

    // Rope.
    let ropeBaseY = rect.minY + rect.height * 0.74
    let rope = CGMutablePath()
    rope.move(to: CGPoint(x: rect.minX - 4, y: ropeBaseY + rect.height * 0.04))
    rope.addQuadCurve(to: CGPoint(x: rect.maxX + 4, y: ropeBaseY + rect.height * 0.04), control: CGPoint(x: rect.midX, y: ropeBaseY - rect.height * 0.12))
    ctx.addPath(rope)
    ctx.setStrokeColor(color(0xB8916A).cgColor)
    ctx.setLineWidth(max(1, s * 0.014))
    ctx.strokePath()

    func ropeY(at x: CGFloat) -> CGFloat {
        let t = (x - (rect.minX - 4)) / (rect.width + 8)
        let y0 = ropeBaseY + rect.height * 0.04, yc = ropeBaseY - rect.height * 0.12
        return (1 - t) * (1 - t) * y0 + 2 * (1 - t) * t * yc + t * t * y0
    }

    // A photo print and a note card hanging from wooden pins.
    func hang(x: CGFloat, w: CGFloat, h: CGFloat, angle: CGFloat, draw: (CGRect) -> Void) {
        let top = ropeY(at: x)
        ctx.saveGState()
        ctx.translateBy(x: x, y: top)
        ctx.rotate(by: angle)
        let card = CGRect(x: -w / 2, y: -h - s * 0.03, width: w, height: h)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.02, color: color(0x2B3F66, 0.35).cgColor)
        draw(card)
        ctx.restoreGState()
        // Clothespin.
        let pw = s * 0.045, ph = s * 0.13
        let pin = CGRect(x: -pw / 2, y: -ph + s * 0.035, width: pw, height: ph)
        let wood = CGGradient(colorsSpace: space, colors: [color(0xB8865A).cgColor, color(0xEAC79A).cgColor, color(0xB8865A).cgColor] as CFArray, locations: [0, 0.45, 1])!
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: pin, cornerWidth: pw * 0.35, cornerHeight: pw * 0.35, transform: nil))
        ctx.clip()
        ctx.drawLinearGradient(wood, start: CGPoint(x: pin.minX, y: 0), end: CGPoint(x: pin.maxX, y: 0), options: [])
        ctx.setFillColor(color(0x8C949C).cgColor)
        ctx.fill(CGRect(x: pin.minX, y: pin.midY - ph * 0.06, width: pw, height: ph * 0.12))
        ctx.setStrokeColor(color(0x8E6A48, 0.8).cgColor)
        ctx.setLineWidth(max(0.5, s * 0.003))
        ctx.move(to: CGPoint(x: 0, y: pin.minY)); ctx.addLine(to: CGPoint(x: 0, y: pin.maxY))
        ctx.strokePath()
        ctx.restoreGState()
        ctx.restoreGState()
    }

    hang(x: rect.minX + rect.width * 0.33, w: rect.width * 0.34, h: rect.width * 0.38, angle: 0.06) { card in
        ctx.setFillColor(color(0xFFFDF8).cgColor)
        ctx.fill(card)
        let img = CGRect(x: card.minX + card.width * 0.08, y: card.minY + card.height * 0.2, width: card.width * 0.84, height: card.height * 0.72)
        let g = CGGradient(colorsSpace: space, colors: [color(0xFFB38A).cgColor, color(0xFF8FA3).cgColor, color(0x9DB8FF).cgColor] as CFArray, locations: [0, 0.5, 1])!
        ctx.saveGState()
        ctx.clip(to: img)
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: img.minY), end: CGPoint(x: 0, y: img.maxY), options: [])
        // Little hills inside the photo.
        ctx.setFillColor(color(0x5E7FB8, 0.6).cgColor)
        ctx.move(to: CGPoint(x: img.minX, y: img.minY))
        ctx.addCurve(to: CGPoint(x: img.maxX, y: img.minY + img.height * 0.25), control1: CGPoint(x: img.midX - img.width * 0.2, y: img.minY + img.height * 0.5), control2: CGPoint(x: img.midX, y: img.minY))
        ctx.addLine(to: CGPoint(x: img.maxX, y: img.minY)); ctx.closePath(); ctx.fillPath()
        ctx.restoreGState()
    }
    hang(x: rect.minX + rect.width * 0.7, w: rect.width * 0.28, h: rect.width * 0.27, angle: -0.08) { card in
        ctx.setFillColor(color(0xFFF6C9).cgColor)
        ctx.fill(card)
        ctx.setStrokeColor(color(0x7CA3D8, 0.4).cgColor)
        ctx.setLineWidth(max(0.5, s * 0.004))
        for i in 1..<4 {
            let y = card.maxY - card.height * CGFloat(i) * 0.24
            ctx.move(to: CGPoint(x: card.minX + card.width * 0.12, y: y)); ctx.addLine(to: CGPoint(x: card.maxX - card.width * 0.12, y: y))
        }
        ctx.strokePath()
    }
    ctx.restoreGState()
}

let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in sizes {
    guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
    drawIcon(in: ctx, size: CGFloat(px))
    guard let image = ctx.makeImage() else { continue }
    let rep = NSBitmapImageRep(cgImage: image)
    try rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("\(name).png"))
}
print("Icon set written to \(out.path)")
