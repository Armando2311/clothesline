import AppKit
import UniformTypeIdentifiers
import ClotheslineCore

/// Everything a user can do with items, including the file operations.
///
/// The wording in menus and alerts deliberately separates the two kinds of
/// "remove": *Remove from Line* forgets the item (the file is untouched), while
/// *Move File to Trash…* acts on the real file and always asks first.
@MainActor
final class ItemActions: NSObject {
    let model: AppModel
    weak var view: LineView?
    private var exportDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Clothesline Exports", isDirectory: true)
    }

    init(model: AppModel, view: LineView) {
        self.model = model
        self.view = view
    }

    // MARK: - Menus

    func menu(for items: [HangingItem]) -> NSMenu {
        let menu = NSMenu()
        guard !items.isEmpty else { return menu }
        let single = items.count == 1 ? items[0] : nil
        let fileItems = items.filter { $0.file != nil }
        let reachable = fileItems.filter { model.url(for: $0) != nil }
        let missing = single.flatMap { model.availability[$0.id] == .missing ? $0 : nil }

        add(menu, "Quick Look", #selector(quickLook), key: " ", modifiers: [])
        add(menu, single?.kind == .link ? "Open Link" : "Open", #selector(openSelected), key: "o", enabled: items.contains { $0.kind == .link || $0.kind == .text || model.url(for: $0) != nil })
        if !fileItems.isEmpty {
            add(menu, "Show in Finder", #selector(revealSelected), key: "r", enabled: !reachable.isEmpty)
        }
        add(menu, "Share…", #selector(shareSelected))
        add(menu, "Export with Recipe…", #selector(exportSelected))
        if let single {
            add(menu, "Rename Label…", #selector(renameSelected))
            if single.kind == .text { add(menu, "Edit Note…", #selector(editSelected)) }
            if [.image, .screenshot].contains(single.kind) { add(menu, "Prepare Image…", #selector(prepareSelected), enabled: !reachable.isEmpty) }
        }
        add(menu, "Copy", #selector(copySelected), key: "c")
        menu.addItem(.separator())

        if !reachable.isEmpty {
            add(menu, "Copy File\(reachable.count > 1 ? "s" : "") To…", #selector(copyFilesTo))
            let referenced = reachable.filter { $0.file?.ownership == .referenced }
            add(menu, "Move File\(reachable.count > 1 ? "s" : "") To…", #selector(moveFilesTo), enabled: !referenced.isEmpty)
        }
        if missing != nil {
            add(menu, "Locate File…", #selector(locate))
        }
        let allPinned = items.allSatisfy(\.pinned)
        add(menu, allPinned ? "Unpin" : "Pin (keep through cleanup)", #selector(togglePin), key: "p", modifiers: [])

        if model.board.lines.count > 1 {
            let moveItem = NSMenuItem(title: "Move to Line", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for line in model.board.moveDestinations(for: items) {
                let mi = NSMenuItem(title: line.name, action: #selector(moveToLine(_:)), keyEquivalent: "")
                mi.target = self
                mi.representedObject = line.id
                sub.addItem(mi)
            }
            moveItem.submenu = sub
            menu.addItem(moveItem)
        }
        menu.addItem(.separator())
        add(menu, items.count > 1 ? "Remove \(items.count) Items from Line" : "Remove from Line", #selector(removeSelected), key: "\u{8}", modifiers: [])
        let trashable = reachable.filter { $0.file?.ownership == .referenced }
        if !trashable.isEmpty {
            add(menu, "Move File\(trashable.count > 1 ? "s" : "") to Trash…", #selector(trashSelected))
        }
        return menu
    }

    func lineMenu() -> NSMenu {
        let menu = NSMenu()
        add(menu, "Hang Clipboard", #selector(hangClipboard), key: "v")
        add(menu, "New Note…", #selector(newNote))
        add(menu, "Add Files…", #selector(addFiles))
        menu.addItem(.separator())
        let sortItem = NSMenuItem(title: "Arrange By", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for order in Board.SortOrder.allCases {
            let mi = NSMenuItem(title: order.displayName, action: #selector(sort(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = order.rawValue
            sub.addItem(mi)
        }
        sortItem.submenu = sub
        menu.addItem(sortItem)
        add(menu, "Select All", #selector(selectAll), key: "a", enabled: !model.activeItems.isEmpty)
        add(menu, "Undo Remove", #selector(undoRemove), key: "z", enabled: model.canUndoRemoval)
        menu.addItem(.separator())
        let linesItem = NSMenuItem(title: "Lines", action: nil, keyEquivalent: "")
        linesItem.submenu = linesMenu()
        menu.addItem(linesItem)
        menu.addItem(.separator())
        add(menu, "Clear Line (keeps pinned)", #selector(clearLine), enabled: model.activeItems.contains { !$0.pinned })
        return menu
    }

    func linesMenu() -> NSMenu {
        let menu = NSMenu()
        for (i, line) in model.board.lines.enumerated() {
            var title = line.name
            if let h = line.expiryHours { title += "  (clears after \(Self.hoursText(h)))" }
            let mi = NSMenuItem(title: title, action: #selector(activateLine(_:)), keyEquivalent: i < 9 ? "\(i + 1)" : "")
            mi.target = self
            mi.representedObject = line.id
            mi.state = line.id == model.board.activeLineID ? .on : .off
            menu.addItem(mi)
        }
        menu.addItem(.separator())
        add(menu, "New Line…", #selector(newLine))
        add(menu, "New Temporary Line (clears after 24 hours)", #selector(newTemporaryLine))
        add(menu, "Rename “\(model.board.activeLine.name)”…", #selector(renameLine))
        add(menu, "Delete “\(model.board.activeLine.name)”", #selector(deleteLine), enabled: model.board.lines.count > 1)
        return menu
    }

    static func hoursText(_ h: Double) -> String {
        h >= 24 && h.truncatingRemainder(dividingBy: 24) == 0 ? "\(Int(h / 24)) day\(h == 24 ? "" : "s")" : "\(Int(h)) h"
    }

    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, key: String = "", modifiers: NSEvent.ModifierFlags = [.command], enabled: Bool = true) {
        let item = NSMenuItem(title: title, action: enabled ? action : nil, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = self
        item.isEnabled = enabled
        menu.addItem(item)
    }

    private var selected: [HangingItem] { view?.selectedItems ?? [] }

    // MARK: - Menu actions

    @objc private func quickLook() { view?.toggleQuickLook() }
    @objc private func shareSelected() { view?.workflow.share() }
    @objc private func exportSelected() { view?.workflow.export() }
    @objc private func renameSelected() { if let item = selected.first { view?.workflow.alias(item) } }
    @objc private func editSelected() { if let item = selected.first { view?.workflow.note(item) } }
    @objc private func prepareSelected() { if let item = selected.first { view?.workflow.prepare(item) } }
    @objc private func openSelected() { open(selected) }
    @objc private func revealSelected() { reveal(selected) }
    @objc private func copySelected() { _ = DragWriters.copyToPasteboard(selected, model: model) }
    @objc private func togglePin() { model.togglePinned(Set(selected.map(\.id))) }
    @objc private func removeSelected() { removeFromLine(selected) }
    @objc private func selectAll() { view?.select(Set(model.activeItems.map(\.id))) }
    @objc private func undoRemove() { model.undoLastRemoval() }
    @objc private func hangClipboard() { PasteboardImporter.importContents(of: .general, into: model, source: .clipboard) }
    @objc private func clearLine() { model.clearActiveLine() }

    @objc private func moveToLine(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        model.move(Set(selected.map(\.id)), toLine: id)
    }

    @objc private func activateLine(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        model.activate(lineID: id)
    }

    @objc private func sort(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let order = Board.SortOrder(rawValue: raw) else { return }
        model.sortActiveLine(by: order)
    }

    // MARK: - Operations

    func open(_ items: [HangingItem]) {
        for item in items {
            switch item.kind {
            case .link:
                if let link = item.link, let url = URL(string: link) { NSWorkspace.shared.open(url) }
            case .text:
                view?.workflow.note(item)
            default:
                if let url = model.url(for: item) { NSWorkspace.shared.open(url) } else { NSSound.beep() }
            }
        }
    }

    func reveal(_ items: [HangingItem]) {
        let urls = items.compactMap { model.url(for: $0) }
        guard !urls.isEmpty else { NSSound.beep(); return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    /// Removes items from the line only. Undoable with ⌘Z.
    func removeFromLine(_ items: [HangingItem]) {
        guard !items.isEmpty else { return }
        model.remove(Set(items.map(\.id)))
    }

    /// A URL Quick Look can show. Notes and links are written to a temporary
    /// export file (never into the user's folders).
    func previewURL(for item: HangingItem) -> URL? {
        switch item.kind {
        case .text:
            return exportFile(for: item) { url in try (item.text ?? "").write(to: url, atomically: true, encoding: .utf8) }
        case .link:
            guard let link = item.link else { return nil }
            return exportFile(for: item) { url in
                let plist: [String: String] = ["URL": link]
                let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                try data.write(to: url)
            }
        default:
            return model.url(for: item)
        }
    }

    private func exportFile(for item: HangingItem, write: (URL) throws -> Void) -> URL? {
        let dir = exportDirectory.appendingPathComponent(item.id.uuidString, isDirectory: true)
        let url = dir.appendingPathComponent(ItemClassifier.exportFileName(for: item))
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try write(url)
            return url
        } catch {
            return nil
        }
    }

    // MARK: - File operations (explicit, confirmed)

    private func chooseFolder(prompt: String, message: String) -> URL? {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.level = WorkflowPresentation.modalLevel
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
        panel.message = message
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// A destination path that never overwrites an existing file ("name 2.ext").
    static func uniqueDestination(for name: String, in folder: URL) -> URL {
        let fm = FileManager.default
        var candidate = folder.appendingPathComponent(name)
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var n = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent(ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)")
            n += 1
        }
        return candidate
    }

    @objc private func copyFilesTo() {
        let items = selected.filter { model.url(for: $0) != nil }
        guard !items.isEmpty, let folder = chooseFolder(prompt: "Copy Here", message: "Copies are made; the originals stay where they are.") else { return }
        var failures: [String] = []
        for item in items {
            guard let src = model.url(for: item) else { continue }
            do {
                try FileManager.default.copyItem(at: src, to: Self.uniqueDestination(for: src.lastPathComponent, in: folder))
            } catch {
                failures.append("\(src.lastPathComponent): \(error.localizedDescription)")
            }
        }
        report(failures, verb: "copied")
    }

    @objc private func moveFilesTo() {
        let items = selected.filter { model.url(for: $0) != nil && $0.file?.ownership == .referenced }
        guard !items.isEmpty, let folder = chooseFolder(prompt: "Move Here", message: "The files will be moved out of their current folders.") else { return }
        let alert = NSAlert()
        alert.window.level = WorkflowPresentation.modalLevel
        alert.messageText = items.count == 1 ? "Move “\(items[0].file?.fileName ?? items[0].title)” to “\(folder.lastPathComponent)”?" : "Move \(items.count) files to “\(folder.lastPathComponent)”?"
        alert.informativeText = "The files will no longer be in their current folders. They stay on the line at their new location."
        alert.addButton(withTitle: "Move")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        var failures: [String] = []
        for item in items {
            guard let src = model.url(for: item) else { continue }
            let dest = Self.uniqueDestination(for: src.lastPathComponent, in: folder)
            do {
                try FileManager.default.moveItem(at: src, to: dest)
                model.updateReference(item.id, to: dest)
            } catch {
                failures.append("\(src.lastPathComponent): \(error.localizedDescription)")
            }
        }
        report(failures, verb: "moved")
    }

    @objc private func trashSelected() {
        let items = selected.filter { model.url(for: $0) != nil && $0.file?.ownership == .referenced }
        guard !items.isEmpty else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.window.level = WorkflowPresentation.modalLevel
        alert.alertStyle = .warning
        alert.messageText = items.count == 1 ? "Move “\(items[0].file?.fileName ?? items[0].title)” to the Trash?" : "Move \(items.count) files to the Trash?"
        alert.informativeText = "This moves the actual file\(items.count == 1 ? "" : "s") on your Mac to the Trash, not just the item on the line. You can put \(items.count == 1 ? "it" : "them") back from the Trash."
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let urls = items.compactMap { model.url(for: $0) }
        NSWorkspace.shared.recycle(urls) { [weak self] trashed, error in
            Task { @MainActor in
                guard let self else { return }
                let trashedPaths = Set(trashed.keys.map(\.path))
                let ids = items.filter { item in self.model.url(for: item).map { trashedPaths.contains($0.path) } ?? false }.map(\.id)
                self.model.remove(Set(ids), style: .unclip, undoable: false)
                if let error { self.report(["\(error.localizedDescription)"], verb: "moved to the Trash") }
            }
        }
    }

    @objc private func locate() {
        guard let item = selected.first else { return }
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.level = WorkflowPresentation.modalLevel
        panel.canChooseFiles = item.kind != .folder
        panel.canChooseDirectories = item.kind == .folder
        panel.message = "Find “\(item.file?.fileName ?? item.title)”"
        panel.prompt = "Use This"
        if panel.runModal() == .OK, let url = panel.url {
            model.updateReference(item.id, to: url)
        }
    }

    private func report(_ failures: [String], verb: String) {
        guard !failures.isEmpty else { return }
        let alert = NSAlert()
        alert.window.level = WorkflowPresentation.modalLevel
        alert.messageText = "Some files couldn’t be \(verb)."
        alert.informativeText = failures.prefix(6).joined(separator: "\n")
        alert.runModal()
    }

    // MARK: - Adding

    @objc func addFiles() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.level = WorkflowPresentation.modalLevel
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Hang"
        panel.message = "Choose files or folders to hang on the line. They stay where they are."
        if panel.runModal() == .OK {
            model.hang(fileURLs: panel.urls, source: .manual)
        }
    }

    @objc func newNote() {
        view?.workflow.note(nil)
    }

    @objc private func newLine() {
        guard let name = TextPrompt.run(title: "New Line", message: "Name the new clothesline.", initial: "") else { return }
        model.addLine(named: name)
    }

    @objc private func newTemporaryLine() {
        model.addLine(named: "Temporary", expiryHours: 24)
    }

    @objc private func renameLine() {
        let line = model.board.activeLine
        guard let name = TextPrompt.run(title: "Rename Line", message: "", initial: line.name) else { return }
        model.renameLine(line.id, to: name)
    }

    @objc private func deleteLine() {
        let line = model.board.activeLine
        let alert = NSAlert()
        alert.window.level = WorkflowPresentation.modalLevel
        alert.messageText = "Delete the line “\(line.name)”?"
        alert.informativeText = "Its items move to another line. No files are affected."
        alert.addButton(withTitle: "Delete Line")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { model.deleteLine(line.id) }
    }
}

/// A small modal text prompt built on NSAlert.
@MainActor
enum TextPrompt {
    static func run(title: String, message: String, initial: String, multiline: Bool = false) -> String? {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.window.level = WorkflowPresentation.modalLevel
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let result: String?
        if multiline {
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
            scroll.hasVerticalScroller = true
            scroll.borderType = .bezelBorder
            let text = NSTextView(frame: scroll.bounds)
            text.isRichText = false
            text.font = .systemFont(ofSize: 13)
            text.string = initial
            text.autoresizingMask = [.width]
            scroll.documentView = text
            alert.accessoryView = scroll
            alert.window.initialFirstResponder = text
            result = alert.runModal() == .alertFirstButtonReturn ? text.string : nil
        } else {
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
            field.stringValue = initial
            alert.accessoryView = field
            alert.window.initialFirstResponder = field
            result = alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
        }
        guard let r = result?.trimmingCharacters(in: .whitespacesAndNewlines), !r.isEmpty else { return nil }
        return r
    }
}
