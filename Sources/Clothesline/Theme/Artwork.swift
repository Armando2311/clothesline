import AppKit
import ClotheslineCore

/// Programmatic illustrations: clothespins, paper items, hooks and the sky's
/// atmosphere. Everything is drawn with Core Graphics into cached bitmaps at
/// the display's scale, then handed to Core Animation as layer contents, so the
/// line never redraws per frame and contains no third-party artwork.
enum Artwork {
    // MARK: - Bitmap helper

    /// Renders into a bitmap using a top-left origin (y grows downwards), with an
    /// NSGraphicsContext installed so AppKit text and image drawing work.
    static func render(size: CGSize, scale: CGFloat, _ draw: (CGContext) -> Void) -> CGImage? {
        let w = max(1, Int(ceil(size.width * scale)))
        let h = max(1, Int(ceil(size.height * scale)))
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .high
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        draw(ctx)
        NSGraphicsContext.current = previous
        return ctx.makeImage()
    }

    // MARK: - Clothespin

    static let pinSize = CGSize(width: 14, height: 38)
    /// Where the rope passes through the pin, measured from the pin's top.
    static let pinRopeY: CGFloat = 10
    /// How far the pin's jaws overlap the top edge of the item.
    static let pinGrip: CGFloat = 13

    static func clothespin(theme: Theme, painted: Bool, scale: CGFloat) -> CGImage? {
        render(size: pinSize, scale: scale) { ctx in
            let s = pinSize
            let light = painted ? theme.paintedPin.blended(withFraction: 0.25, of: .white) ?? theme.paintedPin : theme.woodLight
            let dark = painted ? theme.paintedPin.blended(withFraction: 0.25, of: .black) ?? theme.paintedPin : theme.woodDark

            // Body: two wooden prongs seen from the front, slightly tapered at the top.
            let body = CGMutablePath()
            body.move(to: CGPoint(x: 2.2, y: 1.2))
            body.addQuadCurve(to: CGPoint(x: 11.8, y: 1.2), control: CGPoint(x: 7, y: -0.6))
            body.addLine(to: CGPoint(x: 12.9, y: s.height - 3))
            body.addQuadCurve(to: CGPoint(x: 1.1, y: s.height - 3), control: CGPoint(x: 7, y: s.height + 0.8))
            body.closeSubpath()

            ctx.saveGState()
            ctx.addPath(body)
            ctx.clip()
            let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [
                dark.cgColor, light.cgColor, light.cgColor, dark.cgColor,
            ] as CFArray, locations: [0, 0.32, 0.55, 1])!
            ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: 0), end: CGPoint(x: s.width, y: 0), options: [])

            // Wood grain: a few fine, slightly wavy strokes.
            ctx.setLineWidth(0.35)
            ctx.setStrokeColor(dark.withAlphaComponent(0.35).cgColor)
            for gx in [3.4, 4.6, 9.2, 10.6] as [CGFloat] {
                ctx.move(to: CGPoint(x: gx, y: 2))
                ctx.addCurve(to: CGPoint(x: gx + 0.4, y: s.height - 3),
                             control1: CGPoint(x: gx - 0.6, y: 12), control2: CGPoint(x: gx + 0.9, y: 26))
            }
            ctx.strokePath()

            // Centre seam between the two prongs, with a tiny highlight.
            ctx.setLineWidth(0.8)
            ctx.setStrokeColor(dark.withAlphaComponent(0.8).cgColor)
            ctx.move(to: CGPoint(x: 7, y: 1.5)); ctx.addLine(to: CGPoint(x: 7, y: s.height - 1.5))
            ctx.strokePath()
            ctx.setLineWidth(0.4)
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.35).cgColor)
            ctx.move(to: CGPoint(x: 7.6, y: 2)); ctx.addLine(to: CGPoint(x: 7.6, y: s.height - 2))
            ctx.strokePath()

            // The groove the rope sits in.
            ctx.setFillColor(dark.withAlphaComponent(0.55).cgColor)
            ctx.fillEllipse(in: CGRect(x: 5.4, y: pinRopeY - 1.6, width: 3.2, height: 3.2))
            ctx.restoreGState()

            // Steel spring wrapped around the middle.
            let springRect = CGRect(x: 0.2, y: 15.5, width: s.width - 0.4, height: 4.6)
            let springPath = CGPath(roundedRect: springRect, cornerWidth: 2.2, cornerHeight: 2.2, transform: nil)
            ctx.saveGState()
            ctx.addPath(springPath)
            ctx.clip()
            let steel = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [
                theme.spring.blended(withFraction: 0.5, of: .white)!.cgColor, theme.spring.cgColor,
                theme.spring.blended(withFraction: 0.45, of: .black)!.cgColor,
            ] as CFArray, locations: [0, 0.45, 1])!
            ctx.drawLinearGradient(steel, start: CGPoint(x: 0, y: springRect.minY), end: CGPoint(x: 0, y: springRect.maxY), options: [])
            ctx.setStrokeColor(theme.spring.blended(withFraction: 0.5, of: .black)!.withAlphaComponent(0.6).cgColor)
            ctx.setLineWidth(0.45)
            var x = springRect.minX + 1.2
            while x < springRect.maxX {
                ctx.move(to: CGPoint(x: x, y: springRect.minY)); ctx.addLine(to: CGPoint(x: x + 0.8, y: springRect.maxY))
                x += 1.5
            }
            ctx.strokePath()
            ctx.restoreGState()

            // Outline for crispness at small sizes.
            ctx.addPath(body)
            ctx.setStrokeColor(dark.blended(withFraction: 0.3, of: .black)!.withAlphaComponent(0.45).cgColor)
            ctx.setLineWidth(0.5)
            ctx.strokePath()
        }
    }

    // MARK: - Hooks

    static let hookSize = CGSize(width: 16, height: 18)

    /// A small screw-in brass hook the rope is tied to.
    static func hook(theme: Theme, scale: CGFloat) -> CGImage? {
        render(size: hookSize, scale: scale) { ctx in
            // Base plate.
            ctx.setFillColor(theme.hook.cgColor)
            ctx.fillEllipse(in: CGRect(x: 3, y: 0, width: 10, height: 5))
            ctx.setFillColor(theme.hook.blended(withFraction: 0.4, of: .white)!.withAlphaComponent(0.7).cgColor)
            ctx.fillEllipse(in: CGRect(x: 5, y: 0.8, width: 4, height: 2))
            // Hook loop.
            ctx.setStrokeColor(theme.hook.cgColor)
            ctx.setLineWidth(2)
            ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: 8, y: 4))
            ctx.addLine(to: CGPoint(x: 8, y: 9))
            ctx.addArc(center: CGPoint(x: 8, y: 12), radius: 3, startAngle: -.pi / 2, endAngle: .pi * 1.1, clockwise: false)
            ctx.strokePath()
            // Knot of rope around the hook.
            ctx.setFillColor(theme.rope.cgColor)
            ctx.fillEllipse(in: CGRect(x: 5.2, y: 12.4, width: 5.6, height: 4.2))
            ctx.setFillColor(theme.ropeHighlight.withAlphaComponent(0.8).cgColor)
            ctx.fillEllipse(in: CGRect(x: 6.4, y: 13, width: 2.2, height: 1.6))
        }
    }

    // MARK: - Items

    enum Availability: Equatable {
        case available
        case missing
        case offline
    }

    struct CardInput {
        var item: HangingItem
        var thumbnail: CGImage?
        var icon: NSImage?
        var availability: Availability
        var theme: Theme
        var scale: CGFloat
    }

    struct Card {
        var image: CGImage?
        var size: CGSize
        /// Outline in card coordinates (y-down), used for shadows and selection.
        var outline: CGPath
    }

    static func card(_ input: CardInput) -> Card {
        switch input.item.kind {
        case .screenshot, .image:
            return photoPrint(input)
        case .pdf:
            return paperSheet(input, foldedCorner: true)
        case .folder:
            return folder(input)
        case .text:
            return noteCard(input)
        case .link:
            return linkTag(input)
        case .file:
            return paperSheet(input, foldedCorner: false)
        }
    }

    private static func fittedSize(for image: CGImage?, maxSize: CGSize, fallback: CGSize) -> CGSize {
        guard let image, image.width > 0, image.height > 0 else { return fallback }
        let aspect = CGFloat(image.width) / CGFloat(image.height)
        var w = maxSize.width, h = w / aspect
        if h > maxSize.height { h = maxSize.height; w = h * aspect }
        // Very tall or very wide captures still get a usable print.
        w = max(w, 46); h = max(h, 36)
        return CGSize(width: round(w), height: round(h))
    }

    private static let captionFont: NSFont = NSFont(name: "Noteworthy-Light", size: 8.5)
        ?? NSFont(name: "Bradley Hand", size: 8.5) ?? .systemFont(ofSize: 8)
    private static let noteFont: NSFont = NSFont(name: "Noteworthy-Light", size: 10)
        ?? NSFont(name: "Bradley Hand", size: 10) ?? .systemFont(ofSize: 9.5)

    static func roundedFont(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        if let d = base.fontDescriptor.withDesign(.rounded), let f = NSFont(descriptor: d, size: size) { return f }
        return base
    }

    private static func drawText(_ text: String, in rect: CGRect, font: NSFont, color: NSColor, alignment: NSTextAlignment = .center, lines: Int = 2) {
        let para = NSMutableParagraphStyle()
        para.alignment = alignment
        para.lineBreakMode = lines == 1 ? .byTruncatingMiddle : .byWordWrapping
        para.lineSpacing = -1
        let attr = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: para])
        let options: NSString.DrawingOptions = [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
        attr.draw(with: rect, options: options, context: nil)
    }

    private static func drawStamp(_ availability: Availability, in size: CGSize, theme: Theme) {
        guard availability != .available else { return }
        let text = availability == .missing ? "MISSING" : "OFFLINE"
        // Fade the card, then stamp it like a rubber stamp.
        NSColor(white: 1, alpha: 0.45).setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.translateBy(x: size.width / 2, y: size.height / 2)
        ctx.rotate(by: -0.2)
        let color = NSColor(hex: 0xC2504A, alpha: 0.85)
        let font = roundedFont(9, weight: .heavy)
        let attr = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .kern: 1.2])
        let ts = attr.size()
        let box = CGRect(x: -ts.width / 2 - 5, y: -ts.height / 2 - 2, width: ts.width + 10, height: ts.height + 4)
        let path = NSBezierPath(roundedRect: box, xRadius: 3, yRadius: 3)
        path.lineWidth = 1.2
        color.setStroke()
        path.stroke()
        attr.draw(at: CGPoint(x: -ts.width / 2, y: -ts.height / 2))
        ctx.restoreGState()
    }

    /// Screenshots and images: a small photographic print with a white border.
    private static func photoPrint(_ input: CardInput) -> Card {
        let theme = input.theme
        let imageSize = fittedSize(for: input.thumbnail, maxSize: CGSize(width: 104, height: 82), fallback: CGSize(width: 92, height: 68))
        let side: CGFloat = 5, top: CGFloat = 5, bottom: CGFloat = 17
        let size = CGSize(width: imageSize.width + side * 2, height: imageSize.height + top + bottom)
        let outline = CGPath(roundedRect: CGRect(origin: .zero, size: size), cornerWidth: 1.5, cornerHeight: 1.5, transform: nil)
        let image = render(size: size, scale: input.scale) { ctx in
            // Paper with a faint warm gradient.
            ctx.addPath(outline); ctx.clip()
            let paper = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [
                theme.paper.cgColor, theme.paper.blended(withFraction: 0.06, of: theme.paperEdge)!.cgColor,
            ] as CFArray, locations: [0, 1])!
            ctx.drawLinearGradient(paper, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])

            let imageRect = CGRect(x: side, y: top, width: imageSize.width, height: imageSize.height)
            if let thumb = input.thumbnail {
                NSGraphicsContext.current?.imageInterpolation = .high
                let nsImage = NSImage(cgImage: thumb, size: imageRect.size)
                nsImage.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            } else {
                // Placeholder while the thumbnail loads: a soft sky-tinted square.
                ctx.setFillColor(theme.skyMiddle.withAlphaComponent(0.35).cgColor)
                ctx.fill(imageRect)
            }
            // Gloss: a gentle diagonal sheen like light on photo paper.
            ctx.saveGState()
            ctx.clip(to: imageRect)
            let gloss = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [
                NSColor.white.withAlphaComponent(0.18).cgColor, NSColor.white.withAlphaComponent(0).cgColor,
            ] as CFArray, locations: [0, 0.55])!
            ctx.drawLinearGradient(gloss, start: imageRect.origin, end: CGPoint(x: imageRect.maxX, y: imageRect.maxY), options: [])
            ctx.restoreGState()
            ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.08).cgColor)
            ctx.setLineWidth(0.5)
            ctx.stroke(imageRect.insetBy(dx: 0.25, dy: 0.25))

            // Play badge for screen recordings.
            if let ext = input.item.file?.url.pathExtension.lowercased(), ["mov", "mp4"].contains(ext) {
                let c = CGPoint(x: imageRect.midX, y: imageRect.midY)
                ctx.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
                ctx.fillEllipse(in: CGRect(x: c.x - 11, y: c.y - 11, width: 22, height: 22))
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.move(to: CGPoint(x: c.x - 3.5, y: c.y - 6)); ctx.addLine(to: CGPoint(x: c.x + 6, y: c.y)); ctx.addLine(to: CGPoint(x: c.x - 3.5, y: c.y + 6))
                ctx.fillPath()
            }

            // Handwritten caption on the bottom border.
            let caption: String
            if input.item.kind == .screenshot {
                let f = DateFormatter()
                f.dateStyle = Calendar.current.isDateInToday(input.item.dateAdded) ? .none : .short
                f.timeStyle = .short
                caption = f.string(from: input.item.dateAdded)
            } else {
                caption = input.item.title
            }
            drawText(caption, in: CGRect(x: 4, y: size.height - bottom + 2.5, width: size.width - 8, height: bottom - 3),
                     font: captionFont, color: theme.inkSoft, lines: 1)
            drawStamp(input.availability, in: size, theme: theme)
        }
        return Card(image: image, size: size, outline: outline)
    }

    /// PDFs and generic files: a sheet of paper, optionally with a folded corner.
    private static func paperSheet(_ input: CardInput, foldedCorner: Bool) -> Card {
        let theme = input.theme
        let size = CGSize(width: 80, height: 104)
        let fold: CGFloat = foldedCorner ? 13 : 0
        let outline = CGMutablePath()
        outline.move(to: .zero)
        outline.addLine(to: CGPoint(x: size.width - fold, y: 0))
        outline.addLine(to: CGPoint(x: size.width, y: fold))
        outline.addLine(to: CGPoint(x: size.width, y: size.height))
        outline.addLine(to: CGPoint(x: 0, y: size.height))
        outline.closeSubpath()

        let image = render(size: size, scale: input.scale) { ctx in
            ctx.saveGState()
            ctx.addPath(outline); ctx.clip()
            ctx.setFillColor(theme.paper.cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))

            let labelHeight: CGFloat = 26
            if foldedCorner, let thumb = input.thumbnail {
                // A PDF shows its first page.
                let area = CGRect(x: 0, y: 0, width: size.width, height: size.height - labelHeight)
                let fitted = fittedSize(for: thumb, maxSize: area.size, fallback: area.size)
                let r = CGRect(x: (size.width - fitted.width) / 2, y: 0, width: fitted.width, height: fitted.height)
                NSImage(cgImage: thumb, size: r.size).draw(in: r, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            } else if let icon = input.icon {
                icon.draw(in: CGRect(x: (size.width - 46) / 2, y: 16, width: 46, height: 46), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            } else {
                // Faux text lines.
                ctx.setFillColor(theme.inkSoft.withAlphaComponent(0.25).cgColor)
                var y: CGFloat = 14
                while y < size.height - labelHeight - 8 {
                    let w = (size.width - 20) * (y.truncatingRemainder(dividingBy: 3) < 1 ? 0.7 : 1)
                    ctx.fill(CGRect(x: 10, y: y, width: w, height: 2))
                    y += 6
                }
            }
            // Label band.
            ctx.setFillColor(theme.paper.withAlphaComponent(0.94).cgColor)
            ctx.fill(CGRect(x: 0, y: size.height - labelHeight, width: size.width, height: labelHeight))
            ctx.setFillColor(theme.paperEdge.cgColor)
            ctx.fill(CGRect(x: 6, y: size.height - labelHeight, width: size.width - 12, height: 0.5))
            drawText(input.item.title, in: CGRect(x: 5, y: size.height - labelHeight + 3, width: size.width - 10, height: labelHeight - 4),
                     font: roundedFont(8, weight: .medium), color: theme.ink)

            if foldedCorner {
                // Small type ribbon.
                let tag = CGRect(x: 0, y: 7, width: 22, height: 10)
                ctx.setFillColor(NSColor(hex: 0xD9534F, alpha: 0.9).cgColor)
                ctx.fill(tag)
                drawText("PDF", in: tag.offsetBy(dx: 0, dy: 0.5), font: roundedFont(6.5, weight: .bold), color: .white, lines: 1)
            }
            drawStamp(input.availability, in: size, theme: theme)
            ctx.restoreGState()

            if foldedCorner {
                // The folded-over corner with its own little shadow.
                let flap = CGMutablePath()
                flap.move(to: CGPoint(x: size.width - fold, y: 0))
                flap.addLine(to: CGPoint(x: size.width - fold, y: fold))
                flap.addLine(to: CGPoint(x: size.width, y: fold))
                flap.closeSubpath()
                ctx.saveGState()
                ctx.setShadow(offset: CGSize(width: -1, height: 1), blur: 2, color: NSColor.black.withAlphaComponent(0.18).cgColor)
                ctx.addPath(flap)
                ctx.setFillColor(theme.paperEdge.blended(withFraction: 0.3, of: theme.paper)!.cgColor)
                ctx.fillPath()
                ctx.restoreGState()
            }
            ctx.addPath(outline)
            ctx.setStrokeColor(theme.paperEdge.cgColor)
            ctx.setLineWidth(0.6)
            ctx.strokePath()
        }
        return Card(image: image, size: size, outline: outline)
    }

    /// Folders: a kraft-paper folder with a tab and a handwritten label.
    private static func folder(_ input: CardInput) -> Card {
        let theme = input.theme
        let size = CGSize(width: 104, height: 80)
        let kraft = theme.isDark ? NSColor(hex: 0xC9A66B) : NSColor(hex: 0xEBCB8B)
        let tabW: CGFloat = 38, tabH: CGFloat = 9
        let back = CGMutablePath()
        back.move(to: CGPoint(x: 0, y: tabH + 3))
        back.addQuadCurve(to: CGPoint(x: 3, y: tabH), control: CGPoint(x: 0, y: tabH))
        back.addLine(to: CGPoint(x: 8, y: tabH))
        back.addLine(to: CGPoint(x: 12, y: 0))
        back.addLine(to: CGPoint(x: 12 + tabW, y: 0))
        back.addLine(to: CGPoint(x: 16 + tabW, y: tabH))
        back.addLine(to: CGPoint(x: size.width - 3, y: tabH))
        back.addQuadCurve(to: CGPoint(x: size.width, y: tabH + 3), control: CGPoint(x: size.width, y: tabH))
        back.addLine(to: CGPoint(x: size.width, y: size.height))
        back.addLine(to: CGPoint(x: 0, y: size.height))
        back.closeSubpath()

        let image = render(size: size, scale: input.scale) { ctx in
            ctx.addPath(back)
            ctx.setFillColor(kraft.blended(withFraction: 0.18, of: .black)!.cgColor)
            ctx.fillPath()
            // Front flap.
            let front = CGPath(roundedRect: CGRect(x: 0, y: 20, width: size.width, height: size.height - 20), cornerWidth: 3, cornerHeight: 3, transform: nil)
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -1), blur: 2.5, color: NSColor.black.withAlphaComponent(0.2).cgColor)
            ctx.addPath(front)
            ctx.setFillColor(kraft.cgColor)
            ctx.fillPath()
            ctx.restoreGState()
            ctx.saveGState()
            ctx.addPath(front); ctx.clip()
            let sheen = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [
                NSColor.white.withAlphaComponent(0.25).cgColor, NSColor.white.withAlphaComponent(0).cgColor,
            ] as CFArray, locations: [0, 1])!
            ctx.drawLinearGradient(sheen, start: CGPoint(x: 0, y: 20), end: CGPoint(x: 0, y: size.height), options: [])
            ctx.restoreGState()

            // Paper label, slightly askew.
            ctx.saveGState()
            ctx.translateBy(x: size.width / 2, y: 50)
            ctx.rotate(by: -0.03)
            let label = CGRect(x: -40, y: -11, width: 80, height: 22)
            ctx.setFillColor(theme.paper.cgColor)
            ctx.fill(label)
            ctx.setStrokeColor(theme.paperEdge.cgColor)
            ctx.setLineWidth(0.5)
            ctx.stroke(label)
            drawText(input.item.title, in: label.insetBy(dx: 3, dy: 3), font: captionFont.withSize(9.5), color: theme.ink, lines: 1)
            ctx.restoreGState()
            drawStamp(input.availability, in: size, theme: theme)
        }
        return Card(image: image, size: size, outline: back)
    }

    /// Text snippets: a tinted note card with ruled lines and handwriting.
    private static func noteCard(_ input: CardInput) -> Card {
        let theme = input.theme
        let size = CGSize(width: 94, height: 92)
        let tintIndex = Int((input.item.jitter(7) + 1) / 2 * Double(theme.noteTints.count - 1) + 0.5)
        let tint = theme.noteTints[max(0, min(theme.noteTints.count - 1, tintIndex))]
        // Deckled bottom edge, like torn washi paper.
        let outline = CGMutablePath()
        outline.move(to: .zero)
        outline.addLine(to: CGPoint(x: size.width, y: 0))
        outline.addLine(to: CGPoint(x: size.width, y: size.height - 3))
        var x = size.width
        var up = true
        while x > 0 {
            x -= 4
            outline.addLine(to: CGPoint(x: max(0, x), y: size.height - (up ? 0 : 3)))
            up.toggle()
        }
        outline.closeSubpath()

        let image = render(size: size, scale: input.scale) { ctx in
            ctx.addPath(outline); ctx.clip()
            ctx.setFillColor(tint.cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
            // Ruled lines.
            ctx.setStrokeColor(NSColor(hex: 0x7CA3D8, alpha: 0.22).cgColor)
            ctx.setLineWidth(0.5)
            var y: CGFloat = 22
            while y < size.height - 6 {
                ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: size.width, y: y))
                y += 12.5
            }
            ctx.strokePath()
            let text = input.item.text ?? input.item.title
            drawText(text, in: CGRect(x: 7, y: 11, width: size.width - 14, height: size.height - 18),
                     font: noteFont, color: theme.ink, alignment: .left, lines: 6)
        }
        return Card(image: image, size: size, outline: outline)
    }

    /// Links: a kraft luggage tag with an eyelet.
    private static func linkTag(_ input: CardInput) -> Card {
        let theme = input.theme
        let size = CGSize(width: 100, height: 58)
        let tagColor = theme.isDark ? NSColor(hex: 0xD8C29A) : NSColor(hex: 0xF2DFB8)
        let cut: CGFloat = 14
        let outline = CGMutablePath()
        outline.move(to: CGPoint(x: cut, y: 0))
        outline.addLine(to: CGPoint(x: size.width - 4, y: 0))
        outline.addQuadCurve(to: CGPoint(x: size.width, y: 4), control: CGPoint(x: size.width, y: 0))
        outline.addLine(to: CGPoint(x: size.width, y: size.height - 4))
        outline.addQuadCurve(to: CGPoint(x: size.width - 4, y: size.height), control: CGPoint(x: size.width, y: size.height))
        outline.addLine(to: CGPoint(x: cut, y: size.height))
        outline.addLine(to: CGPoint(x: 0, y: size.height - cut))
        outline.addLine(to: CGPoint(x: 0, y: cut))
        outline.closeSubpath()

        let image = render(size: size, scale: input.scale) { ctx in
            ctx.saveGState()
            ctx.addPath(outline); ctx.clip()
            ctx.setFillColor(tagColor.cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
            // Fibres.
            ctx.setStrokeColor(NSColor(hex: 0x9C7A45, alpha: 0.12).cgColor)
            ctx.setLineWidth(0.4)
            for i in 0..<9 {
                let yy = CGFloat(i) * 6.5 + 3
                ctx.move(to: CGPoint(x: 0, y: yy)); ctx.addLine(to: CGPoint(x: size.width, y: yy + 1.5))
            }
            ctx.strokePath()
            ctx.restoreGState()

            // Eyelet with a reinforcing ring.
            let eye = CGPoint(x: 12, y: size.height / 2)
            ctx.setFillColor(NSColor(hex: 0xC9B48A).cgColor)
            ctx.fillEllipse(in: CGRect(x: eye.x - 6, y: eye.y - 6, width: 12, height: 12))
            ctx.setBlendMode(.clear)
            ctx.fillEllipse(in: CGRect(x: eye.x - 2.6, y: eye.y - 2.6, width: 5.2, height: 5.2))
            ctx.setBlendMode(.normal)

            let link = input.item.link ?? ""
            let host = URL(string: link)?.host.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 } ?? input.item.title
            if let globe = NSImage(systemSymbolName: link.hasPrefix("mailto:") ? "envelope" : "globe", accessibilityDescription: nil) {
                let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
                let tinted = globe.withSymbolConfiguration(config) ?? globe
                let r = CGRect(x: 25, y: 9, width: 12, height: 12)
                tinted.draw(in: r, from: .zero, operation: .sourceOver, fraction: 0.65, respectFlipped: true, hints: nil)
            }
            drawText(host, in: CGRect(x: 39, y: 8, width: size.width - 44, height: 14), font: roundedFont(9.5, weight: .semibold), color: theme.ink, alignment: .left, lines: 1)
            let path = URL(string: link).map { u -> String in
                let p = u.path
                return p.isEmpty || p == "/" ? link : p
            } ?? link
            drawText(path, in: CGRect(x: 25, y: 25, width: size.width - 30, height: 26), font: roundedFont(7.5), color: theme.inkSoft, alignment: .left, lines: 2)
            ctx.addPath(outline)
            ctx.setStrokeColor(NSColor(hex: 0x9C7A45, alpha: 0.4).cgColor)
            ctx.setLineWidth(0.6)
            ctx.strokePath()
        }
        return Card(image: image, size: size, outline: outline)
    }

    // MARK: - Empty-state tag

    static func hintTag(text: String, detail: String, theme: Theme, scale: CGFloat) -> (CGImage?, CGSize) {
        let size = CGSize(width: 214, height: 62)
        let image = render(size: size, scale: scale) { ctx in
            let path = CGPath(roundedRect: CGRect(origin: .zero, size: size), cornerWidth: 4, cornerHeight: 4, transform: nil)
            ctx.addPath(path)
            ctx.setFillColor(theme.paper.withAlphaComponent(0.92).cgColor)
            ctx.fillPath()
            drawText(text, in: CGRect(x: 8, y: 12, width: size.width - 16, height: 20), font: noteFont.withSize(13), color: theme.ink, lines: 1)
            drawText(detail, in: CGRect(x: 8, y: 34, width: size.width - 16, height: 22), font: roundedFont(8.5), color: theme.inkSoft, lines: 2)
        }
        return (image, size)
    }

    // MARK: - Sky atmosphere

    /// Clouds, stars, light rays and the distant horizon, drawn once per theme
    /// and size. Seeded so the sky looks the same every time it opens.
    static func atmosphere(theme: Theme, size: CGSize, scale: CGFloat) -> CGImage? {
        render(size: size, scale: scale) { (ctx: CGContext) -> Void in
            var rng = SeededRandom(seed: 0xC10_7E5 &+ UInt64(ThemeChoice.allCases.firstIndex(of: theme.id) ?? 0))
            if theme.lightRays { drawLightRays(ctx, theme: theme, size: size, rng: &rng) }
            if theme.stars { drawStars(ctx, size: size, rng: &rng) }
            drawClouds(ctx, theme: theme, size: size, rng: &rng)
            drawHorizon(ctx, theme: theme, size: size, rng: &rng)
        }
    }

    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)

    private static func gradient(_ colors: [NSColor], _ locations: [CGFloat]) -> CGGradient {
        CGGradient(colorsSpace: sRGB, colors: colors.map(\.cgColor) as CFArray, locations: locations)!
    }

    private static func drawLightRays(_ ctx: CGContext, theme: Theme, size: CGSize, rng: inout SeededRandom) {
        let origin = CGPoint(x: theme.glowPosition.x * size.width, y: theme.glowPosition.y * size.height - 40)
        let g = gradient([theme.glowColor.withAlphaComponent(0.16), theme.glowColor.withAlphaComponent(0)], [0, 1])
        let length: CGFloat = size.height * 2.2
        let lean: CGFloat = (theme.glowPosition.x - 0.5) * -0.9
        for i in 0..<5 {
            let jitter = CGFloat(rng.next(in: -0.06...0.06))
            let angle: CGFloat = CGFloat.pi / 2 + (CGFloat(i) - 2) * 0.32 + jitter + lean
            let spread = CGFloat(rng.next(in: 0.035...0.08))
            let p1 = CGPoint(x: origin.x + cos(angle - spread) * length, y: origin.y + sin(angle - spread) * length)
            let p2 = CGPoint(x: origin.x + cos(angle + spread) * length, y: origin.y + sin(angle + spread) * length)
            ctx.saveGState()
            ctx.move(to: origin)
            ctx.addLine(to: p1)
            ctx.addLine(to: p2)
            ctx.closePath()
            ctx.clip()
            ctx.drawRadialGradient(g, startCenter: origin, startRadius: 0, endCenter: origin, endRadius: length * 0.45, options: [])
            ctx.restoreGState()
        }
    }

    private static func drawStars(_ ctx: CGContext, size: CGSize, rng: inout SeededRandom) {
        let count = Int(size.width / 9)
        for _ in 0..<count {
            let x = CGFloat(rng.next(in: 0...Double(size.width)))
            let y = CGFloat(rng.next(in: 0...Double(size.height) * 0.75))
            let r = CGFloat(rng.next(in: 0.3...1.1))
            let alpha = CGFloat(rng.next(in: 0.25...0.9))
            ctx.setFillColor(NSColor.white.withAlphaComponent(alpha).cgColor)
            ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        }
        // A few brighter stars with a soft cross.
        for _ in 0..<6 {
            let x = CGFloat(rng.next(in: 0...Double(size.width)))
            let y = CGFloat(rng.next(in: 0...Double(size.height) * 0.5))
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.5).cgColor)
            ctx.setLineWidth(0.5)
            ctx.move(to: CGPoint(x: x - 4, y: y)); ctx.addLine(to: CGPoint(x: x + 4, y: y))
            ctx.move(to: CGPoint(x: x, y: y - 4)); ctx.addLine(to: CGPoint(x: x, y: y + 4))
            ctx.strokePath()
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillEllipse(in: CGRect(x: x - 1.1, y: y - 1.1, width: 2.2, height: 2.2))
        }
    }

    /// Clouds: clusters of soft radial puffs, flatter at the base.
    private static func drawClouds(_ ctx: CGContext, theme: Theme, size: CGSize, rng: inout SeededRandom) {
        let opacity = CGFloat(theme.cloudOpacity)
        let g = gradient([theme.cloudColor.withAlphaComponent(opacity),
                          theme.cloudColor.withAlphaComponent(opacity * 0.55),
                          theme.cloudColor.withAlphaComponent(0)], [0, 0.55, 1])
        let cloudCount = max(3, Int(size.width / 260))
        let band = size.width / CGFloat(cloudCount)
        for i in 0..<cloudCount {
            let cx: CGFloat = (CGFloat(i) + CGFloat(rng.next(in: 0.15...0.85))) * band
            let cy: CGFloat = CGFloat(rng.next(in: 0.25...0.62)) * size.height
            let w = CGFloat(rng.next(in: 90...190))
            let puffs = Int(rng.next(in: 6...10))
            for _ in 0..<puffs {
                let px: CGFloat = cx + CGFloat(rng.next(in: -0.5...0.5)) * w
                let py: CGFloat = cy + CGFloat(rng.next(in: -14...6))
                let falloff: CGFloat = 1 - abs(px - cx) / w * 0.8
                let r: CGFloat = CGFloat(rng.next(in: 14...34)) * falloff
                let c = CGPoint(x: px, y: py)
                ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
            }
        }
    }

    private static func drawHills(_ ctx: CGContext, size: CGSize, height: CGFloat, amplitude: CGFloat, frequency: CGFloat, phase: CGFloat, color: NSColor) {
        let baseY = size.height
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: baseY))
        var x: CGFloat = 0
        while x <= size.width {
            let wave1: CGFloat = sin(x / size.width * .pi * frequency + phase) * amplitude
            let wave2: CGFloat = sin(x / 37 + phase) * 1.2
            path.addLine(to: CGPoint(x: x, y: baseY - height - wave1 - wave2))
            x += 6
        }
        path.addLine(to: CGPoint(x: size.width, y: baseY))
        path.closeSubpath()
        ctx.addPath(path)
        ctx.setFillColor(color.cgColor)
        ctx.fillPath()
    }

    /// Two layers of rolling hills, rooftops and utility poles with wires.
    private static func drawHorizon(_ ctx: CGContext, theme: Theme, size: CGSize, rng: inout SeededRandom) {
        let baseY = size.height
        let hz = theme.horizonColor
        let ha = CGFloat(theme.horizonOpacity)
        drawHills(ctx, size: size, height: 20, amplitude: 9, frequency: 3.2, phase: 0.7, color: hz.withAlphaComponent(ha * 0.55))

        // Rooftops on the far ridge.
        var rx = CGFloat(rng.next(in: 20...80))
        ctx.setFillColor(hz.withAlphaComponent(ha * 0.8).cgColor)
        while rx < size.width - 30 {
            if rng.next(in: 0...1) < 0.55 {
                let w = CGFloat(rng.next(in: 12...26))
                let h = CGFloat(rng.next(in: 6...13))
                let top: CGFloat = baseY - 14 - h
                ctx.fill(CGRect(x: rx, y: top, width: w, height: h + 14))
                ctx.move(to: CGPoint(x: rx - 2, y: top))
                ctx.addLine(to: CGPoint(x: rx + w / 2, y: top - h * 0.45))
                ctx.addLine(to: CGPoint(x: rx + w + 2, y: top))
                ctx.fillPath()
            }
            rx += CGFloat(rng.next(in: 22...70))
        }
        drawHills(ctx, size: size, height: 9, amplitude: 5, frequency: 2.1, phase: 2.1, color: hz.withAlphaComponent(ha))

        // Utility poles with sagging wires, a quiet everyday detail.
        var poleXs: [CGFloat] = []
        var px = size.width * 0.08
        while px < size.width {
            poleXs.append(px + CGFloat(rng.next(in: -20...20)))
            px += size.width * 0.29
        }
        ctx.setStrokeColor(hz.withAlphaComponent(min(1, ha * 1.3)).cgColor)
        ctx.setLineWidth(1)
        for x in poleXs {
            ctx.move(to: CGPoint(x: x, y: baseY)); ctx.addLine(to: CGPoint(x: x, y: baseY - 38))
            ctx.move(to: CGPoint(x: x - 6, y: baseY - 34)); ctx.addLine(to: CGPoint(x: x + 6, y: baseY - 34))
        }
        ctx.strokePath()
        ctx.setLineWidth(0.5)
        for (a, b) in zip(poleXs, poleXs.dropFirst()) {
            for dy in [-34.0, -31.0] as [CGFloat] {
                ctx.move(to: CGPoint(x: a + 5, y: baseY + dy))
                ctx.addQuadCurve(to: CGPoint(x: b - 5, y: baseY + dy), control: CGPoint(x: (a + b) / 2, y: baseY + dy + 9))
            }
        }
        ctx.strokePath()
    }

    // MARK: - Ambient particle sprite

    static func particle(theme: Theme, scale: CGFloat) -> CGImage? {
        switch theme.ambient {
        case .rain:
            return render(size: CGSize(width: 2, height: 16), scale: scale) { ctx in
                let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [
                    theme.ambientColor.withAlphaComponent(0).cgColor, theme.ambientColor.withAlphaComponent(0.7).cgColor,
                ] as CFArray, locations: [0, 1])!
                ctx.addPath(CGPath(roundedRect: CGRect(x: 0.4, y: 0, width: 1.2, height: 16), cornerWidth: 0.6, cornerHeight: 0.6, transform: nil))
                ctx.clip()
                ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: 16), options: [])
            }
        default:
            return render(size: CGSize(width: 12, height: 12), scale: scale) { ctx in
                let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [
                    theme.ambientColor.withAlphaComponent(0.95).cgColor, theme.ambientColor.withAlphaComponent(0).cgColor,
                ] as CFArray, locations: [0, 1])!
                ctx.drawRadialGradient(g, startCenter: CGPoint(x: 6, y: 6), startRadius: 0, endCenter: CGPoint(x: 6, y: 6), endRadius: 6, options: [])
            }
        }
    }

    // MARK: - Menu bar icon

    /// A template clothespin glyph for the menu bar.
    static func menuBarIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            let path = NSBezierPath()
            // Rope
            path.move(to: NSPoint(x: 1, y: 5)); path.curve(to: NSPoint(x: 17, y: 5), controlPoint1: NSPoint(x: 6, y: 8), controlPoint2: NSPoint(x: 12, y: 8))
            path.lineWidth = 1.2
            NSColor.black.setStroke()
            path.stroke()
            // Pin
            let pin = NSBezierPath(roundedRect: NSRect(x: 7, y: 2, width: 4, height: 13), xRadius: 1.6, yRadius: 1.6)
            NSColor.black.setFill()
            pin.fill()
            // Spring gap
            NSColor.clear.setFill()
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(rect: NSRect(x: 8.6, y: 3, width: 0.8, height: 11)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// Deterministic random numbers (SplitMix64) so procedural art is stable.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func next(in range: ClosedRange<Double>) -> Double {
        let unit = Double(next() >> 11) / Double(1 << 53)
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }
}
