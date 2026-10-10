import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ClotheslineCore

struct ImageEditor: View {
    @ObservedObject var model: AppModel
    let reference: FileReference
    let title: String
    @State private var source: CGImage?
    @State private var preview: NSImage?
    @State private var edits = ImageEdits()
    @State private var history: [ImageEdits] = []
    @State private var tool = "Arrow"
    @State private var format: ImageFormat = .png
    @State private var quality = 0.85
    @State private var limitEnabled = false
    @State private var limitMB = 5.0
    @State private var status = "Loading image…"
    @State private var error: String?
    @State private var working = false
    @State private var pending: CGRect?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Prepare Image").font(.title2.bold())
                Spacer()
                Button("Undo") { if let prior = history.popLast() { edits = prior } }.disabled(history.isEmpty || working).keyboardShortcut("z")
                Button("Reset") { remember(); if let source { edits = ImageEdits(); edits.maxEdge = max(source.width,source.height) } }.disabled(source == nil || working)
            }.padding(18)
            Divider()
            HStack(alignment: .top,spacing: 18) {
                imageCanvas
                VStack(alignment: .leading,spacing: 16) {
                    Text("Tools").font(.headline)
                    Picker("Tool",selection: $tool) { ForEach(["Crop","Arrow","Number","Redact"],id: \.self) { Text($0) } }.pickerStyle(.radioGroup)
                    Text(tool == "Number" ? "Click to add the next numbered marker." : "Drag on the image to apply this tool.").font(.caption).foregroundStyle(.secondary)
                    Divider()
                    Text("Output").font(.headline)
                    TextField("Maximum edge (pixels)",value: $edits.maxEdge,formatter: NumberFormatter()).textFieldStyle(.roundedBorder)
                    Text("Resize keeps the aspect ratio and never enlarges the image.").font(.caption).foregroundStyle(.secondary)
                    Picker("Format",selection: $format) { Text("PNG").tag(ImageFormat.png); Text("JPEG").tag(ImageFormat.jpeg) }
                    if format == .jpeg {
                        Text("Quality: \(Int(quality * 100))%")
                        Slider(value: $quality,in: 0.05...1)
                        Toggle("Limit file size",isOn: $limitEnabled)
                        if limitEnabled { TextField("Maximum MB",value: $limitMB,formatter: NumberFormatter()).textFieldStyle(.roundedBorder) }
                    }
                    Spacer()
                    Text("Your original stays untouched. Redaction is applied to the exported image.").font(.caption).foregroundStyle(.secondary)
                }.frame(width: 210).disabled(working || source == nil)
            }.padding(18)
            Divider()
            HStack {
                if working { ProgressView().controlSize(.small) }
                Text(status).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Copy Result") { output(.copy) }
                Button("Hang Result") { output(.hang) }
                Button("Save Result…") { output(.save) }.keyboardShortcut("s")
            }.disabled(working || source == nil).padding(18)
        }
        .premiumAnimation(value: tool)
        .premiumAnimation(value: format)
        .premiumAnimation(value: limitEnabled)
        .premiumAnimation(value: working)
        .frame(minWidth: 850,minHeight: 600)
        .alert("Could not prepare the image",isPresented: Binding(get: { error != nil },set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
        .task {
            let files = model.files
            do {
                let image = try await Task.detached(priority: .userInitiated) { () throws -> CGImage in
                    guard let url = files.resolve(reference).url else { throw WorkflowError.unreadable(title) }
                    return try ImageProcessor.load(url)
                }.value
                source = image; edits.maxEdge = max(image.width,image.height)
                await updatePreview()
            } catch { self.error = error.localizedDescription; status = "Image unavailable" }
        }
        .task(id: edits) { await updatePreview() }
    }
    private var imageCanvas: some View {
        GeometryReader { proxy in
            if let preview {
                let ratio = preview.size.width/preview.size.height
                let w = min(proxy.size.width,proxy.size.height*ratio), h = w/ratio
                VStack {
                    Spacer(minLength: 0)
                    HStack {
                        Spacer(minLength: 0)
                        Image(nsImage: preview).resizable().frame(width: w,height: h)
                            .overlay { if let pending { Rectangle().stroke(Color.accentColor,lineWidth: 2).frame(width: pending.width*w,height: pending.height*h).position(x: pending.midX*w,y: pending.midY*h) } }
                            .contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                                let a = unit(value.startLocation,width: w,height: h), b = unit(value.location,width: w,height: h)
                                pending = rect(a,b)
                            }.onEnded { value in
                                pending = nil
                                let a = unit(value.startLocation,width: w,height: h), b = unit(value.location,width: w,height: h)
                                var next = edits
                                guard next.applyGesture(tool: tool, start: a, end: b) else { return }
                                remember()
                                edits = next
                            })
                        Spacer(minLength: 0)
                    }
                    Spacer(minLength: 0)
                }
            } else { ProgressView().frame(maxWidth: .infinity,maxHeight: .infinity) }
        }.background(Color.primary.opacity(0.05)).cornerRadius(8).disabled(working)
    }
    private func unit(_ point: CGPoint,width: CGFloat,height: CGFloat) -> CGPoint { CGPoint(x: min(1,max(0,point.x/width)),y: min(1,max(0,point.y/height))) }
    private func rect(_ a: CGPoint,_ b: CGPoint) -> CGRect { CGRect(x: min(a.x,b.x),y: min(a.y,b.y),width: abs(a.x-b.x),height: abs(a.y-b.y)) }
    private func remember() { history.append(edits); if history.count > 50 { history.removeFirst() } }
    @MainActor private func updatePreview() async {
        guard let source else { return }
        let snapshot = edits
        do {
            let out = try await Task.detached(priority: .userInitiated) { try ImageProcessor.render(source,edits: snapshot) }.value
            guard !Task.isCancelled, edits == snapshot else { return }
            preview = NSImage(cgImage: out,size: CGSize(width: out.width,height: out.height))
            status = "\(out.width) × \(out.height) pixels"
        } catch { status = error.localizedDescription }
    }
    private enum Output { case copy, hang, save }
    private func output(_ action: Output) {
        guard let source else { return }
        var destination: URL?
        if action == .save {
            let panel = NSSavePanel(); panel.level = WorkflowPresentation.modalLevel; panel.allowedContentTypes = [format == .png ? .png : .jpeg]
            panel.nameFieldStringValue = ExportNames.safe(title) + "-edited." + (format == .png ? "png" : "jpg")
            guard panel.runModal() == .OK, let url = panel.url else { return }
            destination = url
        }
        let originalURL = model.files.resolve(reference).url ?? reference.url
        let snapshot = edits, outputFormat = format, outputQuality = quality
        if limitEnabled && format == .jpeg && (!limitMB.isFinite || limitMB <= 0 || limitMB > 1000) { error = "Choose a size limit between 0 and 1000 MB."; return }
        let bytes = limitEnabled && format == .jpeg ? Int(limitMB*1_000_000) : nil
        working = true
        Task { @MainActor in
            defer { working = false }
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    try ImageProcessor.encode(ImageProcessor.render(source,edits: snapshot),format: outputFormat,quality: outputQuality,maxBytes: bytes)
                }.value
                switch action {
                case .copy:
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setData(data,forType: outputFormat == .png ? .png : NSPasteboard.PasteboardType("public.jpeg"))
                case .hang:
                    guard model.hang(imageData: data,fileExtension: outputFormat == .png ? "png" : "jpg",suggestedName: title+"-edited",source: .manual) != nil else { throw WorkflowError.unreadable("the prepared image") }
                case .save:
                    if let destination { try await Task.detached { try ImageProcessor.saveResult(data, to: destination, protecting: originalURL) }.value }
                }
                status = "\(action == .copy ? "Copied" : action == .hang ? "Hung on the line" : "Saved") · \(ByteCountFormatter.string(fromByteCount: Int64(data.count),countStyle: .file))"
            } catch { self.error = error.localizedDescription }
        }
    }
}
