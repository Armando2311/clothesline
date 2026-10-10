import AppKit
import SwiftUI
import ClotheslineCore

struct WorkspaceView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var activity: WorkspaceStore
    @State private var presets: [ExportPreset] = []
    @State private var presetError: String?
    init(model: AppModel) { self.model = model; activity = model.activity }
    private var config: WorkspaceConfiguration { activity.config(for: model.board.activeLineID) ?? WorkspaceConfiguration(lineID: model.board.activeLineID) }
    var body: some View {
        Form {
            Text("Workspace · \(model.board.activeLine.name)").font(.title2.bold())
            Text("Keep a destination, export preset and project context with this line.").foregroundStyle(.secondary)
            TextField("Project / client context", text: Binding(get: { config.organization }, set: { var value = config; value.organization = $0; activity.update(value) }))
            HStack {
                Text(activity.destinationURL(for: model.board.activeLineID)?.path ?? "No export destination selected").font(.caption).textSelection(.enabled)
                Spacer()
                Button("Choose Folder…") { chooseFolder() }
            }
            Picker("Export preset", selection: Binding<UUID?>(get: { config.exportPresetID }, set: { model.setWorkspacePreset($0) })) {
                Text("Use recipe defaults").tag(UUID?.none)
                ForEach(presets) { Text($0.name).tag(Optional($0.id)) }
                if let id = config.exportPresetID, !presets.contains(where: { $0.id == id }) { Text("Unavailable preset").tag(Optional(id)) }
            }
            Picker("Arrangement", selection: Binding<Board.SortOrder?>(get: { config.sortOrder }, set: { order in
                var value = config; value.sortOrder = order; activity.update(value)
                if let order { model.sortActiveLine(by: order) }
            })) {
                Text("Manual").tag(Board.SortOrder?.none)
                ForEach(Board.SortOrder.allCases, id: \.self) { Text($0.displayName).tag(Optional($0)) }
            }
            if presets.isEmpty { Text("Save a named preset in the export window to reuse it here.").font(.caption).foregroundStyle(.secondary) }
            if let error = activity.error ?? presetError { Text(error).foregroundStyle(.red).font(.caption) }
        }.premiumAnimation(value: model.board.activeLineID).padding(22).frame(minWidth: 520, minHeight: 260)
        .task { do { presets = try ExportPresetStore(directory: activity.directory).load() } catch { presetError = error.localizedDescription } }
    }
    private func chooseFolder() {
        let panel = NSOpenPanel(); panel.level = WorkflowPresentation.modalLevel; panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url { model.setWorkspaceDestination(url) }
    }
}

