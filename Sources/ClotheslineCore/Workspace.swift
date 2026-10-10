import Foundation

public struct WorkspaceConfiguration: Codable, Equatable, Sendable {
    public var lineID: UUID
    public var destinationPath: String?
    public var destinationBookmark: Data?
    public var exportPresetID: UUID?
    public var organization: String
    public var sortOrder: Board.SortOrder?
    public init(lineID: UUID, destinationPath: String? = nil, destinationBookmark: Data? = nil, exportPresetID: UUID? = nil, organization: String = "", sortOrder: Board.SortOrder? = nil) {
        self.lineID = lineID; self.destinationPath = destinationPath; self.destinationBookmark = destinationBookmark
        self.exportPresetID = exportPresetID; self.organization = organization; self.sortOrder = sortOrder
    }
    private enum CodingKeys: String, CodingKey { case lineID, destinationPath, destinationBookmark, exportPresetID, organization, sortOrder }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lineID = try c.decode(UUID.self, forKey: .lineID)
        destinationPath = try c.decodeIfPresent(String.self, forKey: .destinationPath)
        destinationBookmark = try c.decodeIfPresent(Data.self, forKey: .destinationBookmark)
        exportPresetID = try c.decodeIfPresent(UUID.self, forKey: .exportPresetID)
        organization = try c.decodeIfPresent(String.self, forKey: .organization) ?? ""
        sortOrder = try c.decodeIfPresent(Board.SortOrder.self, forKey: .sortOrder)
    }
}

public struct CollectionRule: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var lineID: UUID
    public var source: ItemSource?
    public var kind: ItemKind?
    public var folderPath: String?
    public var folderBookmark: Data?
    public var enabled: Bool
    public init(id: UUID = UUID(), name: String, lineID: UUID, source: ItemSource? = nil, kind: ItemKind? = nil, folderPath: String? = nil, folderBookmark: Data? = nil, enabled: Bool = true) {
        self.id = id; self.name = name; self.lineID = lineID; self.source = source; self.kind = kind
        self.folderPath = folderPath; self.folderBookmark = folderBookmark; self.enabled = enabled
    }
    public func matches(fileURL: URL?, source: ItemSource, kind: ItemKind) -> Bool {
        guard enabled, self.source == nil || self.source == source, self.kind == nil || self.kind == kind else { return false }
        if let folderPath {
            guard let fileURL else { return false }
            return fileURL.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath().path == URL(fileURLWithPath: folderPath).standardizedFileURL.resolvingSymlinksInPath().path
        }
        return true
    }
    private enum CodingKeys: String, CodingKey { case id,name,lineID,source,kind,folderPath,folderBookmark,enabled }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Collection rule"
        lineID = try c.decode(UUID.self, forKey: .lineID)
        source = try c.decodeIfPresent(ItemSource.self, forKey: .source)
        kind = try c.decodeIfPresent(ItemKind.self, forKey: .kind)
        folderPath = try c.decodeIfPresent(String.self, forKey: .folderPath)
        folderBookmark = try c.decodeIfPresent(Data.self, forKey: .folderBookmark)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}

public struct ActivityEntry: Codable, Identifiable, Equatable, Sendable {
    public enum Action: String, Codable, Sendable { case added, removed, exported }
    public var id: UUID
    public var date: Date
    public var action: Action
    public var items: [HangingItem]
    public var resultPath: String?
    public var recipeOptions: RecipeOptions?
    public var canRestore: Bool { action == .removed && !items.isEmpty }
    public init(id: UUID = UUID(), date: Date = Date(), action: Action, items: [HangingItem], resultPath: String? = nil, recipeOptions: RecipeOptions? = nil) {
        self.id = id; self.date = date; self.action = action
        // An addition only needs a readable label: the item itself is still on the
        // line. Never copy note text, links or file bookmarks into the log for it.
        self.items = action == .added ? items.map(ActivityEntry.redacted) : items
        self.resultPath = resultPath; self.recipeOptions = recipeOptions
    }

    /// A label-only copy of an item: kind, source, title and date. Notes and
    /// links lose their content (a note's title is its first line, so it is
    /// replaced too), and files lose their path and bookmark.
    public static func redacted(_ item: HangingItem) -> HangingItem {
        var copy = item
        copy.text = nil
        copy.link = nil
        copy.file = nil
        switch item.kind {
        case .text: copy.title = "Note"
        case .link: copy.title = item.link.flatMap { URL(string: $0)?.host } ?? "Link"
        default: break
        }
        return copy
    }
}

