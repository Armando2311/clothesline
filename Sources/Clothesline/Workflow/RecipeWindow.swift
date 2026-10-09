import SwiftUI
import AppKit
import ClotheslineCore

struct RecipeView: View {
    @ObservedObject var model: AppModel
    let items: [HangingItem]
    @State private var options = RecipeOptions(recipe: .clientHandoff)
    @State private var destination: URL?
    @State private var inputs: [ExportInput] = []
    @State private var progress = 0.0
    @State private var busy = false
    @State private var cancellation = ExportCancellation()
    @State private var result: ExportResult?
    @State private var error: String?
    @State private var resolving = true
    @State private var scopedDestination: URL?

    var body: some View {
        VStack(alignment: .leading,spacing: 14) {
            Text("Get your collection ready").font(.title2.bold())
            Picker("Recipe",selection: Binding(get: { options.recipe },set: { recipe in options = load(recipe); result = nil })) {
                ForEach(ExportRecipe.allCases,id: \.self) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).disabled(busy || resolving)
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
                    ForEach(Array(ExportService.plannedNames(inputs: inputs,options: options).enumerated()),id: \.offset) { _,name in Text(name).font(.system(.caption,design: .monospaced)) }
                    Text("Report.md includes your notes, links and attachment references.").font(.caption).foregroundStyle(.secondary)
                    Text("Originals stay untouched. Each export gets a new folder or ZIP.").font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical,4)
            }.disabled(busy || resolving)
            if busy { ProgressView(value: progress); HStack { Text("Preparing your package…").font(.caption); Spacer(); Button("Cancel") { cancellation.cancel() } } }
            HStack {
                if let result {
                    Label("Export complete",systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([result.url]) }
                    if options.recipe == .bugReport { Button("Copy Report") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(result.report,forType: .string) } }
                }
                Spacer()
                Button("Export") { runExport() }.keyboardShortcut(.defaultAction).disabled(busy || resolving || destination == nil || items.isEmpty)
            }
        }
        .padding(22).frame(minWidth: 620,minHeight: 560)
        .alert("Could not export",isPresented: Binding(get: { error != nil },set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
        .task {
            options = load(.clientHandoff)
            let files = model.files
            inputs = await Task.detached { items.map { ExportInput(item: $0,url: $0.file.flatMap { files.resolve($0).url }) } }.value
            resolving = false
            if let data = UserDefaults.standard.data(forKey: "recipe.destination.bookmark") {
                var stale = false
                let flags: URL.BookmarkResolutionOptions = FileAccess.isSandboxed ? [.withSecurityScope,.withoutUI] : [.withoutUI]
                if let url = try? URL(resolvingBookmarkData: data,options: flags,bookmarkDataIsStale: &stale) {
                    if !FileAccess.isSandboxed || url.startAccessingSecurityScopedResource() { destination = url; if FileAccess.isSandboxed { scopedDestination = url } }
                }
            }
        }
        .onChange(of: options) { value in if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data,forKey: "recipe.\(value.recipe.rawValue)") }; result = nil }
        .onDisappear { cancellation.cancel(); scopedDestination?.stopAccessingSecurityScopedResource() }
    }
    private var imageOptions: some View {
        VStack(alignment: .leading,spacing: 10) {
            HStack {
                TextField("Filename prefix",text: $options.prefix)
                TextField("Maximum edge (px)",value: $options.maxEdge,formatter: NumberFormatter())
            }.textFieldStyle(.roundedBorder)
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
        if let data = try? url.bookmarkData(options: flags,includingResourceValuesForKeys: nil,relativeTo: nil) { UserDefaults.standard.set(data,forKey: "recipe.destination.bookmark") }
    }
    private func runExport() {
        guard let destination else { return }
        let selectedInputs = inputs, snapshot = options, token = ExportCancellation()
        cancellation = token; busy = true; result = nil; progress = 0
        Task { @MainActor in
            defer { busy = false }
            do {
                let output = try await Task.detached(priority: .userInitiated) {
                    try ExportService.export(inputs: selectedInputs,options: snapshot,destination: destination,cancellation: token) { fraction in Task { @MainActor in progress = fraction } }
                }.value
                result = output
            } catch WorkflowError.cancelled { progress = 0 }
            catch { self.error = error.localizedDescription }
        }
    }
}
