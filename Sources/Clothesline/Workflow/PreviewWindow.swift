import SwiftUI
import QuickLookUI

struct CollectionPreview: View {
    var entries: [(String, URL)]
    @State private var index = 0
    var body: some View {
        VStack {
            Picker("Item",selection: $index) { ForEach(entries.indices,id: \.self) { Text(entries[$0].0).tag($0) } }.padding(12)
            NativePreview(url: entries[index].1)
        }.frame(minWidth: 480,minHeight: 360)
    }
}
private struct NativePreview: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero,style: .normal)!
        // SwiftUI owns teardown; prevent Quick Look from closing a second time with its window.
        view.shouldCloseWithWindow = false
        return view
    }
    func updateNSView(_ view: QLPreviewView,context: Context) { view.previewItem = url as NSURL }
    static func dismantleNSView(_ view: QLPreviewView,coordinator: ()) { view.close() }
}
struct ControlAnchor: NSViewRepresentable {
    var ready: (NSView) -> Void
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { ready(view) }
        return view
    }
    func updateNSView(_ view: NSView,context: Context) {}
}
