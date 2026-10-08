import SwiftUI
import AppKit
import ClotheslineCore

enum LineAction { case preview, copy, share, prepare, export, browse, note, newLine, previous, next }
struct LineControls: View {
    @ObservedObject var model: AppModel
    var action: (LineAction) -> Void
    @FocusState private var searching: Bool
    var body: some View {
        HStack(spacing: 8) {
            Picker("Line", selection: Binding(get: { model.board.activeLineID }, set: { model.query = ""; model.activate(lineID: $0) })) {
                ForEach(model.board.lines) { Text($0.name).tag($0.id) }
            }.labelsHidden().frame(width: 145).help("Switch clothesline")
            icon("New line", "plus", .newLine)
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search every line", text: $model.query).textFieldStyle(.plain).focused($searching)
                    .onExitCommand { model.query = ""; searching = false }
                if !model.query.isEmpty { Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).help("Clear search") }
            }.padding(6).background(.background.opacity(0.7)).cornerRadius(6).frame(minWidth: 150, maxWidth: 250)
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
            Button("Export…") { action(.export) }.disabled(model.selectedItems.isEmpty)
            icon("New note", "square.and.pencil", .note)
        }
        .padding(.horizontal,12).padding(.vertical,6)
        .background(.regularMaterial).cornerRadius(10)
        .onReceive(NotificationCenter.default.publisher(for: .clotheslineSearch)) { _ in searching = true }
    }
    private func icon(_ label: String, _ symbol: String, _ value: LineAction, enabled: Bool = true) -> some View {
        Button { action(value) } label: { Image(systemName: symbol).frame(width: 18) }
            .help(label).accessibilityLabel(label).disabled(!enabled)
    }
}
extension Notification.Name { static let clotheslineSearch = Notification.Name("ClotheslineSearch") }
