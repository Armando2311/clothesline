import SwiftUI
import AppKit
import ClotheslineCore

struct CollectionView: View {
    @ObservedObject var model: AppModel
    let actions: WorkflowActions
    @State private var keyboardFocusID: UUID?
    var body: some View {
        VStack(spacing: 0) {
            LineControls(model: model, action: { action, anchor in actions.perform(action, from: anchor) },searchTarget: "collection").padding(8)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160),spacing: 14)],spacing: 14) {
                        ForEach(model.visibleItems) { item in
                            VStack(spacing: 8) {
                                CollectionThumbnail(model: model,item: item).frame(height: 105)
                                SearchHighlight(text:item.title,query:model.query).font(.body.weight(.medium)).lineLimit(2).frame(height: 35)
                                Text(model.board.line(item.lineID)?.name ?? item.kind.displayName).font(.caption).foregroundStyle(.secondary)
                                if let excerpt = SearchFilters.excerpt(model.recognizedText[item.id] ?? item.text ?? "",query:model.query) {
                                    SearchHighlight(text:excerpt,query:model.query).font(.caption).lineLimit(2)
                                }
                            }
                            .padding(10).frame(maxWidth: .infinity)
                            .background(model.selectedIDs.contains(item.id) ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.04))
                            .cornerRadius(10).overlay(RoundedRectangle(cornerRadius: 10).stroke(model.selectedIDs.contains(item.id) ? Color.accentColor : .clear,lineWidth: 2))
                            .contentShape(Rectangle())
                            .overlay(CollectionDragSurface(model: model,item: item,actions: actions))
                            .premiumAnimation(value: model.selectedIDs.contains(item.id))
                            .transition(.opacity)
                            .id(item.id)
                        }
                    }
                    .premiumAnimation(value: model.visibleItems.map(\.id))
                    .background(GeometryReader { gridGeometry in
                        CollectionKeyboardSurface(model: model, actions: actions,
                            columns: max(1, Int((gridGeometry.size.width + 14) / 174)),
                            onNavigate: { keyboardFocusID = $0 })
                    })
                    .padding(18)
                    if model.visibleItems.isEmpty { Text(model.isSearching ? "No matching items. Try another word." : "Drop files on your line to get started.").foregroundStyle(.secondary).padding(40) }
                }
                .onChange(of: keyboardFocusID) { id in
                    if let id { withAnimation(Motion.swiftUI) { proxy.scrollTo(id) } }
                }
            }
            HStack { Text("Arrow keys to navigate · Space to preview · ⌘-click to select several items · Double-click to open · Originals stay untouched").font(.caption).foregroundStyle(.secondary); Spacer() }.padding(12)
        }.frame(minWidth: 900,minHeight: 420)
    }
}
private struct CollectionThumbnail: View {
    @ObservedObject var model: AppModel
    let item: HangingItem
    @State private var image: NSImage?
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFit() }
            else { Image(systemName: item.kind == .text ? "note.text" : item.kind == .link ? "link" : "doc").font(.system(size: 42)).foregroundStyle(.secondary) }
        }
        .premiumAnimation(value: image != nil)
        .overlay(alignment: .topLeading) { if let availability = model.availability[item.id], availability != .available { Text(availability == .missing ? "MISSING" : "OFFLINE").font(.caption.bold()).foregroundStyle(.red) } }
        .task(id: item.file?.path) {
            image = nil
            if let url = model.url(for: item) {
                if [.image,.screenshot,.pdf].contains(item.kind) {
                    model.thumbnails.thumbnail(for: url,size: CGSize(width: 160,height: 110),scale: 2) { cg in if let cg { image = NSImage(cgImage: cg,size: .zero) } }
                } else { image = NSWorkspace.shared.icon(forFile: url.path) }
            }
        }
    }
}

