import SwiftUI
import AppKit
import ClotheslineCore

struct CollectionView: View {
    @ObservedObject var model: AppModel
    let actions: WorkflowActions
    var body: some View {
        VStack(spacing: 0) {
            LineControls(model: model, action: { action, anchor in actions.perform(action, from: anchor) },searchTarget: "collection").padding(8)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160),spacing: 14)],spacing: 14) {
                    ForEach(model.visibleItems) { item in
                        VStack(spacing: 8) {
                            CollectionThumbnail(model: model,item: item).frame(height: 105)
                            Text(item.title).font(.body.weight(.medium)).lineLimit(2).frame(height: 35)
                            Text(model.board.line(item.lineID)?.name ?? item.kind.displayName).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(10).frame(maxWidth: .infinity)
                        .background(model.selectedIDs.contains(item.id) ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.04))
                        .cornerRadius(10).overlay(RoundedRectangle(cornerRadius: 10).stroke(model.selectedIDs.contains(item.id) ? Color.accentColor : .clear,lineWidth: 2))
                        .contentShape(Rectangle())
                        .overlay(CollectionDragSurface(model: model,item: item,actions: actions))
                    }
                }.padding(18)
                if model.visibleItems.isEmpty { Text(model.isSearching ? "No matching items. Try another word." : "Drop files on your line to get started.").foregroundStyle(.secondary).padding(40) }
            }
            HStack { Text("⌘-click to select several items · Double-click to open · Originals stay untouched").font(.caption).foregroundStyle(.secondary); Spacer() }.padding(12)
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
        .overlay(alignment: .topLeading) { if let availability = model.availability[item.id], availability != .available { Text(availability == .missing ? "MISSING" : "OFFLINE").font(.caption.bold()).foregroundStyle(.red) } }
        .task(id: item.file?.path) {
            if let url = model.url(for: item) {
                if [.image,.screenshot,.pdf].contains(item.kind) {
                    model.thumbnails.thumbnail(for: url,size: CGSize(width: 160,height: 110),scale: 2) { cg in if let cg { image = NSImage(cgImage: cg,size: .zero) } }
                } else { image = NSWorkspace.shared.icon(forFile: url.path) }
            }
        }
    }
}
