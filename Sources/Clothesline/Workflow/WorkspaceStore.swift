import Foundation
import Combine
import ClotheslineCore

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published private(set) var configurations: [WorkspaceConfiguration]
    @Published private(set) var rules: [CollectionRule]
    @Published private(set) var history: [ActivityEntry]
    @Published private(set) var error: String?
    let directory: URL
    private let persistence: WorkspacePersistence
    private var collectedFiles: [String:String]
    init(directory: URL) {
        self.directory = directory
        persistence = WorkspacePersistence(directory: directory)
        let state: WorkspaceState
        var loadError: String?
        do { state = try persistence.load() }
        catch { state = WorkspaceState(); loadError = "Workspace settings could not be read. The damaged file was preserved. \(error.localizedDescription)" }
        configurations = state.configurations; rules = state.rules; history = state.history; collectedFiles = state.collectedFiles
        error = loadError
    }
    private var state: WorkspaceState {
        var value = WorkspaceState(); value.configurations = configurations; value.rules = rules
        value.history = history; value.collectedFiles = collectedFiles; return value
    }
    private func save() {
        do { try persistence.save(state); error = nil }
        catch { self.error = "Could not save workspace settings: \(error.localizedDescription)" }
    }
    func config(for lineID: UUID) -> WorkspaceConfiguration? { configurations.first { $0.lineID == lineID } }
    func update(_ config: WorkspaceConfiguration) {
        configurations.removeAll { $0.lineID == config.lineID }; configurations.append(config); save()
    }
    func upsert(_ rule: CollectionRule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) { rules[index] = rule } else { rules.append(rule) }; save()
    }
    func removeRule(_ id: UUID) { rules.removeAll { $0.id == id }; save() }
    func recordAdded(_ items: [HangingItem]) { record(ActivityEntry(action: .added, items: items)) }
    func recordRemoved(_ items: [HangingItem]) { record(ActivityEntry(action: .removed, items: items)) }
    func recordExport(items: [HangingItem], resultURL: URL, options: RecipeOptions) {
        record(ActivityEntry(action: .exported, items: items, resultPath: resultURL.path, recipeOptions: options))
    }
    private func record(_ entry: ActivityEntry) { var value = state; value.record(entry); history = value.history; save() }
    var retainedItems: [HangingItem] { state.retainedItems }
    func destination(for fileURL: URL?, source: ItemSource, kind: ItemKind, defaultLineID: UUID, validLineIDs: Set<UUID>) -> UUID {
        state.destination(for: fileURL, source: source, kind: kind, defaultLineID: defaultLineID, validLineIDs: validLineIDs)
    }
    func destinationURL(for lineID: UUID) -> URL? {
        guard let config = config(for: lineID) else { return nil }
        return Self.resolve(bookmark: config.destinationBookmark, path: config.destinationPath)
    }
    static func resolve(bookmark: Data?, path: String?) -> URL? {
        if let bookmark {
            var stale = false
            let flags: URL.BookmarkResolutionOptions = FileAccess.isSandboxed ? [.withSecurityScope,.withoutUI] : [.withoutUI]
            if let url = try? URL(resolvingBookmarkData: bookmark, options: flags, bookmarkDataIsStale: &stale) { return url }
        }
        return path.map { URL(fileURLWithPath: $0) }
    }
    static func bookmark(for url: URL) -> Data? {
        try? url.bookmarkData(options: FileAccess.isSandboxed ? [.withSecurityScope] : [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }
    var fileTracker: FolderFileTracker { FolderFileTracker(collected: collectedFiles) }
    func saveTracker(_ tracker: FolderFileTracker) { collectedFiles = tracker.collected; save() }
}
