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
            let icon = model.url(for: item).map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage(systemSymbolName: "doc",accessibilityDescription: item.title)!
            drag.setDraggingFrame(CGRect(x: point.x-24,y: point.y-24,width: 48,height: 48),contents: icon)
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
        if !model.selectedIDs.contains(item.id) { model.selectedIDs = [item.id] }
        if let menu = actions.view?.actions.menu(for: model.selectedItems) {
            if let preview = menu.items.first(where: { $0.title == "Quick Look" }) { preview.target = self; preview.action = #selector(previewSelected) }
            if let share = menu.items.first(where: { $0.title == "Share…" }) { share.target = self; share.action = #selector(shareSelected) }
            NSMenu.popUpContextMenu(menu,with: event,for: self)
        }
    }
    @objc private func previewSelected() { actions.preview(from: self) }
    @objc private func shareSelected() { actions.share(from: self) }
    override func accessibilityPerformPress() -> Bool { model.selectedIDs = [item.id]; return true }
    private func open() { if item.kind == .text { actions.note(item) } else { actions.view?.actions.open([item]) } }
}
