import SwiftUI
import AppKit
import ClotheslineCore

struct RecipeView: View {
    @ObservedObject var model: AppModel
    let items: [HangingItem]
    var initialOptions: RecipeOptions? = nil
    @State private var options = RecipeOptions(recipe: .clientHandoff)
    @State private var destination: URL?
    @State private var inputs: [ExportInput] = []
    @State private var progress = 0.0
    @State private var exportNotice: String?
    @State private var busy = false
    @State private var cancellation = ExportCancellation()
    @State private var result: ExportResult?
    @State private var error: String?
    @State private var resolving = true
    @State private var scopedDestination: URL?
    @State private var presets: [ExportPreset] = []
    @State private var presetLoadFailed = false
    @State private var selectedPresetID: UUID?
    @State private var presetName = ""
    @State private var previewID = UUID()
    @State private var estimate: ExportService.SizeEstimate?
    @State private var estimateError: String?
    @State private var estimating = false
    @State private var previewCancellation = ExportCancellation()
    private var presetStore: ExportPresetStore { ExportPresetStore(directory: model.store.directory) }

    var body: some View {
        VStack(alignment: .leading,spacing: 14) {
            Text("Get your collection ready").font(.title2.bold())
            Picker("Recipe",selection: Binding(get: { options.recipe },set: { recipe in options = load(recipe); result = nil })) {
                ForEach(ExportRecipe.allCases,id: \.self) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).disabled(busy || resolving)
            HStack {
                Picker("Saved preset", selection: Binding(get: { selectedPresetID }, set: { selectPreset($0) })) {
                    Text("Custom settings").tag(nil as UUID?)
                    ForEach(presets) { Text($0.name).tag(Optional($0.id)) }
                }
                TextField("Preset name", text: $presetName).textFieldStyle(.roundedBorder)
                Button("Save Preset", action: savePreset).disabled(presetLoadFailed || presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if selectedPresetID != nil { Button("Delete", action: deletePreset) }
            }.disabled(busy || resolving)
            ScrollView {
                VStack(alignment: .leading,spacing: 14) {
                    TextField("Package name",text: $options.packageName).textFieldStyle(.roundedBorder)
                    if options.recipe != .bugReport { imageOptions }
                    else {
                        reportField("Reproduction steps",text: $options.steps)
                        reportField("Expected result",text: $options.expected)
                        reportField("Actual result",text: $options.actual)
                    }
                    Toggle("Create a ZIP package",isOn: $options.zip)
                    HStack { Text(destination?.path ?? "Choose an export folder").font(.caption).lineLimit(2); Spacer(); Button("Choose Folder…",action: chooseFolder) }
                    Divider()
                    Text("Output preview · \(items.count) selected items").font(.headline)
                    if estimate == nil {
                        ForEach(Array(ExportService.plannedNames(inputs: inputs,options: options).enumerated()),id: \.offset) { _,name in Text(name).font(.system(.caption,design: .monospaced)) }
                    }
                    if estimating { ProgressView("Estimating encoded output…").font(.caption) }
                    if let estimate {
                        Text("\(ByteCountFormatter.string(fromByteCount: Int64(estimate.totalBytes), countStyle: .file)) before ZIP compression").font(.caption.bold())
                        ForEach(Array(estimate.outputs.enumerated()), id: \.offset) { _, output in
                            Text("\(output.name) · \(ByteCountFormatter.string(fromByteCount: Int64(output.bytes), countStyle: .file))").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let estimateError { Text(estimateError).font(.caption).foregroundStyle(.orange) }
                    Text("Report.md includes your notes, links and attachment references.").font(.caption).foregroundStyle(.secondary)
                    Text("Originals stay untouched. Each export gets a new folder or ZIP.").font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical,4)
            }.disabled(busy || resolving)
            if busy { ProgressView(value: progress); HStack { Text("Preparing files and package · \(Int(progress * 100))%").font(.caption); Spacer(); Button("Cancel") { cancellation.cancel() } } }
            if let exportNotice { Text(exportNotice).font(.caption).foregroundStyle(.secondary) }
            HStack {
                if let result {
                    Label("Export complete",systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([result.url]) }
                    if options.recipe == .bugReport { Button("Copy Report") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(result.report,forType: .string) } }
                }
                Spacer()
                Button("Export") { runExport() }.keyboardShortcut(.defaultAction).disabled(busy || resolving || destination == nil || items.isEmpty || estimateError != nil || estimating)
            }
        }
        .padding(22).frame(minWidth: 620,minHeight: 560)
        .alert("Could not export",isPresented: Binding(get: { error != nil },set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
        .task {
            options = initialOptions ?? load(.clientHandoff)
            let files = model.files
            inputs = await Task.detached { items.map { ExportInput(item: $0,url: $0.file.flatMap { files.resolve($0).url }) } }.value
            resolving = false
            do { presets = try presetStore.load() } catch { presetLoadFailed = true; self.error = "Saved presets could not be loaded: \(error.localizedDescription)" }
            if initialOptions == nil, let id = model.workspaceForActiveLine?.exportPresetID, presets.contains(where: { $0.id == id }) {
                selectPreset(id)
            } else {
                restoreDestination(model.workspaceForActiveLine?.destinationBookmark ?? UserDefaults.standard.data(forKey: "recipe.destination.bookmark"))
            }
            previewID = UUID()
        }
        .task(id: previewID) { await refreshEstimate() }
        .onChange(of: options) { value in
            if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data,forKey: "recipe.\(value.recipe.rawValue)") }
            result = nil; previewCancellation.cancel(); previewID = UUID()
        }
        .onDisappear { previewCancellation.cancel(); cancellation.cancel(); scopedDestination?.stopAccessingSecurityScopedResource() }
    }
    private var imageOptions: some View {
        VStack(alignment: .leading,spacing: 10) {
            HStack {
                TextField("Filename prefix",text: $options.prefix)
                TextField("Maximum edge (px)",value: $options.maxEdge,formatter: NumberFormatter())
            }.textFieldStyle(.roundedBorder)
            HStack {
                Text("Output formats")
                ForEach(ExportImageFormat.allCases, id: \.self) { format in
                    Toggle(format.rawValue.uppercased(), isOn: Binding(get: { options.imageFormats.contains(format) }, set: { enabled in
                        if enabled { options.imageFormats.append(format) }
                        else if options.imageFormats.count > 1 { options.imageFormats.removeAll { $0 == format } }
                    }))
                }
            }
            HStack {
                Toggle("Hard limit per image", isOn: Binding(get: { options.maximumImageBytes != nil }, set: { options.maximumImageBytes = $0 ? 1_000_000 : nil }))
                if options.maximumImageBytes != nil {
                    TextField("KB", value: Binding(get: { (options.maximumImageBytes ?? 1_000_000) / 1000 }, set: { options.maximumImageBytes = max(1, min($0, 1_000_000)) * 1000 }), formatter: NumberFormatter()).frame(width: 90)
                    Text("KB").font(.caption)
                }
            }
            Text("JPEG quality decreases to fit the limit. PNG keeps its pixels; reduce dimensions if it exceeds the limit.").font(.caption).foregroundStyle(.secondary)
            HStack { Text("JPEG quality \(Int(options.quality*100))%"); Slider(value: $options.quality,in: 0.05...1) }
            Picker("Crop",selection: Binding(get: { options.cropRatio ?? 0 },set: { options.cropRatio = $0 == 0 ? nil : $0 })) {
                Text("Keep original aspect ratio").tag(0.0); Text("Square (1:1)").tag(1.0); Text("Landscape (4:3)").tag(4.0/3); Text("Portrait (3:4)").tag(3.0/4)
            }
        }
    }
    private func reportField(_ title: String,text: Binding<String>) -> some View {
        VStack(alignment: .leading) { Text(title).font(.caption.bold()); TextEditor(text: text).frame(height: 65).border(Color.secondary.opacity(0.2)) }
    }
    private func load(_ recipe: ExportRecipe) -> RecipeOptions {
        if let data = UserDefaults.standard.data(forKey: "recipe.\(recipe.rawValue)"), let value = try? JSONDecoder().decode(RecipeOptions.self,from: data), (try? value.validate()) != nil { return value }
        return RecipeOptions(recipe: recipe)
    }
    private func chooseFolder() {
        let panel = NSOpenPanel(); panel.level = WorkflowPresentation.modalLevel; panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        scopedDestination?.stopAccessingSecurityScopedResource(); scopedDestination = nil
        destination = url
        if FileAccess.isSandboxed, url.startAccessingSecurityScopedResource() { scopedDestination = url }
        let flags: URL.BookmarkCreationOptions = FileAccess.isSandboxed ? [.withSecurityScope] : []
        do {
            let data = try url.bookmarkData(options: flags, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(data, forKey: "recipe.destination.bookmark")
            model.setWorkspaceDestination(url)
            if let index = presets.firstIndex(where: { $0.id == selectedPresetID }) {
                presets[index].destinationBookmark = data; presets[index].destinationPath = url.path
                try presetStore.save(presets)
            }
        } catch { self.error = "The export folder could not be remembered: \(error.localizedDescription)" }
    }
    private func selectPreset(_ id: UUID?) {
        selectedPresetID = id; model.setWorkspacePreset(id)
        guard let preset = presets.first(where: { $0.id == id }) else { presetName = ""; return }
        options = preset.options; presetName = preset.name
        restoreDestination(preset.destinationBookmark ?? model.workspaceForActiveLine?.destinationBookmark)
    }
    private func savePreset() {
        do {
            try options.validate()
            let flags: URL.BookmarkCreationOptions = FileAccess.isSandboxed ? [.withSecurityScope] : []
            let bookmark = try destination?.bookmarkData(options: flags, includingResourceValuesForKeys: nil, relativeTo: nil)
            let preset = ExportPreset(id: selectedPresetID ?? UUID(), name: presetName.trimmingCharacters(in: .whitespacesAndNewlines), options: options,
                                      destinationBookmark: bookmark, destinationPath: destination?.path)
            var updated = presets
            if let index = updated.firstIndex(where: { $0.id == preset.id }) { updated[index] = preset } else { updated.append(preset) }
            try presetStore.save(updated); presets = updated; selectedPresetID = preset.id
            model.setWorkspacePreset(preset.id)
        } catch { self.error = error.localizedDescription }
    }
    private func deletePreset() {
        do {
            let updated = presets.filter { $0.id != selectedPresetID }
            try presetStore.save(updated); presets = updated; selectPreset(nil)
        } catch { self.error = error.localizedDescription }
    }
    private func restoreDestination(_ data: Data?) {
        scopedDestination?.stopAccessingSecurityScopedResource(); scopedDestination = nil; destination = nil
        guard let data else { return }
        do {
            var stale = false
            let flags: URL.BookmarkResolutionOptions = FileAccess.isSandboxed ? [.withSecurityScope, .withoutUI] : [.withoutUI]
            let url = try URL(resolvingBookmarkData: data, options: flags, bookmarkDataIsStale: &stale)
            guard !FileAccess.isSandboxed || url.startAccessingSecurityScopedResource() else { throw WorkflowError.unreadable(url.lastPathComponent) }
            destination = url; if FileAccess.isSandboxed { scopedDestination = url }
            if stale, let index = presets.firstIndex(where: { $0.id == selectedPresetID }) {
                presets[index].destinationBookmark = try url.bookmarkData(options: FileAccess.isSandboxed ? [.withSecurityScope] : [], includingResourceValuesForKeys: nil, relativeTo: nil)
                try presetStore.save(presets)
            }
        } catch { self.error = "Choose the export folder again to restore access. \(error.localizedDescription)" }
    }
    @MainActor private func refreshEstimate() async {
        let token = ExportCancellation(); previewCancellation = token
        estimate = nil; estimateError = nil
        guard !resolving else { return }
        estimating = true
        defer { if previewCancellation === token { estimating = false } }
        do {
            try await Task.sleep(nanoseconds: 250_000_000)
            try Task.checkCancellation()
            let selectedInputs = inputs, snapshot = options
            let preview = try await Task.detached(priority: .utility) { try ExportService.estimate(inputs: selectedInputs, options: snapshot, cancellation: token) }.value
            try Task.checkCancellation()
            estimate = preview
        } catch is CancellationError { token.cancel() }
        catch WorkflowError.cancelled { }
        catch { if !Task.isCancelled { estimateError = error.localizedDescription } }
    }
    private func runExport() {
        guard let destination else { return }
        let selectedInputs = inputs, snapshot = options, token = ExportCancellation()
        cancellation = token; busy = true; result = nil; progress = 0; exportNotice = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                let output = try await Task.detached(priority: .userInitiated) {
                    try ExportService.export(inputs: selectedInputs,options: snapshot,destination: destination,cancellation: token) { fraction in Task { @MainActor in progress = fraction } }
                }.value
                result = output
                model.activity.recordExport(items: items, resultURL: output.url, options: snapshot)
            } catch WorkflowError.cancelled { progress = 0; exportNotice = "Export cancelled. No package was published." }
            catch { self.error = error.localizedDescription }
        }
    }
}
