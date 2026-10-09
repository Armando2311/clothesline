import AppKit
import ClotheslineCore

/// Renders the real `LineView` with sample items into a PNG, without showing
/// any window. Used by CI (`Clothesline --render-preview out.png`) to check the
/// illustration on every build, and handy for design iteration.
@MainActor
enum PreviewRenderer {
    static func run(output: URL) {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("clothesline-preview-\(UUID().uuidString)", isDirectory: true)
        let samples = root.appendingPathComponent("Samples", isDirectory: true)
        try? fm.createDirectory(at: samples, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let savedSettings = UserDefaults.standard.data(forKey: "settings.v1")
        defer {
            if let savedSettings { UserDefaults.standard.set(savedSettings, forKey: "settings.v1") } else { UserDefaults.standard.removeObject(forKey: "settings.v1") }
        }

        let model = AppModel(store: BoardStore(directory: root.appendingPathComponent("State", isDirectory: true)))
        var settings = AppSettings()
        settings.gentleBreeze = false
        settings.ambientEffects = false
        model.settings = settings

        // Sample content.
        let shots = [
            makeScene(samples, "Screenshot 2026-10-08 at 09.41.12.png", size: CGSize(width: 1440, height: 900), hue: 0.58),
            makeScene(samples, "Screenshot 2026-10-08 at 09.42.30.png", size: CGSize(width: 900, height: 1200), hue: 0.92),
            makeScene(samples, "Screenshot 2026-10-08 at 09.44.05.png", size: CGSize(width: 1600, height: 700), hue: 0.12),
        ]
        model.hang(fileURLs: shots, source: .screenshot)
        model.hang(fileURLs: [makePDF(samples)], source: .drop)
        let folder = samples.appendingPathComponent("Project Assets", isDirectory: true)
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        model.hang(fileURLs: [folder], source: .drop)
        model.hang(text: "Remember: ask Aoi about the train times for Saturday ☀︎", source: .clipboard)
        model.hang(link: "https://developer.apple.com/documentation/appkit/nspanel", source: .drop)
        let notes = samples.appendingPathComponent("Meeting notes.md")
        try? "# Notes".write(to: notes, atomically: true, encoding: .utf8)
        model.hang(fileURLs: [notes], source: .drop)
        model.hang(fileURLs: [makeScene(samples, "sunset.jpg", size: CGSize(width: 1000, height: 1000), hue: 0.05)], source: .drop)
        if let pinned = model.activeItems.first(where: { $0.kind == .folder }) { model.setPinned([pinned.id], true) }
        if let missing = model.activeItems.last { try? fm.removeItem(at: missing.file!.url) }

        let size = CGSize(width: 1512 - 16, height: PanelController.panelHeight)
        let view = LineView(model: model)
        view.frame = NSRect(origin: .zero, size: size)
        model.revalidate()

        // Let thumbnails and file checks complete.
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }

        // Show the selection outline on two prints.
        view.select(Set(model.activeItems.prefix(2).map(\.id)))
        var rows: [CGImage] = []
        // First reveal stays quiet; subsequent rows include the hover toolbar.
        view.willAppear(animated: false)
        view.configure(notchCenterX: nil)
        if let img = snapshot(view,size: size) { rows.append(img) }
        view.setToolbarVisible(true,animated: false)
        for theme in ThemeChoice.allCases.filter({ $0 != .automatic }) {
            model.settings.theme = theme
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            view.configure(notchCenterX: Double(size.width / 2))
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            if let img = snapshot(view, size: size) { rows.append(img) }
        }
        // Both compact themes exercise aspect fitting, Retina drawing and the native toolbar.
        model.settings.appearanceStyle = .compact
        let compactSize = CGSize(width: size.width,height: AppearanceStyle.compact.panelHeight)
        view.frame = NSRect(origin: .zero,size: compactSize)
        for choice in [ThemeChoice.summerAfternoon,.midnight] {
            model.settings.theme = choice
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            view.configure(notchCenterX: nil)
            if let img = snapshot(view,size: compactSize) { rows.append(img) }
        }
        model.settings.appearanceStyle = .illustrated
        view.frame = NSRect(origin: .zero,size: size)
        // Empty line on a display without a notch.
        model.settings.theme = .summerAfternoon
        model.remove(Set(model.activeItems.map(\.id)), undoable: false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        view.configure(notchCenterX: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        if let img = snapshot(view, size: size) { rows.append(img) }

        writeStack(rows, to: output)
        print("Preview written to \(output.path)")
    }

    private static func snapshot(_ view: LineView, size: CGSize) -> CGImage? {
        guard let layer = view.layer else { return nil }
        let scale: CGFloat = 2
        guard let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        // A neutral "desktop" behind the panel so transparency and shadows read.
        ctx.setFillColor(NSColor(hex: 0xD9DCE3).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale))
        ctx.scaleBy(x: scale, y: scale)
        if layer.isGeometryFlipped {
            ctx.translateBy(x: 0, y: size.height)
            ctx.scaleBy(x: 1, y: -1)
        }
        layer.layoutIfNeeded()
        layer.render(in: ctx)
        // NSHostingView's native control surfaces don't appear in CALayer.render.
        // Draw its AppKit cache separately over the illustrated snapshot.
        for control in view.subviews where !control.isHidden {
            if let rep = control.bitmapImageRepForCachingDisplay(in: control.bounds) {
                control.cacheDisplay(in: control.bounds,to: rep)
                if let image = rep.cgImage {
                    ctx.saveGState()
                    ctx.translateBy(x: control.frame.minX,y: control.frame.maxY)
                    ctx.scaleBy(x: 1,y: -1)
                    ctx.draw(image,in: CGRect(origin: .zero,size: control.frame.size))
                    ctx.restoreGState()
                }
            }
        }
        return ctx.makeImage()
    }

    private static func writeStack(_ rows: [CGImage], to url: URL) {
        guard let first = rows.first else { return }
        let w = first.width, h = rows.reduce(0) { $0 + $1.height }
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return }
        var y = h
        for row in rows {
            y -= row.height
            ctx.draw(row, in: CGRect(x: 0, y: y, width: row.width, height: row.height))
        }
        guard let image = ctx.makeImage() else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    // MARK: - Sample files

    /// A simple illustrated scene standing in for a screenshot.
    private static func makeScene(_ dir: URL, _ name: String, size: CGSize, hue: CGFloat) -> URL {
        let url = dir.appendingPathComponent(name)
        let image = NSImage(size: size, flipped: false) { rect in
            NSGradient(colors: [NSColor(hue: hue, saturation: 0.45, brightness: 0.95, alpha: 1),
                                NSColor(hue: hue + 0.08, saturation: 0.3, brightness: 1, alpha: 1)])?.draw(in: rect, angle: 90)
            // A window-like card.
            let card = NSRect(x: rect.width * 0.12, y: rect.height * 0.15, width: rect.width * 0.76, height: rect.height * 0.6)
            NSColor.white.withAlphaComponent(0.9).setFill()
            NSBezierPath(roundedRect: card, xRadius: 18, yRadius: 18).fill()
            NSColor(hue: hue, saturation: 0.6, brightness: 0.7, alpha: 1).setFill()
            for i in 0..<5 {
                NSBezierPath(roundedRect: NSRect(x: card.minX + 40, y: card.maxY - 70 - CGFloat(i) * 50, width: card.width * (i % 2 == 0 ? 0.7 : 0.5) - 40, height: 22), xRadius: 8, yRadius: 8).fill()
            }
            return true
        }
        if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
            let type: NSBitmapImageRep.FileType = name.hasSuffix(".jpg") ? .jpeg : .png
            try? rep.representation(using: type, properties: [:])?.write(to: url)
        }
        return url
    }

    private static func makePDF(_ dir: URL) -> URL {
        let url = dir.appendingPathComponent("Design Brief.pdf")
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return url }
        ctx.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSColor(hex: 0xFF8FA3).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 742, width: 595, height: 100)).fill()
        ("Design Brief" as NSString).draw(at: NSPoint(x: 48, y: 770), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 40), .foregroundColor: NSColor.white])
        NSColor(white: 0.75, alpha: 1).setFill()
        for i in 0..<18 {
            NSBezierPath(rect: NSRect(x: 48, y: 690 - CGFloat(i) * 32, width: i % 3 == 2 ? 300 : 499, height: 12)).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        ctx.endPDFPage()
        ctx.closePDF()
        return url
    }
}
