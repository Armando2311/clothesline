import AppKit
import UniformTypeIdentifiers
import ClotheslineCore

/// Builds the real pasteboard representations for items leaving the line, used
/// both for drag-and-drop and for ⌘C.
///
/// - Files: the file URL itself. Receivers (Finder, Mail, Messages, editors)
///   get the actual file, exactly as if it were dragged from Finder.
/// - Links: public.url plus plain text. Finder turns this into a .webloc.
/// - Notes: plain text for editors, plus a file promise so Finder can create a
///   .txt file when the note is dropped into a folder.
@MainActor
enum DragWriters {
    static func writer(for item: HangingItem, model: AppModel) -> NSPasteboardWriting? {
        switch item.kind {
        case .text:
            return NotePromiseProvider(text: item.text ?? item.title, fileName: ItemClassifier.exportFileName(for: item))
        case .link:
            guard let link = item.link else { return nil }
            let pbItem = NSPasteboardItem()
            pbItem.setString(link, forType: .URL)
            pbItem.setString(item.title, forType: NSPasteboard.PasteboardType("public.url-name"))
            pbItem.setString(link, forType: .string)
            return pbItem
        default:
            guard let url = model.url(for: item) else { return nil }
            return url as NSURL
        }
    }

    /// Copies items to the general pasteboard (⌘C).
    static func copyToPasteboard(_ items: [HangingItem], model: AppModel) -> Bool {
        let writers = items.compactMap { writer(for: $0, model: model) }
        guard !writers.isEmpty else { return false }
        let pb = NSPasteboard.general
        pb.clearContents()
        return pb.writeObjects(writers)
    }
}

/// A file promise that also offers the note's text directly.
final class NotePromiseProvider: NSFilePromiseProvider, NSFilePromiseProviderDelegate {
    let text: String
    let fileName: String

    private static let queue: OperationQueue = {
        let q = OperationQueue()
        q.name = "app.clothesline.note-promises"
        return q
    }()

    init(text: String, fileName: String) {
        self.text = text
        self.fileName = fileName
        super.init()
        self.fileType = UTType.plainText.identifier
        self.delegate = self
    }

    override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        [.string] + super.writableTypes(for: pasteboard)
    }

    override func writingOptions(forType type: NSPasteboard.PasteboardType, pasteboard: NSPasteboard) -> NSPasteboard.WritingOptions {
        type == .string ? [] : super.writingOptions(forType: type, pasteboard: pasteboard)
    }

    override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        type == .string ? text : super.pasteboardPropertyList(forType: type)
    }

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        fileName
    }

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping (Error?) -> Void) {
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }

    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
        Self.queue
    }
}