/// Uses visible ordering, so filtering or deleting the anchor cannot leave a stale index.
enum CollectionNavigation {
    enum Direction { case left, right, up, down }
    static func destination(ids: [UUID], selected: Set<UUID>, anchor: UUID?, columns: Int, direction: Direction) -> UUID? {
        guard !ids.isEmpty else { return nil }
        let current = anchor.flatMap { selected.contains($0) ? ids.firstIndex(of: $0) : nil }
            ?? ids.firstIndex(where: { selected.contains($0) })
        guard let current else { return ids.first }
        let delta: Int
        switch direction {
        case .left: delta = -1
        case .right: delta = 1
        case .up:
            guard current >= max(1, columns) else { return ids[current] }
            delta = -max(1, columns)
        case .down:
            guard current / max(1, columns) < (ids.count - 1) / max(1, columns) else { return ids[current] }
            delta = max(1, columns)
        }
        return ids[max(0, min(ids.count - 1, current + delta))]
    }
}

private struct CollectionKeyboardSurface: NSViewRepresentable {
    let model: AppModel
    let actions: WorkflowActions
    let columns: Int
    let onNavigate: (UUID) -> Void
    func makeNSView(context: Context) -> CollectionKeyboardView {
        CollectionKeyboardView(model: model, actions: actions, columns: columns, onNavigate: onNavigate)
    }
    func updateNSView(_ view: CollectionKeyboardView, context: Context) {
        view.columns = columns
        view.onNavigate = onNavigate
    }
}

/// A stable responder behind the lazy cards. Keyboard handling runs only while this
/// view has focus; the search field keeps its normal editing commands.
final class CollectionKeyboardView: NSView {
    let model: AppModel
    let actions: WorkflowActions
    var columns: Int
    var anchorID: UUID?
    var onNavigate: (UUID) -> Void
    init(model: AppModel, actions: WorkflowActions, columns: Int, onNavigate: @escaping (UUID) -> Void) {
        self.model = model; self.actions = actions; self.columns = columns; self.onNavigate = onNavigate
        super.init(frame: .zero)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("not supported") }
    override var acceptsFirstResponder: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    static func find(in view: NSView) -> CollectionKeyboardView? {
        if let keyboard = view as? CollectionKeyboardView { return keyboard }
        for child in view.subviews { if let keyboard = find(in: child) { return keyboard } }
        return nil
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self, event.modifierFlags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }
        return command(event) || super.performKeyEquivalent(with: event)
    }
    private func command(_ event: NSEvent) -> Bool {
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "a": model.selectedIDs = Set(model.visibleItems.map(\.id))
        case "c": actions.perform(.copy, from: self)
        case "f": NotificationCenter.default.post(name: .clotheslineSearch, object: nil, userInfo: ["target": "collection"])
        case "z" where !event.modifierFlags.contains(.shift): model.undoLastRemoval()
        default: return false
        }
        return true
    }
    override func keyDown(with event: NSEvent) {
        guard window?.firstResponder === self else { super.keyDown(with: event); return }
        if event.modifierFlags.contains(.command) {
            if !command(event) { super.keyDown(with: event) }
            return
        }
        let direction: CollectionNavigation.Direction?
        switch event.keyCode {
        case 123: direction = .left
        case 124: direction = .right
        case 125: direction = .down
        case 126: direction = .up
        default: direction = nil
        }
        if let direction, let id = CollectionNavigation.destination(ids: model.visibleItems.map(\.id), selected: model.selectedIDs,
                                                                     anchor: anchorID, columns: columns, direction: direction) {
            if event.modifierFlags.contains(.shift) { model.selectedIDs.insert(id) }
            else { model.selectedIDs = [id] }
            anchorID = id
            onNavigate(id)
            return
        }
        switch event.keyCode {
        case 49: actions.preview(from: self)
        case 51, 117: actions.view?.actions.removeFromLine(model.selectedItems)
        case 36, 76:
            if let item = model.selectedItems.first, item.kind == .text { actions.note(item) }
            else { actions.view?.actions.open(model.selectedItems) }
        default: super.keyDown(with: event)
        }
    }
}
