import AppKit
import ClotheslineCore

/// Creates and resolves durable file references.
///
/// Clothesline stores bookmark data for every file it references. Bookmarks
/// keep pointing at a file after it is renamed or moved on the same volume, and
/// when the app is sandboxed they also carry the security scope needed to read
/// the file after a relaunch. Resolution never mounts volumes or shows UI, so a
/// disconnected drive makes an item "offline" instead of stalling the app.
final class FileAccess: @unchecked Sendable {
    static let isSandboxed: Bool = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil

    struct Resolution {
        var url: URL?
        var availability: Artwork.Availability
        /// A refreshed reference if the bookmark was stale or the file moved.
        var updatedReference: FileReference?
    }

    private let lock = NSLock()
    private var scopedURLs: [String: URL] = [:]

    func makeReference(for url: URL, ownership: FileOwnership) -> FileReference {
        let url = url.standardizedFileURL
        var options: URL.BookmarkCreationOptions = []
        if Self.isSandboxed { options.insert(.withSecurityScope) }
        let bookmark = try? url.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil)
        return FileReference(path: url.path, bookmark: bookmark, ownership: ownership)
    }

    /// Resolves a reference. Call off the main thread: bookmark resolution can
    /// touch the disk and, for network volumes, the network.
    func resolve(_ reference: FileReference) -> Resolution {
        let fm = FileManager.default
        if let data = reference.bookmark {
            var stale = false
            var options: URL.BookmarkResolutionOptions = [.withoutUI, .withoutMounting]
            if Self.isSandboxed { options.insert(.withSecurityScope) }
            if let url = try? URL(resolvingBookmarkData: data, options: options, relativeTo: nil, bookmarkDataIsStale: &stale) {
                if Self.isSandboxed { startAccessing(url) }
                if fm.fileExists(atPath: url.path) {
                    var updated: FileReference?
                    if stale || url.standardizedFileURL.path != reference.path {
                        updated = makeReference(for: url, ownership: reference.ownership)
                    }
                    return Resolution(url: url, availability: .available, updatedReference: updated)
                }
            }
        }
        // Fall back to the last known path.
        if fm.fileExists(atPath: reference.path) {
            let url = URL(fileURLWithPath: reference.path)
            let updated = reference.bookmark == nil ? makeReference(for: url, ownership: reference.ownership) : nil
            return Resolution(url: url, availability: .available, updatedReference: updated)
        }
        return Resolution(url: nil, availability: Self.volumeIsMissing(for: reference.path) ? .offline : .missing, updatedReference: nil)
    }

    /// True if the path lives on a volume under /Volumes that is not mounted.
    static func volumeIsMissing(for path: String) -> Bool {
        let components = (path as NSString).pathComponents
        guard components.count > 2, components[1] == "Volumes" else { return false }
        let volume = "/Volumes/" + components[2]
        return !FileManager.default.fileExists(atPath: volume)
    }

    private func startAccessing(_ url: URL) {
        lock.lock(); defer { lock.unlock() }
        guard scopedURLs[url.path] == nil else { return }
        if url.startAccessingSecurityScopedResource() { scopedURLs[url.path] = url }
    }

    func stopAccessing(path: String) {
        lock.lock(); defer { lock.unlock() }
        scopedURLs.removeValue(forKey: path)?.stopAccessingSecurityScopedResource()
    }
}
