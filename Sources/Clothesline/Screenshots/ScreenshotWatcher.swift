import AppKit
import CoreServices
import ClotheslineCore

/// Watches the screenshot folder and reports each new screenshot exactly once.
///
/// Design (event-driven, no polling):
/// - An FSEvents stream with file-level events on the screenshot folder
///   delivers creations and renames within ~100 ms. `screencapture` writes a
///   hidden temp file and renames it into place, so the visible name appears
///   only once the image is complete; a size-stability check covers other
///   writers and slow volumes.
/// - Each candidate is classified by the `kMDItemIsScreenCapture` extended
///   attribute that macOS stamps on screenshots (see `ScreenshotClassifier`).
/// - A second, tiny FSEvents stream watches `~/Library/Preferences` for
///   changes to `com.apple.screencapture.plist`, so a new save location chosen
///   in the Screenshot app (⇧⌘5 › Options) is picked up immediately.
/// - After sleep/wake, a volume mount, or an FSEvents "history dropped" flag,
///   the folder is reconciled once: files created since the last check that
///   carry the screenshot attribute are reported if they were missed.
final class ScreenshotWatcher: @unchecked Sendable {
    struct Config: Equatable {
        var enabled: Bool
        var includeRecordings: Bool
        /// A user-chosen folder overriding the macOS setting.
        var customFolder: URL?
    }

    /// Called on the main queue with each newly detected screenshot.
    var onScreenshot: (@MainActor (URL) -> Void)?
    /// Called on the main queue whenever the watched folder or its status changes.
    var onStatusChange: (@MainActor (Status) -> Void)?

    struct Status: Equatable {
        var folder: URL?
        var preferences: ScreenshotPreferences
        var watching: Bool
        var problem: String?
    }

    private let queue = DispatchQueue(label: "app.clothesline.screenshots", qos: .utility)
    private var folderStream: FSEventStreamRef?
    private var prefsStream: FSEventStreamRef?
    private var config = Config(enabled: false, includeRecordings: false, customFolder: nil)
    private var folder: URL?
    private var folderRealPath: String?
    private var preferences = ScreenshotPreferences()
    /// Paths already reported (bounded), to make detection idempotent.
    private var reported: [String] = []
    private var reportedSet: Set<String> = []
    private var lastReconcile = Date()
    private var inFlight: Set<String> = []

    deinit {
        stopStream(&folderStream)
        stopStream(&prefsStream)
    }

    // MARK: - Public API (main thread)

    func apply(_ newConfig: Config) {
        queue.async { [self] in
            let changed = newConfig != config
            config = newConfig
            if changed || folderStream == nil { restart() }
        }
    }

    /// Re-reads macOS preferences and reconciles; called on wake, on mount and
    /// when the line is shown.
    func refresh() {
        queue.async { [self] in
            let before = folder
            reloadPreferences()
            if resolveFolder() != before {
                restart()
            } else {
                reconcile()
            }
        }
    }

    // MARK: - Lifecycle (watcher queue)

