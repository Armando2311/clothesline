import AppKit
import ClotheslineCore

/// Watches only the immediate children of explicitly selected folders. Never edits a source file.
@MainActor
final class FolderRuleWatcher {
    private weak var model: AppModel?
    private var timer: Timer?
    private var scanning = false
    private var tracker: FolderFileTracker
    private var task: Task<Void,Never>?
    init(model: AppModel) { self.model = model; tracker = model.activity.fileTracker }
    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in Task { @MainActor in self?.scan() } }
        scan()
    }
    func stop() { timer?.invalidate(); timer = nil; task?.cancel(); task = nil }
    private struct Candidate: Sendable { let url: URL; let rule: CollectionRule; let size: Int64; let modified: Date }
    private func scan() {
        guard !scanning, let model else { return }
        let rules = model.activity.rules.filter { $0.enabled && $0.folderPath != nil && model.board.line($0.lineID) != nil }
        let folders = rules.compactMap { rule -> (CollectionRule,URL)? in
            guard let url = WorkspaceStore.resolve(bookmark: rule.folderBookmark, path: rule.folderPath) else { return nil }
            guard !FileAccess.isSandboxed || url.startAccessingSecurityScopedResource() else { return nil }
            return (rule,url)
        }
        guard !folders.isEmpty else { return }
        scanning = true
        task = Task { [weak self] in
            let candidates = await Task.detached(priority: .utility) {
                folders.flatMap { rule,folder -> [Candidate] in
                    let keys: Set<URLResourceKey> = [.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey,.contentModificationDateKey]
                    guard let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else { return [] }
                    var resolvedRule = rule; resolvedRule.folderPath = folder.path
                    return urls.compactMap { url in
                        guard let value = try? url.resourceValues(forKeys: keys), value.isRegularFile == true, value.isSymbolicLink != true,
                              let size = value.fileSize, let modified = value.contentModificationDate else { return nil }
                        let kind = ItemClassifier.kind(forFileName: url.lastPathComponent, isDirectory: false, isPackage: false)
                        guard resolvedRule.matches(fileURL: url, source: .manual, kind: kind) else { return nil }
                        return Candidate(url: url, rule: rule, size: Int64(size), modified: modified)
                    }
                }
            }.value
            defer { if FileAccess.isSandboxed { folders.forEach { $0.1.stopAccessingSecurityScopedResource() } }; self?.scanning = false }
            guard !Task.isCancelled, let self, let model = self.model else { return }
            for candidate in candidates {
                guard model.activity.rules.contains(candidate.rule) && candidate.rule.enabled, model.board.line(candidate.rule.lineID) != nil else { continue }
                let key = candidate.rule.id.uuidString + ":" + candidate.url.path
                if self.tracker.observe(path: key, size: candidate.size, modified: candidate.modified) {
                    model.hang(fileURLs: [candidate.url], source: .manual, lineID: candidate.rule.lineID)
                    self.tracker.markCollected(path: key, size: candidate.size, modified: candidate.modified)
                    model.activity.saveTracker(self.tracker)
                }
            }
        }
    }
}
