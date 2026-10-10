import AppKit
import SwiftUI
import ClotheslineCore

@MainActor
final class WorkflowActions: NSObject, NSWindowDelegate {
    let model: AppModel
    weak var view: LineView?
    private var windows: [String: NSWindow] = [:]
    private var sharePicker: NSSharingServicePicker?
    init(model: AppModel, view: LineView) { self.model = model; self.view = view; super.init() }
    func present<Content: View>(_ title: String, key: String, size: CGSize, @ViewBuilder content: () -> Content) {
        let window = windows[key] ?? NSWindow(contentRect: CGRect(origin: .zero,size: size), styleMask: [.titled,.closable,.miniaturizable,.resizable], backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        window.delegate = self
        window.title = title; window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: content())
        window.setContentSize(size); window.center(); windows[key] = window
        NSApp.activate(ignoringOtherApps: true); Motion.present(window)
    }
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        windows = windows.filter { $0.value !== window }
        window.contentViewController = nil
    }
    func perform(_ action: LineAction, from anchor: NSView? = nil) {
        switch action {
        case .history:
            present("Activity History",key:"history",size:CGSize(width:740,height:540)) {
                ActivityHistoryView(model:model,repeatExport:{ entry in
                    self.present("Export Again",key:"export",size:CGSize(width:730,height:680)) { RecipeView(model:self.model,items:entry.items,initialOptions:entry.recipeOptions) }
                })
            }
        case .workspace: present("Workspace",key:"workspace",size:CGSize(width:660,height:540)) { WorkspaceView(model:model) }
        case .rules: present("Collection Rules",key:"rules",size:CGSize(width:720,height:680)) { RulesView(model:model) }
        case .copyText:
            let items = model.selectedItems
            model.notice("Reading selected text…")
            Task { @MainActor in
                let text = await model.textForCopy(items)
                if text.isEmpty { model.notice("No text found in the selected items") }
                else { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text,forType:.string); model.notice("Copied recognized text") }
            }
        case .locate:
            if let item = model.selectedItems.first, model.availability[item.id] == .missing || model.availability[item.id] == .offline {
                let panel = NSOpenPanel(); panel.level = WorkflowPresentation.modalLevel
                if panel.runModal() == .OK, let url = panel.url { model.updateReference(item.id,to:url) }
            } else { view?.actions.reveal(model.selectedItems) }
        case .settings: SettingsWindowController.shared.show(model: model)
        case .close: if let view { view.delegate?.lineViewRequestsHide(view) }
        case .preview: preview(from: anchor)
        case .copy: _ = DragWriters.copyToPasteboard(model.selectedItems, model: model)
        case .share: share(from: anchor)
        case .prepare: if let item = model.selectedItems.first { prepare(item) }
        case .export: export()
        case .browse: browse()
        case .note: note(nil)
        case .newLine:
            if let name = TextPrompt.run(title: "New Line", message: "Name this collection.", initial: "", multiline: false) { model.query = ""; model.addLine(named: name) }
        case .previous: view?.scrollPage(-1)
        case .next: view?.scrollPage(1)
        }
    }
    func browse() {
        present("Clothesline Collection", key: "collection", size: CGSize(width: 980,height: 650)) {
            CollectionView(model: model, actions: self)
        }
    }
    func note(_ item: HangingItem?) {
        present(item == nil ? "New Note" : "Edit Note", key: item?.id.uuidString ?? "new-note", size: CGSize(width: 520,height: 380)) {
            NoteEditor(model: model, item: item)
        }
    }
    func alias(_ item: HangingItem) {
        if let value = TextPrompt.run(title: "Rename Label", message: "Change the label on the line. The original file name stays the same.", initial: item.title, multiline: false) { model.renameItem(item.id,title: value) }
    }
    func prepare(_ item: HangingItem) {
        guard let reference = item.file else { return }
        present("Prepare Image — \(item.title)", key: "image-\(item.id)", size: CGSize(width: 980,height: 730)) {
            ImageEditor(model: model, reference: reference, title: item.title)
        }
    }
    func export() {
        let items = model.selectedItems
        guard !items.isEmpty else { return }
        present("Export Collection", key: "export", size: CGSize(width: 690,height: 650)) { RecipeView(model: model, items: items) }
    }
    func preview(from anchor: NSView?) {
        if anchor?.window === view?.window, view?.window?.isVisible == true { view?.toggleQuickLook(); return }
        guard let view else { return }
        let items = model.selectedItems
        let entries = items.compactMap { item in view.actions.previewURL(for: item).map { (item.title,$0) } }
        guard entries.count == items.count else { showWorkflowError(WorkflowError.unreadable("one or more selected items")); return }
        guard !entries.isEmpty else { return }
        present("Preview",key: "preview",size: CGSize(width: 760,height: 600)) { CollectionPreview(entries: entries) }
    }
    func share(from requestedAnchor: NSView? = nil) {
        let items = model.selectedItems
        let files = model.files
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> ([Any], [String]) in
                var payload: [Any] = [], missing: [String] = []
                for item in items {
                    if let ref = item.file {
                        if let url = files.resolve(ref).url { payload.append(url) } else { missing.append(item.title) }
                    } else if let link = item.link, let url = URL(string: link) { payload.append(url) }
                    else if let text = item.text { payload.append(text) }
                }
                return (payload, missing)
            }.value
            guard result.1.isEmpty else { showWorkflowError(WorkflowError.unreadable(result.1.joined(separator: ", "))); return }
            guard !result.0.isEmpty, let anchor = requestedAnchor ?? self.view, anchor.window?.isVisible == true else { return }
            sharePicker = NSSharingServicePicker(items: result.0)
            sharePicker?.show(relativeTo: CGRect(x: anchor.bounds.midX,y: anchor.bounds.midY,width: 1,height: 1), of: anchor, preferredEdge: .minY)
        }
    }
}

@MainActor func showWorkflowError(_ error: Error) {
    let alert = NSAlert(); alert.window.level = WorkflowPresentation.modalLevel; alert.messageText = "Could not complete the action"; alert.informativeText = error.localizedDescription
    NSApp.activate(ignoringOtherApps: true); alert.runModal()
}

@MainActor enum WorkflowPresentation {
    static var modalLevel: NSWindow.Level { NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2) }
}