    private func restart() {
        stopStream(&folderStream)
        reloadPreferences()
        startPreferencesStream()
        guard config.enabled else {
            folder = nil
            publishStatus(watching: false, problem: nil)
            return
        }
        guard let target = resolveFolder() else {
            publishStatus(watching: false, problem: "No screenshot folder")
            return
        }
        folder = target
        folderRealPath = Self.realPath(target.path)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: target.path, isDirectory: &isDir), isDir.boolValue else {
            publishStatus(watching: false, problem: "The screenshot folder “\(target.lastPathComponent)” is not available.")
            return
        }
        lastReconcile = Date()
        folderStream = makeStream(paths: [target.path], flags: FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagWatchRoot
        ), latency: 0.08, kind: .folder)
        let problem: String? = preferences.savesToFile || config.customFolder != nil ? nil :
            "macOS is set to put screenshots on the clipboard, not in a file. Use “Hang Clipboard” after taking one, or choose Options › Save to in the Screenshot app (⇧⌘5)."
        publishStatus(watching: folderStream != nil, problem: folderStream == nil ? "Could not watch the screenshot folder." : problem)
    }

    private func resolveFolder() -> URL? {
        if let custom = config.customFolder { return custom.standardizedFileURL }
        return preferences.resolvedFolder(homeDirectory: NSHomeDirectory())
    }

    private func reloadPreferences() {
        let domain = "com.apple.screencapture" as CFString
        CFPreferencesAppSynchronize(domain)
        func string(_ key: String) -> String? {
            CFPreferencesCopyAppValue(key as CFString, domain) as? String
        }
        preferences = ScreenshotPreferences(location: string("location"), target: string("target"), namePrefix: string("name"))
    }

    private func startPreferencesStream() {
        guard prefsStream == nil else { return }
        let prefsDir = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Preferences")
        prefsStream = makeStream(paths: [prefsDir], flags: FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes
        ), latency: 0.5, kind: .preferences)
    }

    private func publishStatus(watching: Bool, problem: String?) {
        let status = Status(folder: folder ?? resolveFolder(), preferences: preferences, watching: watching, problem: problem)
        let callback = onStatusChange
        DispatchQueue.main.async { MainActor.assumeIsolated { callback?(status) } }
    }

    // MARK: - FSEvents plumbing

    private enum StreamKind { case folder, preferences }

    private final class StreamContext {
        weak var watcher: ScreenshotWatcher?
        let kind: StreamKind
        init(watcher: ScreenshotWatcher, kind: StreamKind) { self.watcher = watcher; self.kind = kind }
    }

    private func makeStream(paths: [String], flags: FSEventStreamCreateFlags, latency: CFTimeInterval, kind: StreamKind) -> FSEventStreamRef? {
        let info = Unmanaged.passRetained(StreamContext(watcher: self, kind: kind)).toOpaque()
        var context = FSEventStreamContext(
            version: 0, info: info,
            retain: nil,
            release: { ptr in
                guard let ptr else { return }
                Unmanaged<StreamContext>.fromOpaque(ptr).release()
            },
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, eventPaths, eventFlags, _ in
            guard let info else { return }
            let ctx = Unmanaged<StreamContext>.fromOpaque(info).takeUnretainedValue()
            guard let watcher = ctx.watcher else { return }
            let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
            var events: [(String, FSEventStreamEventFlags)] = []
            for i in 0..<min(count, paths.count) { events.append((paths[i], eventFlags[i])) }
            watcher.handle(events, kind: ctx.kind)
        }
        guard let stream = FSEventStreamCreate(kCFAllocatorDefault, callback, &context, paths as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags) else {
            Unmanaged<StreamContext>.fromOpaque(info).release()
            return nil
        }
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return nil
        }
        return stream
    }

    private func stopStream(_ stream: inout FSEventStreamRef?) {
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
    }

    // Runs on `queue`.
    private func handle(_ events: [(String, FSEventStreamEventFlags)], kind: StreamKind) {
        switch kind {
        case .preferences:
            guard events.contains(where: { ($0.0 as NSString).lastPathComponent.hasPrefix("com.apple.screencapture") }) else { return }
            let before = folder
            let beforePrefs = preferences
            reloadPreferences()
            if resolveFolder() != before || preferences != beforePrefs { restart() }
        case .folder:
            guard let folder else { return }
            var needsReconcile = false
            for (path, flags) in events {
                let f = Int(flags)
                if f & (kFSEventStreamEventFlagRootChanged) != 0 {
                    // The folder itself was moved or deleted; re-resolve.
                    restart()
                    return
                }
                if f & (kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped) != 0 {
                    needsReconcile = true
                    continue
                }
                guard f & kFSEventStreamEventFlagItemIsFile != 0,
                      f & (kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemRenamed) != 0 else { continue }
                // Only direct children of the folder. FSEvents reports canonical
                // paths (e.g. /private/var/… for /var/…), so compare real paths.
                let parent = (path as NSString).deletingLastPathComponent
                guard parent == folder.path || Self.realPath(parent) == folderRealPath else { continue }
                consider(path, attempt: 0)
            }
            if needsReconcile { reconcile() }
        }
    }

    /// Checks a candidate file, waiting for its size to settle first.
    private func consider(_ path: String, attempt: Int, lastSize: Int64 = -1) {
        guard !reportedSet.contains(path) else { return }
        if attempt == 0 {
            guard !inFlight.contains(path) else { return }
            inFlight.insert(path)
        }
        let name = (path as NSString).lastPathComponent
        // Cheap rejection before touching the file.
        if name.hasPrefix(".") { inFlight.remove(path); return }

        let url = URL(fileURLWithPath: path)
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey, .creationDateKey]) else {
            inFlight.remove(path) // vanished (e.g. the old name of a rename)
            return
        }
        let size = Int64(values.fileSize ?? 0)
        if size == 0 || size != lastSize {
            // Not settled yet: check again shortly, up to ~4 s.
            if attempt < 20 {
                queue.asyncAfter(deadline: .now() + (attempt == 0 ? 0.05 : 0.2)) { [self] in
                    consider(path, attempt: attempt + 1, lastSize: size)
                }
            } else {
                inFlight.remove(path)
            }
            return
        }
        inFlight.remove(path)

        let classifier = ScreenshotClassifier(includeRecordings: config.includeRecordings, customPrefix: preferences.namePrefix)
        let candidate = ScreenshotClassifier.Candidate(
            fileName: name, isDirectory: values.isDirectory ?? false,
            hasScreenCaptureAttribute: Self.screenCaptureAttribute(at: path),
            creationDate: values.creationDate
        )
        guard classifier.classify(candidate) != .notScreenshot else { return }
        report(url)
    }

    private func report(_ url: URL) {
        let path = url.path
        guard reportedSet.insert(path).inserted else { return }
        reported.append(path)
        if reported.count > 500 {
            reportedSet.remove(reported.removeFirst())
        }
        let callback = onScreenshot
        DispatchQueue.main.async { MainActor.assumeIsolated { callback?(url) } }
    }

    /// Scans the folder for screenshots created since the last check.
    private func reconcile() {
        guard config.enabled, let folder else { return }
        let since = lastReconcile.addingTimeInterval(-2)
        lastReconcile = Date()
        let keys: [URLResourceKey] = [.creationDateKey, .isRegularFileKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return }
        let classifier = ScreenshotClassifier(includeRecordings: config.includeRecordings, customPrefix: preferences.namePrefix)
        let fresh = entries.compactMap { url -> (URL, Date)? in
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true,
                  let created = v.creationDate, created >= since else { return nil }
            return (url, created)
        }.sorted { $0.1 < $1.1 }
        for (url, created) in fresh where !reportedSet.contains(url.path) {
            // Reconciliation requires the screenshot attribute: no name guessing for older files.
            let candidate = ScreenshotClassifier.Candidate(fileName: url.lastPathComponent, hasScreenCaptureAttribute: Self.screenCaptureAttribute(at: url.path) ?? false, creationDate: created)
            if classifier.classify(candidate) != .notScreenshot, candidate.hasScreenCaptureAttribute == true {
                report(url)
            }
        }
    }

    /// Canonical path with all symlinks resolved. Unlike
    /// `URL.resolvingSymlinksInPath()`, this keeps the `/private` prefix, which
    /// is what FSEvents reports.
    static func realPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// Reads the screen-capture marker attribute. Returns nil if attributes are
    /// unsupported on the volume.
    static func screenCaptureAttribute(at path: String) -> Bool? {
        let name = "com.apple.metadata:kMDItemIsScreenCapture"
        let size = getxattr(path, name, nil, 0, 0, XATTR_NOFOLLOW)
        if size >= 0 { return true }
        switch errno {
        case ENOATTR: return false
        default: return nil // ENOTSUP and friends: unknown
        }
    }
}
