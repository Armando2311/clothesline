import XCTest
@testable import ClotheslineCore

final class WorkspaceTests: XCTestCase {
    func testRoutingUsesOnlyEnabledMatchingRulesAndExistingTargets() {
        let fallback = UUID(), target = UUID()
        var state = WorkspaceState()
        state.rules = [CollectionRule(name: "Images", lineID: target, source: .manual, kind: .image, folderPath: "/tmp/selected")]
        XCTAssertEqual(state.destination(for: URL(fileURLWithPath: "/tmp/selected/photo.png"), source: .manual, kind: .image, defaultLineID: fallback, validLineIDs: [fallback,target]), target)
        XCTAssertEqual(state.destination(for: URL(fileURLWithPath: "/tmp/selected/nested/photo.png"), source: .manual, kind: .image, defaultLineID: fallback, validLineIDs: [fallback,target]), fallback)
        XCTAssertEqual(state.destination(for: nil, source: .drop, kind: .image, defaultLineID: fallback, validLineIDs: [fallback,target]), fallback)
        state.rules[0].enabled = false
        XCTAssertEqual(state.destination(for: URL(fileURLWithPath: "/tmp/selected/photo.png"), source: .manual, kind: .image, defaultLineID: fallback, validLineIDs: [fallback,target]), fallback)
    }
    func testHistoryKeepsSnapshotsBoundedAndSurvivesReload() throws {
        var state = WorkspaceState()
        let item = HangingItem(kind: .text, source: .manual, title: "Original", lineID: UUID(), text: "Keep me")
        for _ in 0..<205 { state.record(ActivityEntry(action: .removed, items: [item])) }
        let reloaded = try JSONDecoder().decode(WorkspaceState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(reloaded.history.count, 200)
        XCTAssertEqual(reloaded.history.first?.items.first?.text, "Keep me")
        XCTAssertEqual(reloaded.retainedItems.map(\.id), [item.id])
    }
    func testOnlyRemovalsAndExportsRetainOwnedCopies() {
        var state = WorkspaceState()
        var item = HangingItem(kind: .image, source: .clipboard, title: "Copy", lineID: UUID(), file: FileReference(path: "/owned/first.png", bookmark: nil, ownership: .owned))
        state.record(ActivityEntry(action: .added, items: [item]))
        XCTAssertTrue(state.retainedItems.isEmpty, "an addition must not keep a copy alive")
        item.file = FileReference(path: "/owned/second.png", bookmark: nil, ownership: .owned)
        state.record(ActivityEntry(action: .removed, items: [item]))
        XCTAssertEqual(Set(state.retainedItems.compactMap { $0.file?.path }), ["/owned/second.png"])
    }
    func testAdditionsAreLoggedWithoutContent() {
        let note = HangingItem(kind: .text, source: .clipboard, title: "Password is hunter2", lineID: UUID(), text: "Password is hunter2")
        let link = HangingItem(kind: .link, source: .drop, title: "Secret doc", lineID: UUID(), link: "https://example.com/private?token=abc")
        let file = HangingItem(kind: .image, source: .drop, title: "photo", lineID: UUID(), file: FileReference(path: "/Users/me/photo.png", bookmark: Data([1]), ownership: .referenced))
        let entry = ActivityEntry(action: .added, items: [note, link, file])
        XCTAssertEqual(entry.items.map(\.title), ["Note", "example.com", "photo"])
        XCTAssertTrue(entry.items.allSatisfy { $0.text == nil && $0.link == nil && $0.file == nil })
        XCTAssertEqual(entry.items.map(\.id), [note.id, link.id, file.id])
        // Removals keep full snapshots so they can be restored.
        XCTAssertEqual(ActivityEntry(action: .removed, items: [note]).items.first?.text, "Password is hunter2")
    }
    func testHistoryExpiresAfterRetentionWindow() throws {
        var state = WorkspaceState()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let item = HangingItem(kind: .text, source: .manual, title: "x", lineID: UUID(), text: "x")
        state.history = [ActivityEntry(date: now.addingTimeInterval(-8 * 86400), action: .removed, items: [item])]
        state.record(ActivityEntry(date: now.addingTimeInterval(-60), action: .removed, items: [item]), now: now)
        XCTAssertEqual(state.history.count, 1)
        XCTAssertFalse(state.prune(now: now))
        XCTAssertTrue(state.prune(now: now.addingTimeInterval(WorkspaceState.retention)))
        XCTAssertTrue(state.history.isEmpty)
    }
    func testHistoryAndSettingsAreStoredSeparatelyAndLegacyHistoryMigrates() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let item = HangingItem(kind: .text, source: .manual, title: "x", lineID: UUID(), text: "x")
        var legacy = WorkspaceState()
        legacy.rules = [CollectionRule(name: "R", lineID: UUID())]
        legacy.history = [ActivityEntry(action: .removed, items: [item])]
        let store = WorkspacePersistence(directory: directory)
        try JSONEncoder().encode(legacy).write(to: store.url)          // old single-file layout
        XCTAssertEqual(try store.load(), legacy)
        try store.save(legacy)
        let settingsOnly = try JSONDecoder().decode(WorkspaceState.self, from: Data(contentsOf: store.url))
        XCTAssertTrue(settingsOnly.history.isEmpty, "history must not be duplicated into workspaces.json")
        XCTAssertEqual(try WorkspacePersistence(directory: directory).load(), legacy)
        // Saving only history leaves the settings file byte-for-byte unchanged.
        let before = try Data(contentsOf: store.url)
        var changed = legacy; changed.history = []
        try store.save(changed, parts: .history)
        XCTAssertEqual(try Data(contentsOf: store.url), before)
        XCTAssertTrue(try WorkspacePersistence(directory: directory).load().history.isEmpty)
    }
    func testSettingsOnlySaveMigratesLegacyHistoryFirst() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var legacy = WorkspaceState()
        legacy.history = [ActivityEntry(action: .removed, items: [HangingItem(kind: .text, source: .manual, title: "x", lineID: UUID(), text: "x")])]
        let store = WorkspacePersistence(directory: directory)
        try JSONEncoder().encode(legacy).write(to: store.url)
        var state = try store.load()
        state.rules = [CollectionRule(name: "New", lineID: UUID())]
        try store.save(state, parts: .settings)
        XCTAssertEqual(try WorkspacePersistence(directory: directory).load(), state, "a settings edit must not drop history that only lived in workspaces.json")
    }
    func testOneDamagedFileKeepsTheOtherHalf() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var state = WorkspaceState()
        state.rules = [CollectionRule(name: "Keep", lineID: UUID())]
        state.history = [ActivityEntry(action: .removed, items: [HangingItem(kind: .text, source: .manual, title: "x", lineID: UUID(), text: "x")])]
        try WorkspacePersistence(directory: directory).save(state)
        let damagedHistory = WorkspacePersistence(directory: directory)
        try Data("broken".utf8).write(to: damagedHistory.historyURL)
        let (loaded, failure) = damagedHistory.loadRecovering()
        XCTAssertNotNil(failure)
        XCTAssertEqual(loaded.rules, state.rules)
        XCTAssertTrue(loaded.history.isEmpty)
        try damagedHistory.save(loaded)
        XCTAssertEqual(try WorkspacePersistence(directory: directory).load().rules, state.rules)

        let damagedSettings = WorkspacePersistence(directory: directory)
        try damagedSettings.save(state)
        try Data("broken".utf8).write(to: damagedSettings.url)
        let (recovered, settingsFailure) = WorkspacePersistence(directory: directory).loadRecovering()
        XCTAssertNotNil(settingsFailure)
        XCTAssertTrue(recovered.rules.isEmpty)
        XCTAssertEqual(recovered.history, state.history)
    }
    func testDamagedHistoryHoldsOwnedCopiesForOneRestoreWindowFromDiscovery() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = WorkspacePersistence(directory: directory)
        XCTAssertFalse(WorkspacePersistence.holdsOwnedCopies(in: directory))
        // Last written long ago: the hold still counts from when it was found.
        try Data("broken".utf8).write(to: store.historyURL)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-90 * 86400)], ofItemAtPath: store.historyURL.path)
        _ = store.loadRecovering()
        XCTAssertTrue(WorkspacePersistence.holdsOwnedCopies(in: directory))
        XCTAssertFalse(WorkspacePersistence.holdsOwnedCopies(in: directory, now: Date().addingTimeInterval(WorkspaceState.retention + 60)))
    }
    func testWorkspaceArrangementSurvivesPersistence() throws {
        let config = WorkspaceConfiguration(lineID: UUID(), sortOrder: .kind)
        let loaded = try JSONDecoder().decode(WorkspaceConfiguration.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(loaded.sortOrder, .kind)
    }
    func testOldEmptyStateDecodesDefaults() throws {
        let state = try JSONDecoder().decode(WorkspaceState.self, from: Data("{}".utf8))
        XCTAssertTrue(state.rules.isEmpty)
        XCTAssertTrue(state.configurations.isEmpty)
        XCTAssertTrue(state.history.isEmpty)
    }
    func testSavingDoesNotOverwriteAnUnquarantinedCorruptFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = WorkspacePersistence(directory: directory)
        let contents = Data("corrupt snapshot".utf8)
        try contents.write(to: store.url)
        XCTAssertThrowsError(try store.save(WorkspaceState()))
        XCTAssertEqual(try Data(contentsOf: store.url), contents)
    }
    func testCorruptPersistenceIsPreservedAndDefaultsRemainCompatible() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = WorkspacePersistence(directory: directory)
        try Data("broken".utf8).write(to: store.url)
        XCTAssertThrowsError(try store.load())
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(try Data(contentsOf: files[0]), Data("broken".utf8))
        var state = WorkspaceState()
        let id = UUID()
        state.configurations = [WorkspaceConfiguration(lineID: id, destinationPath: "/tmp/export", exportPresetID: UUID(), organization: "Client")]
        try store.save(state)
        XCTAssertEqual(try store.load(), state)
        let legacy = try JSONDecoder().decode(WorkspaceConfiguration.self, from: Data("{\"lineID\":\"\(id.uuidString)\"}".utf8))
        XCTAssertEqual(legacy.organization, "")
    }
    func testMissingReferencedOriginalIsStillAReferenceSnapshot() {
        let item = HangingItem(kind: .image, source: .drop, title: "Gone", lineID: UUID(), file: FileReference(path: "/missing/original.png", bookmark: nil, ownership: .referenced))
        let entry = ActivityEntry(action: .removed, items: [item])
        XCTAssertTrue(entry.canRestore)
        XCTAssertEqual(entry.items[0].file?.ownership, .referenced)
        XCTAssertFalse(FileManager.default.fileExists(atPath: entry.items[0].file!.path))
    }
    func testWatcherWaitsForStableWriteAndDeduplicatesAcrossRestart() {
        var tracker = FolderFileTracker()
        let time = Date(timeIntervalSince1970: 100)
        XCTAssertFalse(tracker.observe(path: "/tmp/a.png", size: 10, modified: time, now: time))
        XCTAssertFalse(tracker.observe(path: "/tmp/a.png", size: 20, modified: time.addingTimeInterval(1), now: time.addingTimeInterval(1)))
        XCTAssertTrue(tracker.observe(path: "/tmp/a.png", size: 20, modified: time.addingTimeInterval(1), now: time.addingTimeInterval(4)))
        tracker.markCollected(path: "/tmp/a.png", size: 20, modified: time.addingTimeInterval(1))
        var restarted = FolderFileTracker(collected: tracker.collected)
        XCTAssertFalse(restarted.observe(path: "/tmp/a.png", size: 20, modified: time.addingTimeInterval(1), now: time.addingTimeInterval(10)))
    }
}
