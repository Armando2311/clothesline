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
        // A damaged file is quarantined on its own; the readable one is kept.
        let (state, failure) = persistence.loadRecovering()
        let loadError = failure.map { "Some workspace data could not be read. The damaged file was preserved. \($0.localizedDescription)" }
        var pruned = state
        let expired = pruned.prune()
        configurations = pruned.configurations; rules = pruned.rules; history = pruned.history; collectedFiles = pruned.collectedFiles
        error = loadError
        if expired && loadError == nil { writeHistory() }
    }
    private var state: WorkspaceState {
        var value = WorkspaceState(); value.configurations = configurations; value.rules = rules
        value.history = history; value.collectedFiles = collectedFiles; return value
    }
    private func save(_ parts: WorkspacePersistence.Parts = .settings) {
        do { try persistence.save(state, parts: parts); error = nil }
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
    /// History is a convenience log, so bursts of activity (a folder rule
    /// collecting 50 files, a multi-item drop) are written once, a moment later.
    /// `flush()` runs at quit; settings and rules are still written immediately.
    private let historySave = Delayed()
    private(set) var historyWrites = 0
    private func record(_ entry: ActivityEntry) {
        var value = state; value.record(entry); history = value.history
        historySave.schedule(after: 1) { [weak self] in self?.writeHistory() }
    }
    private func writeHistory() { historySave.cancel(); historyWrites += 1; save(.history) }
    func flush() { if historySave.isPending { writeHistory() } }
    /// Forgets all history. Clothesline-owned copies it was retaining become
    /// eligible for cleanup (the caller runs it).
    func clearHistory() { history = []; writeHistory() }
    /// Applies the retention window (e.g. at wake or on a long-running session).
    func pruneHistory() { var value = state; if value.prune() { history = value.history; writeHistory() } }
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
