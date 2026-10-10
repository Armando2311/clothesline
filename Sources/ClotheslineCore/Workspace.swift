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
        self.id = id; self.date = date; self.action = action; self.items = items; self.resultPath = resultPath; self.recipeOptions = recipeOptions
    }
}

public struct WorkspaceState: Codable, Equatable, Sendable {
    public var configurations: [WorkspaceConfiguration] = []
    public var rules: [CollectionRule] = []
    public var history: [ActivityEntry] = []
    public var collectedFiles: [String:String] = [:]
    public init() {}
    public mutating func record(_ entry: ActivityEntry) {
        guard !entry.items.isEmpty else { return }
        history.insert(entry, at: 0)
        if history.count > 200 { history.removeLast(history.count - 200) }
    }
    public var retainedItems: [HangingItem] {
        var seen = Set<String>()
        return history.flatMap(\.items).filter { seen.insert($0.id.uuidString + ":" + ($0.file?.path ?? "")).inserted }
    }
    public func destination(for fileURL: URL?, source: ItemSource, kind: ItemKind, defaultLineID: UUID, validLineIDs: Set<UUID>) -> UUID {
        rules.first { validLineIDs.contains($0.lineID) && $0.matches(fileURL: fileURL, source: source, kind: kind) }?.lineID ?? defaultLineID
    }
    private enum CodingKeys: String, CodingKey { case configurations,rules,history,collectedFiles }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        configurations = try c.decodeIfPresent([WorkspaceConfiguration].self, forKey: .configurations) ?? []
        rules = try c.decodeIfPresent([CollectionRule].self, forKey: .rules) ?? []
        history = Array((try c.decodeIfPresent([ActivityEntry].self, forKey: .history) ?? []).prefix(200))
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
}

public struct WorkspacePersistence {
    public let url: URL
    public init(directory: URL) { url = directory.appendingPathComponent("workspaces.json") }
    public func load() throws -> WorkspaceState {
        guard FileManager.default.fileExists(atPath: url.path) else { return WorkspaceState() }
        do { return try JSONDecoder().decode(WorkspaceState.self, from: Data(contentsOf: url)) }
        catch {
            let quarantine = url.deletingLastPathComponent().appendingPathComponent("workspaces-corrupt-\(UUID().uuidString).json")
            try FileManager.default.moveItem(at: url, to: quarantine)
            throw error
        }
    }
    public func save(_ state: WorkspaceState) throws {
        // Refuse to replace an unreadable file if quarantine failed during load.
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try JSONDecoder().decode(WorkspaceState.self, from: Data(contentsOf: url))
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: url, options: .atomic)
    }
}
