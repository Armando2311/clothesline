import SwiftUI
import AppKit
import ClotheslineCore

enum LineAction { case preview, copy, share, prepare, export, browse, note, newLine, previous, next, settings, close }
struct LineControls: View {
    @ObservedObject var model: AppModel
    var action: (LineAction, NSView?) -> Void
    @State private var anchor: NSView?
    var searchTarget = "rope"
    var focusChanged: ((Bool) -> Void)?
    var verticalMove: ((CGFloat) -> Void)?
    @FocusState private var searching: Bool
    var body: some View {
        HStack(spacing: 6) {
            if let verticalMove { PanelDragHandle(move: verticalMove).frame(width: 24,height: 24).help("Drag to move the clothesline up or down") }
            Picker("Line", selection: Binding(get: { model.board.activeLineID }, set: { model.query = ""; model.activate(lineID: $0) })) {
                ForEach(model.board.lines) { Text($0.name).tag($0.id) }
            }.labelsHidden().frame(width: 145).help("Switch clothesline")
            icon("New line", "plus", .newLine)
            HStack(spacing: 5) {
                Button { searching = true } label: { Image(systemName: "magnifyingglass").foregroundStyle(.secondary) }.buttonStyle(.plain).keyboardShortcut("f").help("Search (Command–F)").accessibilityLabel("Search")
                TextField("Search every line", text: $model.query).textFieldStyle(.plain).focused($searching)
                    .onExitCommand { if searchTarget == "rope" { action(.close,anchor) } else { model.query = ""; searching = false } }
                if !model.query.isEmpty { Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).help("Clear search") }
            }.padding(6).background { if model.settings.theme == .liquidGlass { Color.primary.opacity(0.055) } else { Color(nsColor: .windowBackgroundColor).opacity(0.7) } }.cornerRadius(6).frame(minWidth: 150, maxWidth: 250)
            Text(model.selectedIDs.isEmpty ? "\(model.visibleItems.count) items" : "\(model.selectedIDs.count) selected").font(.caption).foregroundStyle(.secondary).frame(minWidth: 64)
            Spacer(minLength: 0)
            icon("Scroll left", "chevron.left", .previous)
            icon("Scroll right", "chevron.right", .next)
            icon("Browse collection", "square.grid.2x2", .browse)
            Divider().frame(height: 20)
            icon("Preview", "eye", .preview, enabled: !model.selectedItems.isEmpty)
            icon("Copy", "doc.on.doc", .copy, enabled: !model.selectedItems.isEmpty)
            icon("Share", "square.and.arrow.up", .share, enabled: !model.selectedItems.isEmpty)
            icon("Prepare image", "slider.horizontal.3", .prepare, enabled: model.selectedItems.count == 1 && [.image,.screenshot].contains(model.selectedItems[0].kind))
            Button("Export…") { action(.export,anchor) }.disabled(model.selectedItems.isEmpty)
            icon("New note", "square.and.pencil", .note)
            if searchTarget == "rope" {
                Divider().frame(height: 20)
                Toggle(isOn: $model.settings.keepToolbarVisible) {
                    Image(systemName: model.settings.keepToolbarVisible ? "pin.fill" : "pin").frame(width: 18)
                }
                .toggleStyle(.button)
                .help(model.settings.keepToolbarVisible ? "Unpin toolbar — hide when the pointer leaves" : "Pin toolbar — keep controls visible")
                .accessibilityLabel("Keep toolbar visible")
                icon("Settings", "gearshape.fill", .settings)
                Button("EXIT") { action(.close,anchor) }
                    .font(.system(size: 13,weight: .bold,design: .rounded))
                    .padding(.horizontal,10).frame(minWidth: 66,minHeight: 28)
                    .help("Close clothesline (Escape)").accessibilityLabel("EXIT — Close clothesline")
            }
        }
        .padding(.horizontal,8).padding(.vertical,4)
        .background { toolbarBackground }
        .background(ControlAnchor { anchor = $0 })
        .onChange(of: searching) { value in focusChanged?(value) }
        .onReceive(NotificationCenter.default.publisher(for: .clotheslineSearch)) { notification in if (notification.userInfo?["target"] as? String ?? "rope") == searchTarget { searching = true } }
    }
    @ViewBuilder private var toolbarBackground: some View {
        if model.settings.theme == .liquidGlass {
            // The panel already supplies desktop frost and glass. A second adaptive
            // glass pass here changed the apparent blur when the toolbar appeared.
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.2))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.18),lineWidth: 0.75))
        } else {
            RoundedRectangle(cornerRadius: 10).fill(.regularMaterial)
                .shadow(color: .black.opacity(model.settings.theme == .noTheme ? 0.2 : 0),radius: 7,y: 3)
        }
    }
    private func icon(_ label: String, _ symbol: String, _ value: LineAction, enabled: Bool = true) -> some View {
        Button { action(value,anchor) } label: { Image(systemName: symbol).frame(width: 18) }
            .help(label).accessibilityLabel(label).disabled(!enabled)
    }
}
extension Notification.Name { static let clotheslineSearch = Notification.Name("ClotheslineSearch") }