public struct WorkspaceState: Codable, Equatable, Sendable {
    public var configurations: [WorkspaceConfiguration] = []
    public var rules: [CollectionRule] = []
    public var history: [ActivityEntry] = []
    public var collectedFiles: [String:String] = [:]
    public init() {}
    /// How long removed items stay restorable (and their Clothesline-owned
    /// copies stay on disk). Older history is discarded.
    public static let retention: TimeInterval = 7 * 86400
    public static let maximumEntries = 200

    public mutating func record(_ entry: ActivityEntry, now: Date = Date()) {
        guard !entry.items.isEmpty else { return }
        history.insert(entry, at: 0)
        prune(now: now)
    }

    /// Drops entries past the retention window and beyond the entry limit.
    @discardableResult
    public mutating func prune(now: Date = Date()) -> Bool {
        let before = history.count
        let cutoff = now.addingTimeInterval(-Self.retention)
        history.removeAll { $0.date < cutoff }
        if history.count > Self.maximumEntries { history.removeLast(history.count - Self.maximumEntries) }
        return history.count != before
    }

    /// Items whose Clothesline-owned copies must stay on disk because history can
    /// still restore or re-export them. Additions never retain anything: those
    /// items are on the line (or were later removed, which has its own entry).
    public var retainedItems: [HangingItem] {
        var seen = Set<String>()
        return history.filter { $0.action != .added }.flatMap(\.items)
            .filter { seen.insert($0.id.uuidString + ":" + ($0.file?.path ?? "")).inserted }
    }
    public func destination(for fileURL: URL?, source: ItemSource, kind: ItemKind, defaultLineID: UUID, validLineIDs: Set<UUID>) -> UUID {
        rules.first { validLineIDs.contains($0.lineID) && $0.matches(fileURL: fileURL, source: source, kind: kind) }?.lineID ?? defaultLineID
    }
    private enum CodingKeys: String, CodingKey { case configurations,rules,history,collectedFiles }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        configurations = try c.decodeIfPresent([WorkspaceConfiguration].self, forKey: .configurations) ?? []
        rules = try c.decodeIfPresent([CollectionRule].self, forKey: .rules) ?? []
        history = Array((try c.decodeIfPresent([ActivityEntry].self, forKey: .history) ?? []).prefix(Self.maximumEntries))
        collectedFiles = try c.decodeIfPresent([String:String].self, forKey: .collectedFiles) ?? [:]
    }
}

/// Two unchanged observations separated by a quiet interval are required before collecting.
public struct FolderFileTracker: Sendable {
    public private(set) var collected: [String:String]
    private var pending: [String:(signature:String, since:Date)] = [:]
    public init(collected: [String:String] = [:]) { self.collected = collected }
    private func signature(size: Int64, modified: Date) -> String { "\(size):\(modified.timeIntervalSince1970)" }
    public mutating func observe(path: String, size: Int64, modified: Date, now: Date = Date()) -> Bool {
        let signature = signature(size: size, modified: modified)
        guard collected[path] != signature else { pending.removeValue(forKey: path); return false }
        if let previous = pending[path], previous.signature == signature { return now.timeIntervalSince(previous.since) >= 2 && now.timeIntervalSince(modified) >= 2 }
        pending[path] = (signature,now); return false
    }
    public mutating func markCollected(path: String, size: Int64, modified: Date) {
        collected[path] = signature(size: size, modified: modified); pending.removeValue(forKey: path)
    }
    /// True while a file was seen but has not yet proven stable. The watcher
    /// only schedules a follow-up check in that case.
    public var hasPending: Bool { !pending.isEmpty }
    /// Forgets pending files that were not seen in the latest scan (deleted or
    /// renamed while being written), so follow-up checks always end.
    public mutating func retainPending(_ paths: Set<String>) {
        pending = pending.filter { paths.contains($0.key) }
    }
}

