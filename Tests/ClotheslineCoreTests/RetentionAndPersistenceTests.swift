import XCTest
@testable import ClotheslineCore

final class RetentionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func shot(_ name: String, _ line: UUID, ageHours: Double, pinned: Bool = false, kind: ItemKind = .screenshot) -> HangingItem {
        HangingItem(kind: kind, source: .screenshot, title: name, dateAdded: now.addingTimeInterval(-ageHours * 3600), lineID: line, pinned: pinned,
                    file: FileReference(path: "/s/\(name)", bookmark: nil, ownership: .referenced))
    }

    func testMaxScreenshotsRemovesOldestUnpinned() {
        var board = Board.makeDefault()
        let l = board.activeLineID
        let items = [shot("1", l, ageHours: 5), shot("2", l, ageHours: 4, pinned: true), shot("3", l, ageHours: 3), shot("4", l, ageHours: 2), shot("5", l, ageHours: 1)]
        items.forEach { board.add($0) }
        board.add(shot("img", l, ageHours: 10, kind: .image))
        let policy = RetentionPolicy(maxScreenshotsPerLine: 2)
        let removed = policy.itemsToRemove(from: board, now: now)
        // Unpinned screenshots: 1,3,4,5 -> keep newest two (4,5). Pinned and non-screenshots untouched.
        XCTAssertEqual(removed, Set([items[0].id, items[2].id]))
    }

    func testExpiryUsesStricterOfGlobalAndLine() {
        var board = Board.makeDefault()
        let l = board.activeLineID
        let temp = board.addLine(named: "Temporary", expiryHours: 1)
        let old = shot("old", l, ageHours: 30)
        let young = shot("young", l, ageHours: 2)
        let tempItem = shot("t", temp.id, ageHours: 2)
        let tempPinned = shot("tp", temp.id, ageHours: 2, pinned: true)
        [old, young, tempItem, tempPinned].forEach { board.add($0) }
        let policy = RetentionPolicy(maxScreenshotsPerLine: nil, expireAfterHours: 24)
        XCTAssertEqual(policy.itemsToRemove(from: board, now: now), Set([old.id, tempItem.id]))
    }

    func testNextExpiry() {
        var board = Board.makeDefault()
        let l = board.activeLineID
        board.add(shot("a", l, ageHours: 23))
        board.add(shot("b", l, ageHours: 1))
        let policy = RetentionPolicy(maxScreenshotsPerLine: nil, expireAfterHours: 24)
        XCTAssertEqual(policy.nextExpiry(in: board, after: now), now.addingTimeInterval(3600))
        XCTAssertNil(RetentionPolicy(maxScreenshotsPerLine: nil).nextExpiry(in: board, after: now))
    }

    func testRetentionCodingKeepsUnlimited() throws {
        let unlimited = RetentionPolicy(maxScreenshotsPerLine: nil, expireAfterHours: nil)
        let data = try JSONEncoder().encode(unlimited)
        XCTAssertEqual(try JSONDecoder().decode(RetentionPolicy.self, from: data), unlimited)
        // Missing keys fall back to defaults.
        let empty = try JSONDecoder().decode(RetentionPolicy.self, from: Data("{}".utf8))
        XCTAssertEqual(empty, RetentionPolicy())
    }
}

