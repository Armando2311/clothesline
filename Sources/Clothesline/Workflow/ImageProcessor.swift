import AppKit
import ImageIO
import UniformTypeIdentifiers
import CoreText
import ClotheslineCore

enum ImageFormat: String, CaseIterable { case png, jpeg }
struct ImageMark: Equatable {
    enum Kind: String, CaseIterable { case arrow, number, redact }
    var kind: Kind
    var start: CGPoint
    var end: CGPoint
    var number: Int = 1
}
struct ImageEdits: Equatable {
    var crop = CGRect(x: 0, y: 0, width: 1, height: 1)
    var maxEdge = 1600
    var marks: [ImageMark] = []
}

enum ImageProcessor {
    static func load(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 50000, height <= 50000,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: min(12000, max(width, height)),
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw WorkflowError.unreadable(url.lastPathComponent) }
        return image
    }
    static func render(_ image: CGImage, edits: ImageEdits) throws -> CGImage {
        guard (1...12000).contains(edits.maxEdge), [edits.crop.minX, edits.crop.minY, edits.crop.width, edits.crop.height].allSatisfy({ $0.isFinite }),
              edits.crop.width > 0, edits.crop.height > 0 else { throw WorkflowError.invalidOptions }
        let unit = edits.crop.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !unit.isNull, unit.width > 0, unit.height > 0 else { throw WorkflowError.invalidOptions }
        let region = CGRect(x: unit.minX * CGFloat(image.width), y: unit.minY * CGFloat(image.height),
                            width: unit.width * CGFloat(image.width), height: unit.height * CGFloat(image.height)).integral
        guard let cropped = image.cropping(to: region) else { throw WorkflowError.invalidOptions }
        let scale = min(1, Double(edits.maxEdge) / Double(max(cropped.width, cropped.height)))
        let width = max(1, Int(Double(cropped.width) * scale)), height = max(1, Int(Double(cropped.height) * scale))
        guard let c = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw WorkflowError.invalidOptions }
        c.interpolationQuality = .high
        c.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
        c.translateBy(x: 0, y: CGFloat(height)); c.scaleBy(x: 1, y: -1)
        let thickness = max(2, CGFloat(width) / 250)
        for mark in edits.marks {
            let a = CGPoint(x: mark.start.x * CGFloat(width), y: mark.start.y * CGFloat(height))
            let b = CGPoint(x: mark.end.x * CGFloat(width), y: mark.end.y * CGFloat(height))
            guard [a.x, a.y, b.x, b.y].allSatisfy({ $0.isFinite }) else { throw WorkflowError.invalidOptions }
            switch mark.kind {
            case .redact:
                c.setFillColor(CGColor(gray: 0, alpha: 1))
                c.fill(CGRect(x: min(a.x,b.x), y: min(a.y,b.y), width: max(1,abs(a.x-b.x)), height: max(1,abs(a.y-b.y))).integral)
            case .arrow:
                c.setStrokeColor(CGColor(red: 0.95, green: 0.18, blue: 0.15, alpha: 1)); c.setLineWidth(thickness); c.setLineCap(.round)
                c.move(to: a); c.addLine(to: b); c.strokePath()
                let angle = atan2(b.y-a.y,b.x-a.x), length = thickness * 5
                for offset in [-CGFloat.pi/6, CGFloat.pi/6] {
                    c.move(to: b); c.addLine(to: CGPoint(x: b.x-length*cos(angle+offset), y: b.y-length*sin(angle+offset))); c.strokePath()
                }
            case .number:
                let radius = max(10, CGFloat(width)/60)
                c.setFillColor(CGColor(red: 0.95, green: 0.18, blue: 0.15, alpha: 1)); c.fillEllipse(in: CGRect(x: a.x-radius, y: a.y-radius, width: radius*2, height: radius*2))
                c.saveGState(); c.translateBy(x: a.x, y: a.y); c.scaleBy(x: 1,y: -1)
                let text = NSAttributedString(string: String(mark.number), attributes: [.font: NSFont.boldSystemFont(ofSize: radius*1.2), .foregroundColor: NSColor.white])
                let line = CTLineCreateWithAttributedString(text)
                c.textPosition = CGPoint(x: -CTLineGetTypographicBounds(line,nil,nil,nil)/2, y: -radius*0.42)
                CTLineDraw(line,c); c.restoreGState()
            }
        }
        guard let out = c.makeImage() else { throw WorkflowError.invalidOptions }
        return out
    }
    static func centerCrop(_ image: CGImage, ratio: Double?) -> CGRect {
        guard let ratio, ratio > 0 else { return CGRect(x: 0,y: 0,width: 1,height: 1) }
        let actual = Double(image.width)/Double(image.height)
        if actual > ratio { let w = ratio/actual; return CGRect(x: (1-w)/2,y: 0,width: w,height: 1) }
        let h = actual/ratio; return CGRect(x: 0,y: (1-h)/2,width: 1,height: h)
    }
    static func encode(_ image: CGImage, format: ImageFormat, quality: Double, maxBytes: Int? = nil) throws -> Data {
        guard quality.isFinite, (0.05...1).contains(quality), maxBytes == nil || maxBytes! > 0 else { throw WorkflowError.invalidOptions }
        func encodeAt(_ q: Double) throws -> Data {
            let data = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(data, (format == .png ? UTType.png.identifier : UTType.jpeg.identifier) as CFString, 1, nil) else { throw WorkflowError.invalidOptions }
            CGImageDestinationAddImage(dest,image,[kCGImageDestinationLossyCompressionQuality:q] as CFDictionary)
            guard CGImageDestinationFinalize(dest) else { throw WorkflowError.invalidOptions }
            return data as Data
        }
        var best = try encodeAt(quality)
        guard let maxBytes, best.count > maxBytes else { return best }
        guard format == .jpeg else { throw WorkflowError.sizeLimit }
        best = try encodeAt(0.05)
        guard best.count <= maxBytes else { throw WorkflowError.sizeLimit }
        var low = 0.05, high = quality
        for _ in 0..<9 {
            let q = (low+high)/2, data = try encodeAt(q)
            if data.count <= maxBytes { low = q; best = data } else { high = q }
        }
        return best
    }
}
