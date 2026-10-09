import AppKit
import SwiftUI
import ClotheslineCore

enum DragPolicy {
    static func operation(items: [HangingItem],context: NSDraggingContext,modifiers: NSEvent.ModifierFlags) -> NSDragOperation {
        if context == .withinApplication { return [.move,.copy] }
        if !items.isEmpty, modifiers.contains(.command), items.allSatisfy({ $0.file?.ownership == .referenced }) { return .move }
        return .copy
    }
}
struct CollectionDragSurface: NSViewRepresentable {
    let model: AppModel
    let item: HangingItem
    let actions: WorkflowActions
    func makeNSView(context: Context) -> CollectionDragView { CollectionDragView(model: model,item: item,actions: actions) }
    func updateNSView(_ view: CollectionDragView,context: Context) {
        view.item = item
        view.setAccessibilitySelected(model.selectedIDs.contains(item.id))
        view.setAccessibilityLabel("\(item.kind.displayName): \(item.title)")
    }
}
final class CollectionDragView: NSView, NSDraggingSource {
    let model: AppModel
    var item: HangingItem
    let actions: WorkflowActions
    private var start: CGPoint?
    private var wasSelected = false
    private(set) var draggingIDs: [UUID] = []
    var didDropInternally = false
    init(model: AppModel,item: HangingItem,actions: WorkflowActions) {
        self.model = model; self.item = item; self.actions = actions
        super.init(frame: .zero)
        setAccessibilityElement(true); setAccessibilityRole(.button)
    }
    required init?(coder: NSCoder) { fatalError("not supported") }
    override func mouseDown(with event: NSEvent) {
        focusCollection()
        start = convert(event.locationInWindow,from: nil); wasSelected = model.selectedIDs.contains(item.id)
        if event.clickCount == 2 { open(); start = nil; return }
        if event.modifierFlags.contains(.command) {
            if wasSelected { model.selectedIDs.remove(item.id) } else { model.selectedIDs.insert(item.id) }
        } else if !wasSelected { model.selectedIDs = [item.id] }
    }
    override func mouseUp(with event: NSEvent) {
        if start != nil, wasSelected, !event.modifierFlags.contains(.command) { model.selectedIDs = [item.id] }
        start = nil
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let point = convert(event.locationInWindow,from: nil)
        guard hypot(point.x-start.x,point.y-start.y) > 4 else { return }
        self.start = nil; didDropInternally = false
        let selected = model.selectedItems
        draggingIDs = []
        let dragItems = selected.compactMap { item -> NSDraggingItem? in
            guard let writer = DragWriters.writer(for: item,model: model) else { return nil }
            draggingIDs.append(item.id)
            let drag = NSDraggingItem(pasteboardWriter: writer)
            let image: NSImage
            if let url = model.url(for: item),
               let cached = model.thumbnails.cached(for: url, size: CGSize(width: 160, height: 110), scale: 2) {
                image = NSImage(cgImage: cached, size: CGSize(width: cached.width, height: cached.height))
            } else {
                image = model.url(for: item).map { NSWorkspace.shared.icon(forFile: $0.path) }
                    ?? NSImage(systemSymbolName: item.kind == .text ? "note.text" : item.kind == .link ? "link" : "doc", accessibilityDescription: item.title)!
            }
            let size = CollectionDragPreview.size(for: image.size)
            drag.setDraggingFrame(CGRect(x: point.x-size.width/2, y: point.y-size.height/2, width: size.width, height: size.height), contents: image)
            return drag
        }
        guard !dragItems.isEmpty else { return }
        let session = beginDraggingSession(with: dragItems,event: event,source: self)
        session.draggingFormation = .pile; session.animatesToStartingPositionsOnCancelOrFail = true
    }
    func draggingSession(_ session: NSDraggingSession,sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        DragPolicy.operation(items: draggingIDs.compactMap { model.board.item($0) },context: context,modifiers: NSEvent.modifierFlags)
    }
    func draggingSession(_ session: NSDraggingSession,endedAt screenPoint: NSPoint,operation: NSDragOperation) {
        defer { draggingIDs = [] }
        guard !didDropInternally else { return }
        if operation.contains(.move) { model.remove(Set(draggingIDs),style: .delivered,undoable: false) }
        else if operation != [], model.settings.afterDragOut == .removeFromLine { model.remove(Set(draggingIDs),style: .delivered) }
    }
    override func rightMouseDown(with event: NSEvent) {
        focusCollection()
        if !model.selectedIDs.contains(item.id) { model.selectedIDs = [item.id] }
        if let menu = actions.view?.actions.menu(for: model.selectedItems) {
            if let preview = menu.items.first(where: { $0.title == "Quick Look" }) { preview.target = self; preview.action = #selector(previewSelected) }
            if let share = menu.items.first(where: { $0.title == "Share…" }) { share.target = self; share.action = #selector(shareSelected) }
            NSMenu.popUpContextMenu(menu,with: event,for: self)
        }
    }
    @objc private func previewSelected() { actions.preview(from: self) }
    @objc private func shareSelected() { actions.share(from: self) }
    override func accessibilityPerformPress() -> Bool {
        model.selectedIDs = [item.id]
        focusCollection()
        return true
    }
    private func focusCollection() {
        guard let content = window?.contentView, let keyboard = CollectionKeyboardView.find(in: content) else { return }
        keyboard.anchorID = item.id
        window?.makeFirstResponder(keyboard)
    }
    private func open() { if item.kind == .text { actions.note(item) } else { actions.view?.actions.open([item]) } }
}


enum CollectionDragPreview {
    static func size(for source: CGSize) -> CGSize {
        guard source.width > 0, source.height > 0, source.width.isFinite, source.height.isFinite else {
            return CGSize(width: 48, height: 48)
        }
        let scale = 96 / max(source.width, source.height)
        return CGSize(width: source.width * scale, height: source.height * scale)
    }
}
