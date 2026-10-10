import AppKit
import UniformTypeIdentifiers
import ClotheslineCore

/// `Clothesline --self-test`: exercises the AppKit-dependent file paths with
/// real files, real bookmarks and real pasteboards, then exits non-zero on any
/// failure. Runs in CI on every push; nothing outside a temp folder is touched.
@MainActor
enum SelfTest {
    private static var failures = 0

    private static func check(_ condition: @autoclosure () -> Bool, _ name: String) {
        if condition() {
            print("PASS  \(name)")
        } else {
            failures += 1
            print("FAIL  \(name)")
        }
    }

    private static func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    static func run() -> Int32 {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("clothesline-selftest-\(UUID().uuidString)", isDirectory: true)
        let userFiles = root.appendingPathComponent("User Files", isDirectory: true)
        let stateDir = root.appendingPathComponent("State", isDirectory: true)
        try? fm.createDirectory(at: userFiles, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let savedSettings = UserDefaults.standard.data(forKey: "settings.v1")
        defer {
            if let savedSettings { UserDefaults.standard.set(savedSettings, forKey: "settings.v1") } else { UserDefaults.standard.removeObject(forKey: "settings.v1") }
        }

        let store = BoardStore(directory: stateDir)
        let model = AppModel(store: store)
        let original = userFiles.appendingPathComponent("Report.pdf")
        try? Data("%PDF-1.4 test".utf8).write(to: original)

        // 1. Dropping a file hangs a reference: no copy, original untouched.
        let pb = NSPasteboard(name: NSPasteboard.Name("app.clothesline.selftest.\(UUID().uuidString)"))
        pb.clearContents()
        pb.writeObjects([original as NSURL])
        let ids = PasteboardImporter.importContents(of: pb, into: model, source: .drop)
        let item = ids.first.flatMap { model.board.item($0) }
        check(item?.file?.ownership == .referenced, "file drop is hung by reference")
        check(item?.file?.path == original.path, "reference points at the original path")
        check(item?.kind == .pdf, "PDF is recognised")
        check(item?.file?.bookmark != nil, "bookmark data stored")
        check((try? fm.contentsOfDirectory(atPath: store.ownedFilesDirectory.path))?.isEmpty ?? true, "no copy made in Clothesline's folder")

        // 2. Same file again is not hung twice.
        pb.clearContents()
        pb.writeObjects([original as NSURL])
        check(PasteboardImporter.importContents(of: pb, into: model, source: .drop).isEmpty, "duplicate drop ignored")

        // 3. Image data becomes an owned copy.
        let image = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { r in NSColor.systemPink.setFill(); r.fill(); return true }
        pb.clearContents()
        pb.setData(image.tiffRepresentation, forType: .tiff)
        let imageID = PasteboardImporter.importContents(of: pb, into: model, source: .clipboard).first
        let imageItem = imageID.flatMap { model.board.item($0) }
        check(imageItem?.file?.ownership == .owned, "pasted image is an owned copy")
        check(imageItem.map { store.isInsideOwnedDirectory($0.file!.path) && fm.fileExists(atPath: $0.file!.path) } ?? false, "owned copy saved inside Clothesline's folder")
        check(imageItem?.kind == .image, "pasted image kind")

        // 4. Text and links.
        pb.clearContents()
        pb.setString("https://example.com/page", forType: .string)
        let linkID = PasteboardImporter.importContents(of: pb, into: model, source: .clipboard).first
        check(linkID.flatMap { model.board.item($0) }?.kind == .link, "single URL string becomes a link")
        pb.clearContents()
        pb.setString("Buy milk\nand bread", forType: .string)
        let noteID = PasteboardImporter.importContents(of: pb, into: model, source: .clipboard).first
        check(noteID.flatMap { model.board.item($0) }?.kind == .text, "text becomes a note")

        // 5. Drag-out writers produce real representations.
        if let item {
            let out = NSPasteboard(name: NSPasteboard.Name("app.clothesline.selftest.out.\(UUID().uuidString)"))
            out.clearContents()
            out.writeObjects([DragWriters.writer(for: item, model: model)!])
            let urls = out.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
            check(urls?.first?.standardizedFileURL.path == original.standardizedFileURL.path, "dragging a file out provides the real file URL")
        }
        if let noteID, let note = model.board.item(noteID) {
            let out = NSPasteboard(name: NSPasteboard.Name("app.clothesline.selftest.note.\(UUID().uuidString)"))
            out.clearContents()
            out.writeObjects([DragWriters.writer(for: note, model: model)!])
            check(out.string(forType: .string) == "Buy milk\nand bread", "dragging a note out provides its text")
            let types = out.types ?? []
            check(types.contains { $0.rawValue.contains("promise") || $0.rawValue == "com.apple.NSFilePromiseItemMetaData" || $0.rawValue == "com.apple.pasteboard.promised-file-content-type" }, "dragging a note out offers a file promise for Finder")
        }
        if let linkID, let link = model.board.item(linkID) {
            let out = NSPasteboard(name: NSPasteboard.Name("app.clothesline.selftest.link.\(UUID().uuidString)"))
            out.clearContents()
            out.writeObjects([DragWriters.writer(for: link, model: model)!])
            check(out.string(forType: .URL) == "https://example.com/page", "dragging a link out provides public.url")
        }

        // 6. Removing never touches originals; history retains owned copies.
        if let item, let imageItem {
            model.remove([item.id, imageItem.id])
            check(fm.fileExists(atPath: original.path), "removing a referenced item leaves the file")
            check(fm.fileExists(atPath: imageItem.file!.path), "owned copy kept while removal can be undone")
            model.undoLastRemoval()
            check(model.board.item(item.id) != nil && model.board.item(imageItem.id) != nil, "undo restores removed items")
            model.remove([imageItem.id], undoable: false)
            check(fm.fileExists(atPath: imageItem.file!.path), "owned copy retained for persistent history after final removal")
            if let entry = model.activity.history.first(where: { $0.action == .removed && $0.items.contains(where: { $0.id == imageItem.id }) }) {
                model.restoreActivity(entry)
                check(model.board.item(imageItem.id) != nil,"history restores an owned copy after final removal")
                model.remove([imageItem.id],undoable:false)
            }
        }

        // 7. Bookmarks follow a rename; deletion is detected as missing.
        if let item {
            let renamed = userFiles.appendingPathComponent("Report (final).pdf")
            try? fm.moveItem(at: original, to: renamed)
            model.revalidate(ids: [item.id])
            spin(1.0)
            let updated = model.board.item(item.id)
            check(updated?.file?.path == renamed.path, "reference follows a rename (bookmark)")
            check(model.availability[item.id] == .available, "renamed file still available")
            try? fm.removeItem(at: renamed)
            model.revalidate(ids: [item.id])
            spin(1.0)
            check(model.availability[item.id] == .missing, "deleted file is reported missing")
            check(model.board.item(item.id) != nil, "missing file stays on the line")
        }

        // 8. State survives a relaunch.
        model.saveNow()
        let reloaded = AppModel(store: BoardStore(directory: stateDir))
        check(reloaded.board.items.map(\.id) == model.board.items.map(\.id), "items restored after relaunch, in order")

        // 9. Copy-to never overwrites.
        let dupe = userFiles.appendingPathComponent("a.txt")
        try? Data("1".utf8).write(to: dupe)
        check(ItemActions.uniqueDestination(for: "a.txt", in: userFiles).lastPathComponent == "a 2.txt", "copy destination avoids overwriting")

        // 10. Classification of real files on disk.
        let shot = userFiles.appendingPathComponent("shot.png")
        try? Data([0x89, 0x50, 0x4E, 0x47]).write(to: shot)
        check(ScreenshotWatcher.screenCaptureAttribute(at: shot.path) == false, "plain file has no screen-capture attribute")
        _ = shot.path.withCString { p in setxattr(p, "com.apple.metadata:kMDItemIsScreenCapture", "1", 1, 0, 0) }
        check(ScreenshotWatcher.screenCaptureAttribute(at: shot.path) == true, "screen-capture attribute detected")

        print(failures == 0 ? "Self-test passed." : "Self-test: \(failures) failure(s).")
        return failures == 0 ? 0 : 1
    }
}
