import AppKit

extension Artwork {
    static func compactCard(_ input: CardInput) -> Card {
        let size = CGSize(width: 138, height: 100)
        let outline = CGPath(roundedRect: CGRect(origin: .zero, size: size), cornerWidth: 7, cornerHeight: 7, transform: nil)
        let image = render(size: size, scale: input.scale) { context in
            let rect = CGRect(origin: .zero,size: size)
            input.theme.paper.setFill(); NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
            let preview = CGRect(x: 8, y: 6, width: 122, height: 66)
            if let thumb = input.thumbnail {
                let ratio = CGFloat(thumb.width)/CGFloat(thumb.height)
                let width = min(preview.width,preview.height*ratio), height = width/ratio
                let fitted = CGRect(x: preview.midX-width/2,y: preview.midY-height/2,width: width,height: height)
                NSImage(cgImage: thumb, size: .zero).draw(in: fitted, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            } else if let icon = input.icon {
                icon.draw(in: CGRect(x: 48,y: 12,width: 42,height: 42), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            } else {
                ((input.item.text ?? input.item.link ?? input.item.kind.displayName) as NSString).draw(in: preview, withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: input.theme.ink])
            }
            let style = NSMutableParagraphStyle(); style.lineBreakMode = .byTruncatingMiddle; style.alignment = .center
            (input.item.title as NSString).draw(in: CGRect(x: 6,y: 77,width: 126,height: 18), withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: input.theme.ink, .paragraphStyle: style])
            if input.availability != .available {
                ((input.availability == .missing ? "MISSING" : "OFFLINE") as NSString).draw(at: CGPoint(x: 8,y: 8), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 10), .foregroundColor: NSColor.systemRed])
            }
        }
        return Card(image: image, size: size, outline: outline)
    }
}
