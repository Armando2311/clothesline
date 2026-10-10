import AppKit
import Combine
import ClotheslineCore

/// The single source of truth for the app: the board, settings and per-item
/// file availability. Views observe it; all mutations go through it so that
/// persistence, undo and owned-file cleanup are handled in one place.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var board: Board
    @Published var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            persistSettings()
            settingsDidChange?(oldValue)
        }
    }
    @Published private(set) var availability: [UUID: Artwork.Availability] = [:]
    @Published var screenshotStatus: ScreenshotWatcher.Status?
    @Published var hotKeyResults: [HotKeyCenter.Action: HotKeyCenter.RegistrationResult] = [:]
    @Published private(set) var canUndoRemoval = false

    @Published var query = "" {
        didSet {
            reconcileSelection()
            refreshOCR()
        }
    }
    @Published var selectedIDs: Set<UUID> = []
    @Published private(set) var recognizedText: [UUID: String] = [:]
    @Published var searchFilters = SearchFilters() { didSet { reconcileSelection(); refreshOCR() } }
    @Published private(set) var statusMessage: String?
    @Published private(set) var groups: [ItemGroup] = []
    @Published var collapsedGroupIDs:Set<UUID> = []
    let activity: WorkspaceStore
    private let noticeExpiry = Delayed()
    private var persistenceError:String?
    private let ocr: OCRIndex
    private var ocrInputsTask: Task<Void, Never>?
    var isSearching: Bool { searchFilters.isActive || !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var visibleItems: [HangingItem] { searchFilters.results(board: board, query: query, recognizedText: recognizedText) }
    var selectedItems: [HangingItem] { visibleItems.filter { selectedIDs.contains($0.id) } }
    private func reconcileSelection() { selectedIDs.formIntersection(Set(visibleItems.map(\.id))) }
    func refreshOCR() {
        ocrInputsTask?.cancel()
        ocr.stop()
        guard isSearching else { return }
        let references = board.items.compactMap { item -> (UUID, FileReference)? in
            guard [.image,.screenshot].contains(item.kind), let file = item.file else { return nil }
            return (item.id,file)
        }
        let files = self.files
        ocrInputsTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 150_000_000) } catch { return }
            let inputs = await Task.detached(priority: .utility) {
                references.compactMap { id,reference -> (UUID, URL)? in
                    guard let url = files.resolve(reference).url else { return nil }
                    return (id,url)
                }
            }.value
            guard !Task.isCancelled, let self, self.isSearching else { return }
            self.ocr.refresh(inputs)
        }
    }

    /// How the most recent removal should look on screen.
    enum RemovalStyle { case unclip, delivered }
    private(set) var lastRemovalStyle: RemovalStyle = .unclip
    /// Items added in the most recent mutation (for the "clip on" animation).
    private(set) var recentlyAdded: Set<UUID> = []

    var settingsDidChange: ((AppSettings) -> Void)?
    /// Asks the UI to briefly reveal the line (e.g. after a screenshot).
    var requestPeek: (() -> Void)?

    let store: BoardStore
    let files = FileAccess()
    let thumbnails = ThumbnailCache()
    private let saveDebounce = Delayed()
    private let expiryTimer = Delayed()
    private let resolveQueue = DispatchQueue(label: "app.clothesline.resolve", qos: .userInitiated)

    private struct RemovedBatch {
        var entries: [(HangingItem, Int)]
    }
    private var undoStack: [RemovedBatch] = []
    private let maxUndo = 20

    private static let settingsKey = "settings.v1"

    init(store: BoardStore = BoardStore(directory: BoardStore.defaultDirectory()), ocrIndex: OCRIndex? = nil) {
        self.ocr = ocrIndex ?? OCRIndex(debounceNanoseconds: 0)
        self.store = store
        self.activity = WorkspaceStore(directory: store.directory)
        switch store.load() {
        case .loaded(let b), .fresh(let b):
            board = b
        case .recovered(let b, let backup):
            board = b
            Log.error("State file was unreadable; moved to \(backup.lastPathComponent)")
        }
        if let data = UserDefaults.standard.data(forKey: Self.settingsKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = AppSettings()
        }
        ocr.changed = { [weak self] text in
            self?.recognizedText = text
            self?.reconcileSelection()
        }
        let groupURL = store.directory.appendingPathComponent("groups.json")
        if let data = try? Data(contentsOf: groupURL) {
            do { groups = try JSONDecoder().decode([ItemGroup].self,from:data) }
            catch { try? FileManager.default.moveItem(at:groupURL,to:store.directory.appendingPathComponent("groups.corrupt-\(UUID().uuidString).json")) }
        }
        collapsedGroupIDs = Set(groups.map(\.id))
        collectOwnedGarbage()
        applyRetention()
    }

    // MARK: - Persistence

    private func persistSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.settingsKey)
        }
    }

    private func mutate(_ change: (inout Board) -> Void) {
        var copy = board
        change(&copy)
        guard copy != board else { return }
        board = copy
        reconcileSelection()
        refreshOCR()
        saveNow()
        scheduleExpiryCheck()
    }

    private func scheduleSave() {
        saveDebounce.schedule(after: 0.4) { [weak self] in self?.saveNow() }
    }

    func saveNow() {
        saveDebounce.cancel()
        do { try store.save(board); persistenceError = nil }
        catch { persistenceError = "Could not save your collection: \(error.localizedDescription)"; notice(persistenceError!); Log.error("Saving failed: \(error.localizedDescription)") }
    }

    /// Called at quit: applies quit-time cleanup, deletes owned copies whose
    /// removal can no longer be undone, and writes the final state.
    func prepareForTermination() {
        ocrInputsTask?.cancel()
        ocr.stop()
        if settings.retention.clearUnpinnedOnQuit {
            for line in board.lines {
                let ids = Set(board.items(on: line.id).filter { !$0.pinned }.map(\.id))
                remove(ids, style: .unclip, undoable: false)
            }
        }
        flushUndo()
        collectOwnedGarbage()
        saveNow()
    }

    // MARK: - Lines

    var activeItems: [HangingItem] { board.activeItems }

    func activate(lineID: UUID) {
        mutate { $0.activate(lineID: lineID) }
        if let order = workspaceForActiveLine?.sortOrder { sortActiveLine(by:order) }
    }

    @discardableResult
    func addLine(named name: String, expiryHours: Double? = nil) -> Line {
        var created: Line?
        mutate {
            created = $0.addLine(named: name, expiryHours: expiryHours)
            $0.activate(lineID: created!.id)
        }
        return created!
    }

    func renameLine(_ id: UUID, to name: String) { mutate { $0.renameLine(id, to: name) } }
    func setLineExpiry(_ id: UUID, hours: Double?) { mutate { $0.setExpiry(id, hours: hours) }; applyRetention() }
    func deleteLine(_ id: UUID) { mutate { $0.deleteLine(id) } }

    func cycleLine(by offset: Int) {
        guard board.lines.count > 1, let i = board.lines.firstIndex(where: { $0.id == board.activeLineID }) else { return }
        let next = (i + offset + board.lines.count) % board.lines.count
        activate(lineID: board.lines[next].id)
    }

    // MARK: - Hanging things

    private func targetLine(_ lineID: UUID?) -> UUID {
        if let lineID, board.line(lineID) != nil { return lineID }
        return board.activeLineID
    }

    /// Hangs files by reference. The originals are never moved or copied.
    @discardableResult
    func hang(fileURLs: [URL], source: ItemSource, lineID: UUID? = nil, at position: Int? = nil, ownership: FileOwnership = .referenced) -> [UUID] {
        var added: [UUID] = []
        mutate { board in
            var pos = position
            for url in fileURLs {
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
                var kind = ItemClassifier.kind(forFileName: url.lastPathComponent, isDirectory: values?.isDirectory ?? false, isPackage: values?.isPackage ?? false)
                if source == .screenshot { kind = .screenshot }
                let reference = files.makeReference(for: url, ownership: ownership)
                let item = HangingItem(kind: kind, source: source, title: ItemClassifier.title(forFileName: url.lastPathComponent, kind: kind),
                                       lineID: routedLine(url:url,source:source,kind:kind,explicit:lineID), file: reference)
                switch board.add(item, atLinePosition: pos) {
                case .added(let i):
                    added.append(i.id)
                    availability[i.id] = .available
                    if let p = pos { pos = p + 1 }
                case .alreadyPresent:
                    break
                }
            }
        }
        recentlyAdded = Set(added)
        activity.recordAdded(board.items.filter { added.contains($0.id) })
        let duplicateCount = fileURLs.count - added.count
        notice(added.isEmpty ? "Already collected" : "Added \(added.count) item\(added.count == 1 ? "" : "s")\(duplicateCount > 0 ? " · \(duplicateCount) already collected" : "")")
        return added
    }

    @discardableResult
    func hang(text: String, source: ItemSource, lineID: UUID? = nil, at position: Int? = nil) -> UUID? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let link = ItemClassifier.link(from: trimmed) {
            return hang(link: link, source: source, lineID: lineID, at: position)
        }
        let item = HangingItem(kind: .text, source: source, title: ItemClassifier.title(forText: trimmed), lineID: routedLine(url:nil,source:source,kind:.text,explicit:lineID), text: trimmed)
        return add(item, at: position)
    }

    @discardableResult
    func hang(link: String, title: String? = nil, source: ItemSource, lineID: UUID? = nil, at position: Int? = nil) -> UUID? {
        let item = HangingItem(kind: .link, source: source, title: title ?? ItemClassifier.title(forLink: link), lineID: routedLine(url:nil,source:source,kind:.link,explicit:lineID), link: link)
        return add(item, at: position)
    }

    /// Saves raw image data (e.g. dragged from a browser or copied) as a
    /// Clothesline-owned file and hangs it.
    @discardableResult
    func hang(imageData: Data, fileExtension: String, suggestedName: String?, source: ItemSource, lineID: UUID? = nil, at position: Int? = nil) -> UUID? {
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
        var name = suggestedName.map { ($0 as NSString).deletingPathExtension } ?? "Image \(stamp)"
        if name.isEmpty { name = "Image" }
        do {
            let url = try store.makeOwnedFileURL(preferredName: name + "." + fileExtension)
            try imageData.write(to: url, options: .atomic)
            return hang(fileURLs: [url], source: source, lineID: lineID, at: position, ownership: .owned).first
        } catch {
            notice("Could not save image: \(error.localizedDescription)")
            Log.error("Could not save image: \(error.localizedDescription)")
            return nil
        }
    }

    private func add(_ item: HangingItem, at position: Int?) -> UUID? {
        var result: UUID?
        mutate { board in
            if case .added(let i) = board.add(item, atLinePosition: position) { result = i.id }
        }
        recentlyAdded = result.map { [$0] } ?? []
        if let result, let added = board.item(result) { activity.recordAdded([added]); notice("Added \(added.kind.displayName.lowercased())") }
        else { notice("Already collected") }
        return result
    }

    func screenshotDetected(_ url: URL) {
        guard settings.collectScreenshots else { return }
        let added = hang(fileURLs: [url], source: .screenshot, lineID: settings.screenshotLineID)
        guard !added.isEmpty else { return }
        applyRetention()
        if settings.revealOnScreenshot { requestPeek?() }
    }

    // MARK: - Removing

    /// Takes items off the line. Referenced files are never touched. Owned
    /// copies are kept until the removal can no longer be undone.
    func remove(_ ids: Set<UUID>, style: RemovalStyle = .unclip, undoable: Bool = true) {
        guard !ids.isEmpty else { return }
        var entries: [(HangingItem, Int)] = []
        for id in ids {
            guard let item = board.item(id) else { continue }
            let pos = board.items(on: item.lineID).firstIndex { $0.id == id } ?? 0
            entries.append((item, pos))
        }
        guard !entries.isEmpty else { return }
        activity.recordRemoved(entries.map { $0.0 })
        lastRemovalStyle = style
        mutate { _ = $0.remove(ids) }
        notice("Removed \(entries.count) item\(entries.count == 1 ? "" : "s") · available in History")
        recentlyAdded = []
        for (item, _) in entries { if let f = item.file { files.stopAccessing(path: f.path) } }
        let batch = RemovedBatch(entries: entries.sorted { $0.1 < $1.1 })
        if undoable {
            undoStack.append(batch)
            if undoStack.count > maxUndo { finalize(undoStack.removeFirst()) }
        } else {
            finalize(batch)
        }
        canUndoRemoval = !undoStack.isEmpty
    }

    func clearActiveLine() {
        let ids = Set(activeItems.filter { !$0.pinned }.map(\.id))
        remove(ids)
    }

    func undoLastRemoval() {
        guard let batch = undoStack.popLast() else { return }
        canUndoRemoval = !undoStack.isEmpty
        var restored: [UUID] = []
        mutate { board in
            for (item, position) in batch.entries {
                var item = item
                if board.line(item.lineID) == nil { item.lineID = board.activeLineID }
                if case .added = board.add(item, atLinePosition: position) { restored.append(item.id) }
            }
        }
        recentlyAdded = Set(restored)
        revalidate(ids: Set(restored))
    }

    private func finalize(_ batch: RemovedBatch) {
        for (item, _) in batch.entries {
            guard let file = item.file, file.ownership == .owned else { continue }
            // Another line might still hang the same owned copy.
            if board.items.contains(where: { $0.file?.path == file.path }) || activity.retainedItems.contains(where: { $0.file?.path == file.path }) { continue }
            store.deleteOwnedFile(file)
        }
    }

    private func flushUndo() {
        undoStack.forEach(finalize)
        undoStack.removeAll()
        canUndoRemoval = false
    }

    // MARK: - Editing

    func createNote(_ text: String) -> UUID? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return add(HangingItem(kind: .text,source: .manual,title: ItemClassifier.title(forText: text),lineID: board.activeLineID,text: text),at: nil)
    }
    func editNote(_ id: UUID, text: String) { mutate { $0.editNote(id, text: text) } }
    func renameItem(_ id: UUID, title: String) { mutate { $0.rename(id, to: title) } }

    func setPinned(_ ids: Set<UUID>, _ pinned: Bool) { mutate { $0.setPinned(ids, pinned) } }

    func togglePinned(_ ids: Set<UUID>) {
        let allPinned = ids.allSatisfy { board.item($0)?.pinned == true }
        setPinned(ids, !allPinned)
    }

    func move(_ ids: Set<UUID>, toPosition position: Int) {
        recentlyAdded = []
        mutate { $0.move(ids, toLinePosition: position, lineID: $0.activeLineID) }
    }

    func move(_ ids: Set<UUID>, toLine lineID: UUID) {
        recentlyAdded = []
        lastRemovalStyle = .delivered
        mutate { $0.move(ids, toLine: lineID) }
    }

    func sortActiveLine(by order: Board.SortOrder) {
        recentlyAdded = []
        mutate { $0.sort(lineID: $0.activeLineID, by: order) }
    }

    func updateReference(_ id: UUID, to url: URL) {
        guard let item = board.item(id), let old = item.file else { return }
        mutate { $0.updateFile(id, files.makeReference(for: url, ownership: old.ownership)) }
        availability[id] = .available
    }

    // MARK: - File availability

    /// The resolved URL for a file-backed item, if it is reachable.
    func url(for item: HangingItem) -> URL? {
        guard let file = item.file else { return nil }
        if availability[item.id] == .missing || availability[item.id] == .offline { return nil }
        return file.url
    }

    /// Re-resolves file references off the main thread and refreshes the
    /// availability of each item (handles renamed, moved, deleted files and
    /// unplugged drives).
    func revalidate(ids: Set<UUID>? = nil) {
        let targets = board.items.filter { $0.file != nil && (ids == nil || ids!.contains($0.id)) }
        guard !targets.isEmpty else { return }
        let files = self.files
        resolveQueue.async { [weak self] in
            var results: [(UUID, FileAccess.Resolution)] = []
            for item in targets {
                guard let ref = item.file else { continue }
                results.append((item.id, files.resolve(ref)))
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                var updates: [(UUID, FileReference)] = []
                for (id, resolution) in results {
                    if self.availability[id] != resolution.availability { self.availability[id] = resolution.availability }
                    if let updated = resolution.updatedReference { updates.append((id, updated)) }
                }
                self.refreshOCR()
                if !updates.isEmpty {
                    self.recentlyAdded = []
                    self.mutate { board in for (id, ref) in updates { board.updateFile(id, ref) } }
                }
            }
        }
    }

    // MARK: - Retention

    func applyRetention() {
        let ids = settings.retention.itemsToRemove(from: board, now: Date())
        if !ids.isEmpty { remove(ids, style: .unclip, undoable: false) }
        scheduleExpiryCheck()
    }

    /// One-shot timer for the next expiry, never a polling loop.
    private func scheduleExpiryCheck() {
        guard let next = settings.retention.nextExpiry(in: board, after: Date()) else {
            expiryTimer.cancel()
            return
        }
        expiryTimer.schedule(after: next.timeIntervalSinceNow + 1) { [weak self] in self?.applyRetention() }
    }
    func notice(_ message: String) {
        statusMessage = persistenceError ?? message
        noticeExpiry.schedule(after:4) { [weak self] in
            guard let self else { return }; self.statusMessage = self.persistenceError
        }
    }
    private func routedLine(url:URL?,source:ItemSource,kind:ItemKind,explicit:UUID?) -> UUID {
        if let explicit { return targetLine(explicit) }
        return activity.destination(for:url,source:source,kind:kind,defaultLineID:board.activeLineID,validLineIDs:Set(board.lines.map(\.id)))
    }
    var workspaceForActiveLine: WorkspaceConfiguration? { activity.config(for:board.activeLineID) }
    func setWorkspaceDestination(_ url:URL) {
        var config = workspaceForActiveLine ?? WorkspaceConfiguration(lineID:board.activeLineID)
        config.destinationPath = url.path
        config.destinationBookmark = WorkspaceStore.bookmark(for:url)
        activity.update(config)
    }
    func setWorkspacePreset(_ id:UUID?) {
        var config = workspaceForActiveLine ?? WorkspaceConfiguration(lineID:board.activeLineID)
        config.exportPresetID = id; activity.update(config)
    }
    func restoreActivity(_ entry:ActivityEntry) {
        query = ""; searchFilters = SearchFilters()
        var restored:[UUID] = []
        mutate { board in
            for var item in entry.items {
                if let file = item.file, file.ownership == .owned, !FileManager.default.fileExists(atPath:file.path) { continue }
                if board.item(item.id) != nil { restored.append(item.id); continue }
                if board.line(item.lineID) == nil { item.lineID = board.activeLineID }
                if case .added = board.add(item) { restored.append(item.id) }
            }
            if let id = restored.first, let item = board.item(id) { board.activate(lineID:item.lineID) }
        }
        recentlyAdded = Set(restored); selectedIDs = Set(restored); reconcileSelection(); revalidate(ids:Set(restored))
        notice(restored.isEmpty ? "No recoverable items — original files may be unavailable" : "Restored \(restored.count) items to the line")
    }
    func groupItems(_ ids:Set<UUID>,named name:String) {
        let members = Set(board.activeItems.filter { ids.contains($0.id) }.map(\.id))
        guard members.count > 1 else { return }
        ungroupItems(members)
        let title = name.trimmingCharacters(in:.whitespacesAndNewlines)
        let firstPosition = board.activeItems.firstIndex { members.contains($0.id) } ?? 0
        mutate { $0.move(members,toLinePosition:firstPosition,lineID:$0.activeLineID) }
        groups.append(ItemGroup(name:title.isEmpty ? "Group" : title,lineID:board.activeLineID,itemIDs:members))
        collapsedGroupIDs = Set(groups.map(\.id))
        saveGroups(); notice("Grouped \(members.count) items")
    }
    func ungroupItems(_ ids:Set<UUID>) {
        groups = groups.compactMap { value in
            var group = value; group.itemIDs.subtract(ids); return group.itemIDs.count > 1 ? group : nil
        }; saveGroups()
    }
    func groupName(for item:HangingItem) -> String? { groups.first { $0.lineID == item.lineID && $0.itemIDs.contains(item.id) }?.name }
    private func saveGroups() {
        do { try FileManager.default.createDirectory(at:store.directory,withIntermediateDirectories:true); try JSONEncoder().encode(groups).write(to:store.directory.appendingPathComponent("groups.json"),options:.atomic) }
        catch { notice("Could not save groups: \(error.localizedDescription)") }
    }
    private func collectOwnedGarbage() {
        // A quarantined history file may still describe removed owned copies.
        // Preserve those copies until recovery has been resolved explicitly.
        let names = (try? FileManager.default.contentsOfDirectory(atPath:store.directory.path)) ?? []
        guard !names.contains(where:{ $0.hasPrefix("workspaces-corrupt-") }) else { return }
        var retained = board
        retained.items.append(contentsOf:activity.retainedItems)
        store.collectGarbage(keeping:retained)
    }

    func textForCopy(_ items:[HangingItem]) async -> String {
        var values:[String] = []
        for item in items {
            if let text = item.text { values.append(text); continue }
            guard [.image,.screenshot].contains(item.kind),let reference = item.file else { continue }
            let files = self.files
            let resolved = await Task.detached(priority:.utility) { files.resolve(reference).url }.value
            if let resolved,let text = await ocr.text(for:resolved),!text.isEmpty { recognizedText[item.id] = text; values.append(text) }
        }
        return values.joined(separator:"\n\n")
    }

    var ropeItems:[HangingItem] {
        let items = visibleItems
        guard !isSearching else { return items }
        var seen:Set<UUID> = []
        return items.filter { item in
            guard let group = groups.first(where:{ $0.lineID == item.lineID && $0.itemIDs.contains(item.id) }),collapsedGroupIDs.contains(group.id) else { return true }
            return seen.insert(group.id).inserted
        }
    }
    func expandGroup(for item:HangingItem) -> Bool {
        guard let group = groups.first(where:{ $0.lineID == item.lineID && $0.itemIDs.contains(item.id) }),collapsedGroupIDs.contains(group.id) else { return false }
        collapsedGroupIDs.remove(group.id); return true
    }
    func groupDisplayName(for item:HangingItem) -> String? {
        guard let group = groups.first(where:{ $0.lineID == item.lineID && $0.itemIDs.contains(item.id) }) else { return nil }
        let count = board.items.filter { group.itemIDs.contains($0.id) && $0.lineID == group.lineID }.count
        return collapsedGroupIDs.contains(group.id) ? "\(group.name) · \(count) items" : group.name
    }

    func linePosition(forVisibleInsertion index:Int,movingIDs:Set<UUID> = []) -> Int {
        let remaining = board.activeItems.filter { !movingIDs.contains($0.id) }
        let following = ropeItems.dropFirst(max(0,index)).first { !movingIDs.contains($0.id) }
        guard let following else { return remaining.count }
        return remaining.firstIndex { $0.id == following.id } ?? remaining.count
    }
    func dragItems(for ids:Set<UUID>) -> [HangingItem] {
        var all = ids
        for group in groups where collapsedGroupIDs.contains(group.id) && !group.itemIDs.isDisjoint(with:ids) { all.formUnion(group.itemIDs) }
        return visibleItems.filter { all.contains($0.id) }
    }
    func dragRepresentativeID(for item:HangingItem) -> UUID {
        guard let group = groups.first(where:{ $0.lineID == item.lineID && $0.itemIDs.contains(item.id) }),collapsedGroupIDs.contains(group.id) else { return item.id }
        return ropeItems.first { group.itemIDs.contains($0.id) }?.id ?? item.id
    }

}