/// Workspace settings (`workspaces.json`) and activity history (`history.json`)
/// are stored separately so that recording an addition never rewrites rules
/// and configurations, and vice versa. Older installs kept history inside
/// `workspaces.json`; it is read from there until `history.json` exists.
public final class WorkspacePersistence {
    public struct Parts: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let settings = Parts(rawValue: 1)
        public static let history = Parts(rawValue: 2)
        public static let all: Parts = [.settings, .history]
    }

    public let url: URL
    public let historyURL: URL
    /// Files confirmed readable (or written by us) during this session. A file
    /// that could not be quarantined is never replaced; checking once is enough.
    private var verified: Set<URL> = []

    public init(directory: URL) {
        url = directory.appendingPathComponent("workspaces.json")
        historyURL = directory.appendingPathComponent("history.json")
    }

    public static let corruptPrefixes = ["workspaces-corrupt-", "history-corrupt-"]

    /// Loads both files. Throws if either was damaged (it has been quarantined);
    /// use `loadRecovering()` to keep the half that was readable.
    public func load() throws -> WorkspaceState {
        let (state, failure) = loadRecovering()
        if let failure { throw failure }
        return state
    }

    /// Loads both files independently: a damaged one is quarantined and reported,
    /// and whatever the other file holds is still returned, so a later save
    /// never overwrites good settings (or good history) with defaults.
    public func loadRecovering() -> (state: WorkspaceState, failure: Error?) {
        var state = WorkspaceState()
        var failure: Error?
        if FileManager.default.fileExists(atPath: url.path) {
            do { state = try JSONDecoder().decode(WorkspaceState.self, from: Data(contentsOf: url)); verified.insert(url) }
            catch { failure = error; quarantine(url, prefix: "workspaces-corrupt-") }
        }
        if FileManager.default.fileExists(atPath: historyURL.path) {
            do {
                state.history = Array(try JSONDecoder().decode([ActivityEntry].self, from: Data(contentsOf: historyURL)).prefix(WorkspaceState.maximumEntries))
                verified.insert(historyURL)
            } catch { failure = failure ?? error; quarantine(historyURL, prefix: "history-corrupt-") }
        }
        return (state, failure)
    }

    /// Moves a damaged file aside and stamps it with the time it was found, which
    /// anchors the restore-window hold below. If the move fails the file stays
    /// in place and `verifyReplaceable` refuses to overwrite it.
    private func quarantine(_ file: URL, prefix: String) {
        let destination = file.deletingLastPathComponent().appendingPathComponent("\(prefix)\(UUID().uuidString).json")
        guard (try? FileManager.default.moveItem(at: file, to: destination)) != nil else { return }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: destination.path)
    }

    /// True while a damaged workspace or history file was quarantined less than
    /// one restore window ago. Its removals are unknown, so every unreferenced
    /// Clothesline-owned copy must be kept until the window has passed.
    public static func holdsOwnedCopies(in directory: URL, now: Date = Date()) -> Bool {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        return files.contains { file in
            guard corruptPrefixes.contains(where: { file.lastPathComponent.hasPrefix($0) }) else { return false }
            let found = (try? file.resourceValues(forKeys: Set(keys)))?.contentModificationDate ?? now
            return now < found.addingTimeInterval(WorkspaceState.retention)
        }
    }

    /// Refuse to replace an unreadable file that quarantine failed to move aside.
    private func verifyReplaceable(_ file: URL, as type: (some Decodable).Type) throws {
        guard !verified.contains(file), FileManager.default.fileExists(atPath: file.path) else { return }
        _ = try JSONDecoder().decode(type, from: Data(contentsOf: file))
        verified.insert(file)
    }

    public func save(_ state: WorkspaceState, parts: Parts = .all) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var parts = parts
        // History still only inside an old single-file workspaces.json: write
        // history.json first, or the settings write below would drop it.
        if parts.contains(.settings), !state.history.isEmpty, !FileManager.default.fileExists(atPath: historyURL.path) {
            parts.insert(.history)
        }
        if parts.contains(.history) {
            try verifyReplaceable(historyURL, as: [ActivityEntry].self)
            try JSONEncoder().encode(state.history).write(to: historyURL, options: .atomic)
            verified.insert(historyURL)
        }
        if parts.contains(.settings) {
            try verifyReplaceable(url, as: WorkspaceState.self)
            var settingsOnly = state
            settingsOnly.history = []
            try JSONEncoder().encode(settingsOnly).write(to: url, options: .atomic)
            verified.insert(url)
        }
    }
}
