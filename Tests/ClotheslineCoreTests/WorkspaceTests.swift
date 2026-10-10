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
    func testHistoryRetainsEachOwnedSnapshotWhenReferenceChanges() {
        var state = WorkspaceState()
        var item = HangingItem(kind: .image, source: .clipboard, title: "Copy", lineID: UUID(), file: FileReference(path: "/owned/first.png", bookmark: nil, ownership: .owned))
        state.record(ActivityEntry(action: .added, items: [item]))
        item.file = FileReference(path: "/owned/second.png", bookmark: nil, ownership: .owned)
        state.record(ActivityEntry(action: .removed, items: [item]))
        XCTAssertEqual(Set(state.retainedItems.compactMap { $0.file?.path }), ["/owned/first.png", "/owned/second.png"])
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
