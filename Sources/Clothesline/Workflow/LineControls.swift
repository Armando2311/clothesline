import SwiftUI
import AppKit
import ClotheslineCore

enum LineAction { case preview, copy, share, prepare, export, browse, note, newLine, previous, next, settings, close, history, workspace, rules, copyText, locate }
struct LineControls: View {
    @ObservedObject var model: AppModel
    var action: (LineAction, NSView?) -> Void
    @State private var anchor: NSView?
    var searchTarget = "rope"
    var focusChanged: ((Bool) -> Void)?
    var verticalMove: ((CGFloat) -> Void)?
    @FocusState private var searching: Bool
    @State private var filtersVisible = false
    var body: some View {
        GeometryReader { geometry in
            controls(compact: AdaptivePanel.compactToolbar(width: geometry.size.width))
        }
        .background { toolbarBackground }
        .background(ControlAnchor { anchor = $0 })
        .onChange(of: searching) { value in focusChanged?(value) }
        .onReceive(NotificationCenter.default.publisher(for: .clotheslineSearch)) { notification in if (notification.userInfo?["target"] as? String ?? "rope") == searchTarget { searching = true } }
    }
    private func controls(compact: Bool) -> some View {
        HStack(spacing: 6) {
            if let verticalMove { PanelDragHandle(move: verticalMove).frame(width: 24,height: 24).help("Drag to move the clothesline up or down") }
            Picker("Line", selection: Binding(get: { model.board.activeLineID }, set: { model.query = ""; model.activate(lineID: $0) })) {
                ForEach(model.board.lines) { Text($0.name).tag($0.id) }
            }.labelsHidden().frame(width: compact ? 110 : 145).help("Switch clothesline")
            search.frame(minWidth: compact ? 90 : 150, maxWidth: 250)
            Button { filtersVisible.toggle() } label: { Image(systemName: model.searchFilters.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle") }
                .help("Filter search").accessibilityLabel("Filter search")
                .popover(isPresented: $filtersVisible) { searchFilters }
            Spacer(minLength: 0)
            if !compact {
                Text(model.statusMessage ?? (model.selectedIDs.isEmpty ? "\(model.visibleItems.count) items" : "\(model.selectedIDs.count) selected"))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                icon("Scroll left", "chevron.left", .previous)
                icon("Scroll right", "chevron.right", .next)
            }
            if model.selectedItems.isEmpty {
                icon("New note", "square.and.pencil", .note)
                if !compact { icon("Browse collection", "square.grid.2x2", .browse) }
            } else {
                if !compact { icon("Copy selection", "doc.on.doc", .copy) }
                if model.selectedItems.count == 1 && model.selectedItems.contains(where: { [.image,.screenshot].contains($0.kind) }) {
                    icon("Prepare image", "slider.horizontal.3", .prepare)
                    if !compact { icon("Share selection", "square.and.arrow.up", .share) }
                } else {
                    icon("Share selection", "square.and.arrow.up", .share)
                }
                icon("Export selection", "tray.and.arrow.down", .export)
                if !compact { icon("Preview selection", "eye", .preview) }
            }
            Menu {
                if let status = model.statusMessage { Text(status) }
                Button("Browse collection") { action(.browse,anchor) }
                Button("New note") { action(.note,anchor) }
                Button("New line") { action(.newLine,anchor) }
                Divider()
                Button("Copy") { action(.copy,anchor) }.disabled(model.selectedItems.isEmpty)
                Button("Share…") { action(.share,anchor) }.disabled(model.selectedItems.isEmpty)
                Button("Preview") { action(.preview,anchor) }.disabled(model.selectedItems.isEmpty)
                Button("Prepare image…") { action(.prepare,anchor) }.disabled(model.selectedItems.count != 1 || !model.selectedItems.contains { [.image,.screenshot].contains($0.kind) })
                Button("Export…") { action(.export,anchor) }.disabled(model.selectedItems.isEmpty)
                Button("Copy text") { action(.copyText,anchor) }.disabled(model.selectedItems.isEmpty)
                Button("Locate missing file…") { action(.locate,anchor) }.disabled(model.selectedItems.count != 1)
                if !model.selectedItems.isEmpty {
                    Menu("Move selection to line") {
                        ForEach(model.board.lines) { line in
                            Button(line.name) { model.move(model.selectedIDs, toLine: line.id) }
                        }
                    }
                    Button("Group selection…") { nameGroup() }
                    Button("Ungroup selection") { model.ungroupItems(model.selectedIDs) }
                }
                if !model.groups.isEmpty {
                    Button("Collapse groups into stacks") { model.collapsedGroupIDs = Set(model.groups.map(\.id)) }
                    Button("Expand all groups") { model.collapsedGroupIDs = [] }
                }
                Divider()
                Button("Activity history…") { action(.history,anchor) }
                Button("Workspace…") { action(.workspace,anchor) }
                Button("Smart rules…") { action(.rules,anchor) }
                Divider()
                Button("Scroll left") { action(.previous,anchor) }
                Button("Scroll right") { action(.next,anchor) }
            } label: { Image(systemName: "ellipsis").frame(width: 18) }
                .menuStyle(.borderlessButton).fixedSize().help("More actions").accessibilityLabel("More actions")
            if searchTarget == "rope" {
                Divider().frame(height: 20)
                Toggle(isOn: $model.settings.keepToolbarVisible) { Image(systemName: model.settings.keepToolbarVisible ? "pin.fill" : "pin").frame(width: 18) }
                    .toggleStyle(.button).help("Keep toolbar visible").accessibilityLabel("Keep toolbar visible")
                icon("Settings", "gearshape.fill", .settings)
                Button("EXIT") { action(.close,anchor) }
                    .font(.system(size: 13,weight: .bold,design: .rounded))
                    .padding(.horizontal,4).frame(minWidth: 54,minHeight: 28)
                    .help("Close clothesline (Escape)").accessibilityLabel("EXIT — Close clothesline")
            }
        }.padding(.horizontal,8).padding(.vertical,4)
    }
    private var search: some View {
        HStack(spacing: 5) {
            Button { searching = true } label: { Image(systemName: "magnifyingglass").foregroundStyle(.secondary) }
                .buttonStyle(.plain).keyboardShortcut("f").help("Search (Command–F)").accessibilityLabel("Search")
            TextField("Search every line", text: $model.query).textFieldStyle(.plain).focused($searching)
                .onExitCommand { if searchTarget == "rope" { action(.close,anchor) } else { model.query = ""; searching = false } }
            if !model.query.isEmpty { Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).help("Clear search") }
        }.padding(6).background(Color.primary.opacity(0.055)).cornerRadius(6)
    }
    private var searchFilters: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Search filters").font(.headline)
            Picker("Kind", selection: $model.searchFilters.kind) {
                Text("Every kind").tag(ItemKind?.none)
                ForEach(ItemKind.allCases, id: \.self) { Text($0.displayName).tag(Optional($0)) }
            }
            Picker("Source", selection: $model.searchFilters.source) {
                Text("Every source").tag(ItemSource?.none)
                ForEach([ItemSource.screenshot,.drop,.clipboard,.manual],id: \.self) { Text($0.rawValue.capitalized).tag(Optional($0)) }
            }
            Picker("Line", selection: $model.searchFilters.lineID) {
                Text("Every line").tag(UUID?.none)
                ForEach(model.board.lines) { Text($0.name).tag(Optional($0.id)) }
            }
            Picker("Added", selection: $model.searchFilters.period) {
                Text("Any time").tag(SearchPeriod.anytime)
                Text("Today").tag(SearchPeriod.today)
                Text("Last 7 days").tag(SearchPeriod.week)
            }
            Button("Reset filters") { model.searchFilters = SearchFilters() }
        }.padding(18).frame(width: 280)
    }
    private func nameGroup() {
        let alert = NSAlert()
        alert.messageText = "Group selection"
        alert.informativeText = "Name this group. You can also hold Option while dropping items onto a card to group them."
        let field = NSTextField(string: "New group")
        field.frame = NSRect(x: 0,y: 0,width: 260,height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Group")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { model.groupItems(model.selectedIDs, named: field.stringValue) }
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
