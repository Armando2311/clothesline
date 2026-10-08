import AppKit
import SwiftUI
import ClotheslineCore

@MainActor
final class WorkflowActions {
    let model: AppModel
    weak var view: LineView?
    private var windows: [String: NSWindow] = [:]
    private var sharePicker: NSSharingServicePicker?
    init(model: AppModel, view: LineView) { self.model = model; self.view = view }
    func present<Content: View>(_ title: String, key: String, size: CGSize, @ViewBuilder content: () -> Content) {
        let window = windows[key] ?? NSWindow(contentRect: CGRect(origin: .zero,size: size), styleMask: [.titled,.closable,.miniaturizable,.resizable], backing: .buffered, defer: false)
        window.title = title; window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: content())
        window.setContentSize(size); window.center(); windows[key] = window
        NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
    }
    func perform(_ action: LineAction) {
        switch action {
        case .preview: view?.toggleQuickLook()
        case .copy: _ = DragWriters.copyToPasteboard(model.selectedItems, model: model)
        case .share: share()
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
    func share() {
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
            guard !result.0.isEmpty, let view = self.view else { return }
            sharePicker = NSSharingServicePicker(items: result.0)
            sharePicker?.show(relativeTo: CGRect(x: view.bounds.midX,y: view.bounds.height-40,width: 1,height: 1), of: view, preferredEdge: .minY)
        }
    }
}

@MainActor func showWorkflowError(_ error: Error) {
    let alert = NSAlert(); alert.messageText = "Could not complete the action"; alert.informativeText = error.localizedDescription
    NSApp.activate(ignoringOtherApps: true); alert.runModal()
}
