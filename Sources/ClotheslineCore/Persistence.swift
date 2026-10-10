import Foundation

/// Loads and saves the board as JSON in Application Support.
///
/// - Writes are atomic (write to temp file, then rename), so a crash mid-save
///   never leaves a truncated state file.
/// - A file that cannot be decoded is moved aside (`state.corrupt-<date>.json`)
///   instead of being overwritten, so nothing the user hung is silently lost.
public final class BoardStore {
    public let directory: URL
    public var stateURL: URL { directory.appendingPathComponent("state.json") }
    /// Where Clothesline keeps files it owns (dropped image data, file promises,
    /// clipboard images). Only files in here are ever deleted by Clothesline.
    public var ownedFilesDirectory: URL { directory.appendingPathComponent("Items", isDirectory: true) }

    private let fileManager: FileManager

    public init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    public static func defaultDirectory(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Clothesline", isDirectory: true)
    }

    public enum LoadResult: Equatable {
        case loaded(Board)
        case fresh(Board)
        /// The existing file was unreadable and has been moved to `backup`.
        case recovered(Board, backup: URL)
    }

    public func load() -> LoadResult {
        guard fileManager.fileExists(atPath: stateURL.path) else {
            return .fresh(.makeDefault())
        }
        do {
            let data = try Data(contentsOf: stateURL)
            var board = try Self.decoder.decode(Board.self, from: data)
            board.repair()
            return .loaded(board)
        } catch {
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = directory.appendingPathComponent("state.corrupt-\(stamp).json")
            try? fileManager.moveItem(at: stateURL, to: backup)
            return .recovered(.makeDefault(), backup: backup)
        }
    }

    public func save(_ board: Board) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try Self.encoder.encode(board)
        try data.write(to: stateURL, options: .atomic)
    }

    /// Creates a unique path inside the owned-files folder for a new owned copy.
    public func makeOwnedFileURL(preferredName: String) throws -> URL {
        let folder = ownedFilesDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let safe = Self.sanitizedFileName(preferredName)
        return folder.appendingPathComponent(safe)
    }

    /// Deletes an owned copy. Refuses to delete anything outside the owned folder,
    /// which guarantees a bug elsewhere can never remove a user's file.
    @discardableResult
    public func deleteOwnedFile(_ reference: FileReference) -> Bool {
        guard reference.ownership == .owned, isInsideOwnedDirectory(reference.path) else { return false }
        let url = URL(fileURLWithPath: reference.path)
        let parent = url.deletingLastPathComponent()
        do {
            try fileManager.removeItem(at: url)
            // Remove the per-item folder if it is now empty.
            if parent.standardizedFileURL != ownedFilesDirectory.standardizedFileURL,
               (try? fileManager.contentsOfDirectory(atPath: parent.path))?.isEmpty == true {
                try? fileManager.removeItem(at: parent)
            }
            return true
        } catch {
            return false
        }
    }

    public func isInsideOwnedDirectory(_ path: String) -> Bool {
        let root = ownedFilesDirectory.standardizedFileURL.resolvingSymlinksInPath().path
        let candidate = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
        return candidate.hasPrefix(root + "/")
    }

    /// Removes owned files that no item references any more (e.g. after a crash
    /// between removing an item and deleting its copy).
    ///
    /// - Parameter protectingNewerThan: when set, unreferenced copies modified on
    ///   or after this date are kept too. Used when a damaged history file may
    ///   still describe recent removals: those copies stay for the restore window
    ///   instead of cleanup stopping altogether.
    public func collectGarbage(keeping board: Board, protectingNewerThan cutoff: Date? = nil) {
        guard let entries = try? fileManager.contentsOfDirectory(at: ownedFilesDirectory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let referenced = Set(board.items.compactMap { item -> String? in
            guard let file = item.file, file.ownership == .owned else { return nil }
            return URL(fileURLWithPath: file.path).deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath().path
        })
        for entry in entries {
            let path = entry.standardizedFileURL.resolvingSymlinksInPath().path
            guard !referenced.contains(path) else { continue }
            if let cutoff {
                let modified = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
                if modified >= cutoff { continue }
            }
            try? fileManager.removeItem(at: entry)
        }
    }

    public static func sanitizedFileName(_ name: String) -> String {
        var cleaned = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasPrefix(".") { cleaned.removeFirst() }
        if cleaned.isEmpty { cleaned = "Item" }
        if cleaned.utf8.count > 200 {
            let ext = (cleaned as NSString).pathExtension
            let stem = String((cleaned as NSString).deletingPathExtension.prefix(120))
            cleaned = ext.isEmpty ? stem : stem + "." + ext
        }
        return cleaned
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
