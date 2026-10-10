import AppKit
import Combine
import CoreServices
import ClotheslineCore

/// Watches only the immediate children of explicitly selected folders. Never edits a source file.
///
/// Event-driven, like the screenshot watcher: an FSEvents stream covers the
/// folders of enabled folder rules and exists only while at least one such rule
/// exists. A change triggers one scan. A file that is still being written gets
/// a single follow-up check a few seconds later, repeated only until it is
/// stable (or gone). With no folder rules nothing runs at all.
@MainActor
final class FolderRuleWatcher {
    private weak var model: AppModel?
    private var scanning = false
    private var rescanRequested = false
    private var tracker: FolderFileTracker
    private var task: Task<Void,Never>?
    private var stream: FolderEventStream?
    private var watchedPaths: [String] = []
    private let followUp = Delayed()
    private var rulesSubscription: AnyCancellable?
    private var started = false

    /// Seconds between checks while a file is settling. The tracker needs two
    /// identical observations at least two seconds apart.
    static let settleInterval: TimeInterval = 2.5

    init(model: AppModel) { self.model = model; tracker = model.activity.fileTracker }

    /// True while an FSEvents stream is active (for tests and diagnostics).
    var isWatching: Bool { stream != nil }

    func start() {
        guard !started, let model else { return }
        started = true
        rulesSubscription = model.activity.$rules.receive(on: RunLoop.main).sink { [weak self] _ in self?.rulesChanged() }
        rulesChanged()
    }

    func stop() {
        started = false
        rulesSubscription = nil
        stream = nil
        watchedPaths = []
        followUp.cancel()
        task?.cancel(); task = nil
    }

    private var activeRules: [CollectionRule] {
        guard let model else { return [] }
        return model.activity.rules.filter { $0.enabled && $0.folderPath != nil && model.board.line($0.lineID) != nil }
    }

    private func rulesChanged() {
        guard started else { return }
        let paths = Array(Set(activeRules.compactMap { WorkspaceStore.resolve(bookmark: $0.folderBookmark, path: $0.folderPath)?.path })).sorted()
        if paths != watchedPaths {
            watchedPaths = paths
            stream = paths.isEmpty ? nil : FolderEventStream(paths: paths) { [weak self] in self?.scan() }
        }
        if paths.isEmpty { followUp.cancel() } else { scan() }
    }

    private struct Candidate: Sendable { let url: URL; let rule: CollectionRule; let size: Int64; let modified: Date }

    private func scan() {
        guard started, let model else { return }
        guard !scanning else { rescanRequested = true; return }
        let folders = activeRules.compactMap { rule -> (CollectionRule,URL)? in
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
            if FileAccess.isSandboxed { folders.forEach { $0.1.stopAccessingSecurityScopedResource() } }
            guard let self else { return }
            self.scanning = false
            guard !Task.isCancelled, self.started, let model = self.model else { return }
            var seen = Set<String>()
            for candidate in candidates {
                guard model.activity.rules.contains(candidate.rule) && candidate.rule.enabled, model.board.line(candidate.rule.lineID) != nil else { continue }
                let key = candidate.rule.id.uuidString + ":" + candidate.url.path
                seen.insert(key)
                if self.tracker.observe(path: key, size: candidate.size, modified: candidate.modified) {
                    model.hang(fileURLs: [candidate.url], source: .manual, lineID: candidate.rule.lineID)
                    self.tracker.markCollected(path: key, size: candidate.size, modified: candidate.modified)
                    model.activity.saveTracker(self.tracker)
                }
            }
            self.tracker.retainPending(seen)
            if self.rescanRequested {
                self.rescanRequested = false
                self.scan()
            } else if self.tracker.hasPending {
                // A file is still settling: check once more shortly. This stops
                // as soon as nothing is pending.
                self.followUp.schedule(after: Self.settleInterval) { [weak self] in self?.scan() }
            }
        }
    }
}

/// A minimal FSEvents stream that reports "something changed" on the main queue.
final class FolderEventStream {
    private var stream: FSEventStreamRef?

    private final class Box {
        let handler: @MainActor () -> Void
        init(_ handler: @escaping @MainActor () -> Void) { self.handler = handler }
    }

    init?(paths: [String], latency: CFTimeInterval = 1.0, handler: @escaping @MainActor () -> Void) {
        let info = Unmanaged.passRetained(Box(handler)).toOpaque()
        var context = FSEventStreamContext(
            version: 0, info: info, retain: nil,
            release: { ptr in
                guard let ptr else { return }
                Unmanaged<Box>.fromOpaque(ptr).release()
            },
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let box = Unmanaged<Box>.fromOpaque(info).takeUnretainedValue()
            // Delivered on the main queue (see FSEventStreamSetDispatchQueue below).
            MainActor.assumeIsolated { box.handler() }
        }
        guard let created = FSEventStreamCreate(kCFAllocatorDefault, callback, &context, paths as CFArray,
                                                FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency,
                                                FSEventStreamCreateFlags(kFSEventStreamCreateFlagNone)) else {
            Unmanaged<Box>.fromOpaque(info).release()
            return nil
        }
        FSEventStreamSetDispatchQueue(created, DispatchQueue.main)
        guard FSEventStreamStart(created) else {
            FSEventStreamInvalidate(created)
            FSEventStreamRelease(created)
            return nil
        }
        stream = created
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