struct RulesView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var activity: WorkspaceStore
    @State private var draft: CollectionRule
    @State private var preview: String?
    init(model: AppModel) {
        self.model = model; activity = model.activity
        _draft = State(initialValue: CollectionRule(name: "New rule", lineID: model.board.activeLineID))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Collection rules").font(.title2.bold())
            Text("Rules route incoming items. A selected watch folder adds references to finished files in that folder only; originals stay untouched.").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                ForEach(activity.rules) { rule in
                    HStack {
                        Toggle("", isOn: Binding(get: { activity.rules.first { $0.id == rule.id }?.enabled ?? false }, set: { var value = rule; value.enabled = $0; activity.upsert(value) })).labelsHidden()
                        VStack(alignment: .leading) {
                            Text(rule.name).font(.headline)
                            Text("\(rule.source?.rawValue ?? "Any source") · \(rule.kind?.displayName ?? "Any kind") → \(model.board.line(rule.lineID)?.name ?? "Missing line")").font(.caption)
                            if let path = rule.folderPath { Text(path).font(.caption2).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Button("Edit") { draft = rule; preview = nil }
                        Button("Delete") { activity.removeRule(rule.id) }
                    }.padding(.vertical, 5)
                }
            }.frame(maxHeight: 200)
            Divider()
            TextField("Rule name", text: $draft.name).textFieldStyle(.roundedBorder)
            HStack {
                Picker("Source", selection: $draft.source) {
                    Text("Any source").tag(ItemSource?.none)
                    ForEach([ItemSource.screenshot,.drop,.clipboard,.manual], id: \.self) { Text($0.rawValue.capitalized).tag(Optional($0)) }
                }
                Picker("Kind", selection: $draft.kind) {
                    Text("Any kind").tag(ItemKind?.none)
                    ForEach(ItemKind.allCases, id: \.self) { Text($0.displayName).tag(Optional($0)) }
                }
            }
            Picker("Destination line", selection: $draft.lineID) { ForEach(model.board.lines) { Text($0.name).tag($0.id) } }
            HStack {
                Text(draft.folderPath ?? "No watch folder").font(.caption).lineLimit(2)
                Spacer()
                Button("Watch Folder…") { selectFolder() }
                if draft.folderPath != nil { Button("Clear") { draft.folderPath = nil; draft.folderBookmark = nil } }
            }
            Text("Watch folders use Manual as their source. Collection starts after you save an enabled rule. Disable its switch to pause.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Preview File…") { previewFile() }
                if let preview { Text(preview).font(.caption) }
                Spacer()
                Button("New Rule") { draft = CollectionRule(name: "New rule", lineID: model.board.activeLineID); preview = nil }
                Button("Save Rule") { activity.upsert(draft) }.disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.board.line(draft.lineID) == nil)
            }
            if let error = activity.error { Text(error).foregroundStyle(.red).font(.caption) }
        }.premiumAnimation(value: activity.rules.map(\.id)).premiumAnimation(value: preview).padding(22).frame(minWidth: 660, minHeight: 550)
    }
    private func selectFolder() {
        let panel = NSOpenPanel(); panel.level = WorkflowPresentation.modalLevel; panel.canChooseFiles = false; panel.canChooseDirectories = true
        if panel.runModal() == .OK, let url = panel.url { draft.folderPath = url.path; draft.folderBookmark = WorkspaceStore.bookmark(for: url); draft.source = .manual; preview = nil }
    }
    private func previewFile() {
        let panel = NSOpenPanel(); panel.level = WorkflowPresentation.modalLevel; panel.canChooseFiles = true; panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            let kind = ItemClassifier.kind(forFileName: url.lastPathComponent, isDirectory: false, isPackage: false)
            preview = draft.matches(fileURL: url, source: draft.source ?? .manual, kind: kind) ? "Matches → \(model.board.line(draft.lineID)?.name ?? "Missing line")" : "Does not match"
        }
    }
}

struct ActivityHistoryView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var activity: WorkspaceStore
    var repeatExport: ((ActivityEntry) -> Void)?
    init(model: AppModel, repeatExport: ((ActivityEntry) -> Void)? = nil) { self.model = model; activity = model.activity; self.repeatExport = repeatExport }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Activity history").font(.title2.bold())
            Text("The last 7 days of additions, removals and exports (up to 200). Removed items can be restored to the line during that time; additions are listed by name only. A deleted original must be located again. Clear history in Settings › About › Privacy.").font(.caption).foregroundStyle(.secondary)
            if activity.history.isEmpty { Text("Activity will appear as you collect and export.").foregroundStyle(.secondary) }
            List(activity.history) { entry in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(entry.action.rawValue.capitalized).font(.headline)
                        Text(entry.date, style: .date).font(.caption)
                        Text(entry.date, style: .time).font(.caption)
                        Spacer()
                        if entry.canRestore { Button("Restore to Line") { model.restoreActivity(entry) } }
                        if entry.action == .exported, let repeatExport { Button("Export Again…") { repeatExport(entry) } }
                        if let path = entry.resultPath {
                            Button("Show Export") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }.disabled(!FileManager.default.fileExists(atPath: path))
                        }
                    }
                    Text(entry.items.map(\.title).joined(separator: ", ")).lineLimit(2).font(.caption)
                    if let path = entry.resultPath { Text(path).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                }.padding(.vertical, 4)
            }
            if let error = activity.error { Text(error).foregroundStyle(.red).font(.caption) }
        }.premiumAnimation(value: activity.history.map(\.id)).padding(22).frame(minWidth: 680, minHeight: 460)
    }
}
