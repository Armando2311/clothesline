import XCTest
import AppKit
import ClotheslineCore
@testable import Clothesline

/// Regressions for idle cost, redraw cost and privacy retention.
final class EfficiencyPrivacyTests: XCTestCase {
    @MainActor func testClickThroughPointerTrackingRunsOnlyWhenEnabled() {
        withModel { model, _ in
            let controller = PanelController(model: model)
            defer { controller.hide(); controller.panel.orderOut(nil) }
            controller.show(.explicit)
            XCTAssertFalse(controller.isTrackingPointerForClickThrough, "default theme: no pointer tracking while the line is open")
            model.settings.theme = .noTheme
            controller.refreshLayout()
            XCTAssertFalse(controller.isTrackingPointerForClickThrough, "No Theme without click-through: still nothing")
            model.settings.noThemeClickThrough = true
            controller.refreshLayout()
            XCTAssertTrue(controller.isTrackingPointerForClickThrough)
            controller.hide()
            XCTAssertFalse(controller.isTrackingPointerForClickThrough, "hidden line: monitors removed")
            XCTAssertFalse(controller.panel.ignoresMouseEvents)
        }
    }

    @MainActor func testFolderWatcherOnlyRunsWhileAFolderRuleIsEnabled() throws {
        try withModel { model, root in
            let watcher = FolderRuleWatcher(model: model)
            defer { watcher.stop() }
            watcher.start()
            spin()
            XCTAssertFalse(watcher.isWatching, "no rules: nothing watches the disk")
            let folder = root.appendingPathComponent("Inbox", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var rule = CollectionRule(name: "Inbox", lineID: model.board.activeLineID, source: .manual, folderPath: folder.path)
            model.activity.upsert(rule)
            spin()
            XCTAssertTrue(watcher.isWatching)
            rule.enabled = false
            model.activity.upsert(rule)
            spin()
            XCTAssertFalse(watcher.isWatching, "paused rule: stream stopped")
        }
    }

    @MainActor func testFolderWatcherCollectsANewFileWithoutPolling() throws {
        try withModel { model, root in
            let folder = root.appendingPathComponent("Drop", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            model.activity.upsert(CollectionRule(name: "Drop", lineID: model.board.activeLineID, source: .manual, folderPath: folder.path))
            let watcher = FolderRuleWatcher(model: model)
            defer { watcher.stop() }
            watcher.start()
            spin(0.5)
            let file = folder.appendingPathComponent("report.pdf")
            try Data("%PDF".utf8).write(to: file)
            // FSEvents (1 s latency) + two stable observations >= 2 s apart.
            let deadline = Date().addingTimeInterval(12)
            while Date() < deadline && model.board.items.isEmpty { spin(0.25) }
            XCTAssertEqual(model.board.items.first?.file?.fileName, "report.pdf")
        }
    }

    @MainActor func testResizingTheLineRedrawsNoArtwork() {
        withModel { model, _ in
            let view = LineView(model: model)
            view.configure(notchCenterX: nil, canvasWidth: 1500)
            view.frame.size = NSSize(width: 700, height: 210)
            for i in 0..<6 { _ = model.createNote("Note \(i)") }
            spin()
            view.relayout(animated: false)
            let cards = view.cardRenderCount, sky = view.skyArtRenderCount
            XCTAssertGreaterThan(cards, 0)
            view.setFrameSize(NSSize(width: 820, height: 210))
            view.setFrameSize(NSSize(width: 980, height: 210))
            XCTAssertEqual(view.cardRenderCount, cards, "cards are fixed-size bitmaps; a resize must not redraw them")
            XCTAssertEqual(view.skyArtRenderCount, sky, "the sky is drawn at display width once")
        }
    }

    @MainActor func testClearingHistoryReleasesOwnedCopiesAndRecognizedText() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let cache = root.appendingPathComponent("ocr.json")
        let index = OCRIndex(cacheURL: cache, recognizer: { _ in "secret text" })
        let store = BoardStore(directory: root.appendingPathComponent("state"))
        let model = AppModel(store: store, ocrIndex: index)
        let url = try store.makeOwnedFileURL(preferredName: "pasted.png")
        let image = NSImage(size: NSSize(width: 20, height: 20), flipped: false) { r in NSColor.white.setFill(); r.fill(); return true }
        try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation))?.representation(using: .png, properties: [:])).write(to: url)
        let id = try XCTUnwrap(model.hang(fileURLs: [url], source: .clipboard, ownership: .owned).first)
        let text = await model.textForCopy(model.activeItems)
        XCTAssertEqual(text, "secret text")
        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.path))

        model.remove([id], undoable: false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "restorable for the history window")

        await model.clearHistoryAndRecognizedText()
        XCTAssertTrue(model.activity.history.isEmpty)
        XCTAssertTrue(model.recognizedText.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path), "recognized text is deleted from disk")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "owned copy only history kept is deleted")
    }

    @MainActor func testRecognizedTextIsPrunedWhenItsImageLeavesTheLine() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let cache = root.appendingPathComponent("ocr.json")
        let index = OCRIndex(cacheURL: cache, recognizer: { _ in "card number 4242" })
        let model = AppModel(store: BoardStore(directory: root.appendingPathComponent("state")), ocrIndex: index)
        var ids: [UUID] = []
        for name in ["a.png", "b.png"] {
            let url = root.appendingPathComponent(name)
            let image = NSImage(size: NSSize(width: 20, height: 20), flipped: false) { r in NSColor.white.setFill(); r.fill(); return true }
            try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation))?.representation(using: .png, properties: [:])).write(to: url)
            ids += model.hang(fileURLs: [url], source: .drop)
        }
        _ = await model.textForCopy(model.activeItems)
        XCTAssertEqual(try cachedKeys(cache).count, 2)
        model.remove([ids[0]], undoable: false)
        model.pruneRecognizedText()
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline, (try? cachedKeys(cache).count) != 1 { try await Task.sleep(nanoseconds: 50_000_000) }
        let keys = try cachedKeys(cache)
        XCTAssertEqual(keys.count, 1)
        XCTAssertTrue(keys.first?.hasSuffix("b.png") == true)
        XCTAssertNil(model.recognizedText[ids[0]])
    }

    @MainActor func testHistoryWritesAreCoalesced() {
        withModel { model, _ in
            let before = model.activity.historyWrites
            for i in 0..<20 { _ = model.createNote("Burst \(i)") }
            XCTAssertEqual(model.activity.historyWrites, before, "a burst of additions is not written 20 times")
            model.activity.flush()
            XCTAssertEqual(model.activity.historyWrites, before + 1)
            XCTAssertEqual(model.activity.history.count, 20)
        }
    }

    // MARK: - Helpers

    private func cachedKeys(_ url: URL) throws -> [String] {
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        return Array((object ?? [:]).keys)
    }

    @MainActor private func spin(_ seconds: TimeInterval = 0.2) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    @MainActor private func withModel(_ run: (AppModel, URL) throws -> Void) rethrows {
        let defaults = UserDefaults.standard
        let saved = defaults.data(forKey: "settings.v1")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: root)
            if let saved { defaults.set(saved, forKey: "settings.v1") } else { defaults.removeObject(forKey: "settings.v1") }
        }
        let model = AppModel(store: BoardStore(directory: root.appendingPathComponent("state")))
        model.settings = AppSettings()
        try run(model, root)
    }
}
