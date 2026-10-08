import AppKit
import QuickLookThumbnailing

/// Generates thumbnails with Quick Look (the same engine Finder uses), so every
/// file type macOS can preview gets a real thumbnail. Results are cached in
/// memory, keyed by path, modification date and size, and the cache is bounded.
@MainActor
final class ThumbnailCache {
    private final class Box {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    private let cache: NSCache<NSString, Box> = {
        let c = NSCache<NSString, Box>()
        c.countLimit = 200
        c.totalCostLimit = 64 * 1024 * 1024
        return c
    }()
    private var pending: [NSString: [(CGImage?) -> Void]] = [:]

    private func key(for url: URL, size: CGSize, scale: CGFloat) -> NSString {
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
        return "\(url.path)|\(mtime)|\(Int(size.width))x\(Int(size.height))@\(scale)" as NSString
    }

    func cached(for url: URL, size: CGSize, scale: CGFloat) -> CGImage? {
        cache.object(forKey: key(for: url, size: size, scale: scale))?.image
    }

    func thumbnail(for url: URL, size: CGSize, scale: CGFloat, completion: @escaping (CGImage?) -> Void) {
        let k = key(for: url, size: size, scale: scale)
        if let hit = cache.object(forKey: k) { completion(hit.image); return }
        if pending[k] != nil { pending[k]?.append(completion); return }
        pending[k] = [completion]

        let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: scale, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] rep, _ in
            let image = rep?.cgImage
            Task { @MainActor in
                guard let self else { return }
                if let image {
                    self.cache.setObject(Box(image), forKey: k, cost: image.bytesPerRow * image.height)
                }
                let callbacks = self.pending.removeValue(forKey: k) ?? []
                callbacks.forEach { $0(image) }
            }
        }
    }

    func removeAll() { cache.removeAllObjects() }
}