final class PersistenceTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("clothesline-tests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testFreshThenRoundTrip() throws {
        let store = BoardStore(directory: dir)
        guard case .fresh(var board) = store.load() else { return XCTFail("expected fresh") }
        board.add(HangingItem(kind: .link, source: .clipboard, title: "x", lineID: board.activeLineID, link: "https://example.com"))
        _ = board.addLine(named: "Work", expiryHours: 4)
        try store.save(board)
        guard case .loaded(let loaded) = store.load() else { return XCTFail("expected loaded") }
        XCTAssertEqual(loaded.items.count, 1)
        XCTAssertEqual(loaded.lines.map(\.name), ["Clothesline", "Work"])
        XCTAssertEqual(loaded.lines[1].expiryHours, 4)
        XCTAssertEqual(loaded.items[0].link, "https://example.com")
    }

    func testCorruptFileIsMovedAsideNotOverwritten() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = BoardStore(directory: dir)
        try Data("{ not json".utf8).write(to: store.stateURL)
        guard case .recovered(_, let backup) = store.load() else { return XCTFail("expected recovery") }
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), "{ not json")
    }

    func testOwnedFileDeletionIsConfinedToOwnedFolder() throws {
        let store = BoardStore(directory: dir)
        let owned = try store.makeOwnedFileURL(preferredName: "pic.png")
        try Data([1, 2, 3]).write(to: owned)
        // A referenced (user) file must never be deleted, even if marked owned by mistake.
        let outside = dir.appendingPathComponent("user-file.txt")
        try Data("keep".utf8).write(to: outside)
        XCTAssertFalse(store.deleteOwnedFile(FileReference(path: outside.path, bookmark: nil, ownership: .owned)))
        XCTAssertFalse(store.deleteOwnedFile(FileReference(path: owned.path, bookmark: nil, ownership: .referenced)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
        // Path traversal out of the owned folder is rejected.
        let sneaky = store.ownedFilesDirectory.appendingPathComponent("../user-file.txt").path
        XCTAssertFalse(store.deleteOwnedFile(FileReference(path: sneaky, bookmark: nil, ownership: .owned)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
        // The genuine owned copy is deleted along with its folder.
        XCTAssertTrue(store.deleteOwnedFile(FileReference(path: owned.path, bookmark: nil, ownership: .owned)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: owned.deletingLastPathComponent().path))
    }

    func testGarbageCollectionKeepsReferencedOwnedFiles() throws {
        let store = BoardStore(directory: dir)
        let keep = try store.makeOwnedFileURL(preferredName: "keep.png")
        let drop = try store.makeOwnedFileURL(preferredName: "drop.png")
        try Data([1]).write(to: keep)
        try Data([1]).write(to: drop)
        var board = Board.makeDefault()
        board.add(HangingItem(kind: .image, source: .drop, title: "keep", lineID: board.activeLineID,
                              file: FileReference(path: keep.path, bookmark: nil, ownership: .owned)))
        store.collectGarbage(keeping: board)
        XCTAssertTrue(FileManager.default.fileExists(atPath: keep.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: drop.path))
    }

    func testGarbageCollectionCanProtectRecentCopies() throws {
        let store = BoardStore(directory: dir)
        let recent = try store.makeOwnedFileURL(preferredName: "recent.png")
        let old = try store.makeOwnedFileURL(preferredName: "old.png")
        try Data([1]).write(to: recent)
        try Data([1]).write(to: old)
        let past = Date().addingTimeInterval(-30 * 86400)
        try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: old.deletingLastPathComponent().path)
        store.collectGarbage(keeping: Board.makeDefault(), protectingNewerThan: Date().addingTimeInterval(-7 * 86400))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recent.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
    }

    func testSanitizedFileName() {
        XCTAssertEqual(BoardStore.sanitizedFileName("a/b:c.png"), "a-b-c.png")
        XCTAssertEqual(BoardStore.sanitizedFileName("..hidden"), "hidden")
        XCTAssertEqual(BoardStore.sanitizedFileName("   "), "Item")
        let long = String(repeating: "x", count: 300) + ".png"
        XCTAssertTrue(BoardStore.sanitizedFileName(long).hasSuffix(".png"))
        XCTAssertLessThanOrEqual(BoardStore.sanitizedFileName(long).utf8.count, 200)
    }

    func testSettingsDecodingToleratesMissingKeysAndKeepsNone() throws {
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"theme":"midnight"}"#.utf8))
        XCTAssertEqual(decoded.theme, .midnight)
        XCTAssertEqual(decoded.toggleShortcut, .defaultToggle)
        var none = AppSettings()
        none.toggleShortcut = nil
        let roundTrip = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(none))
        XCTAssertNil(roundTrip.toggleShortcut)
        XCTAssertEqual(roundTrip, none)
    }

    func testShortcutDisplay() {
        XCTAssertEqual(Shortcut.defaultToggle.displayString, "⌃⌥C")
        XCTAssertFalse(Shortcut(keyCode: 0, modifiers: Shortcut.shift, keyLabel: "A").isValidGlobalShortcut)
    }
}
