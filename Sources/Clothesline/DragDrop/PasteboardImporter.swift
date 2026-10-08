import AppKit
import UniformTypeIdentifiers
import ClotheslineCore

/// Turns pasteboard contents (from a drop or the clipboard) into hanging items.
///
/// Preference order, most faithful first:
/// 1. File URLs (Finder, Desktop, most apps): hung by reference, never copied.
/// 2. File promises (Photos, Mail attachments, some browsers): the promised file
///    is received into Clothesline's own folder and hung as an owned copy.
/// 3. Image data (copied images, browser image drags without a promise):
///    saved as an owned PNG/JPEG.
/// 4. Web URLs: hung as link tags.
/// 5. Plain text: hung as a note (or a link if it is a single URL).
@MainActor
enum PasteboardImporter {
    static var acceptedTypes: [NSPasteboard.PasteboardType] {
        [.fileURL, .URL, .string, .png, .tiff, NSPasteboard.PasteboardType(UTType.jpeg.identifier), NSPasteboard.PasteboardType(UTType.heic.identifier)]
            + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
    }

    private static let promiseQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "app.clothesline.promises"
        q.qualityOfService = .userInitiated
        return q
    }()

    static func canImport(_ pb: NSPasteboard) -> Bool {
        pb.availableType(from: acceptedTypes) != nil
    }

    /// Imports everything usable from `pb`. Returns the ids added synchronously;
    /// file promises arrive asynchronously and are hung when received.
    @discardableResult
    static func importContents(of pb: NSPasteboard, into model: AppModel, source: ItemSource, at position: Int? = nil) -> [UUID] {
        // 1. Real files.
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            return model.hang(fileURLs: urls, source: source, at: position)
        }

        // 2. File promises — except web-location promises, where the URL itself is better.
        if let receivers = pb.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver], !receivers.isEmpty {
            let webloc = UTType("com.apple.web-internet-location")
            let useful = receivers.filter { r in
                !r.fileTypes.contains { t in UTType(t).map { webloc.map($0.conforms(to:)) ?? false } ?? false }
            }
            if !useful.isEmpty {
                receive(useful, into: model, source: source, at: position)
                return []
            }
        }

        // 3. Image data.
        if let id = importImageData(pb, into: model, source: source, at: position) {
            return [id]
        }

        // 4. Web links.
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            let links = urls.filter { !$0.isFileURL && $0.scheme != nil }
            if !links.isEmpty {
                var ids: [UUID] = []
                var pos = position
                let title = links.count == 1 ? pb.string(forType: NSPasteboard.PasteboardType("public.url-name")) : nil
                for link in links {
                    if let id = model.hang(link: link.absoluteString, title: title.flatMap { $0.isEmpty ? nil : $0 }, source: source, at: pos) {
                        ids.append(id)
                        pos = pos.map { $0 + 1 }
                    }
                }
                if !ids.isEmpty { return ids }
            }
        }

        // 5. Text.
        if let text = pb.string(forType: .string), let id = model.hang(text: text, source: source, at: position) {
            return [id]
        }
        return []
    }

    private static func importImageData(_ pb: NSPasteboard, into model: AppModel, source: ItemSource, at position: Int?) -> UUID? {
        let candidates: [(NSPasteboard.PasteboardType, String)] = [
            (.png, "png"),
            (NSPasteboard.PasteboardType(UTType.jpeg.identifier), "jpg"),
            (NSPasteboard.PasteboardType(UTType.heic.identifier), "heic"),
        ]
        for (type, ext) in candidates {
            if let data = pb.data(forType: type), !data.isEmpty {
                return model.hang(imageData: data, fileExtension: ext, suggestedName: nil, source: source, at: position)
            }
        }
        // TIFF is what most apps put on the clipboard; store it as PNG.
        if let tiff = pb.data(forType: .tiff), let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            return model.hang(imageData: png, fileExtension: "png", suggestedName: nil, source: source, at: position)
        }
        return nil
    }

    private static func receive(_ receivers: [NSFilePromiseReceiver], into model: AppModel, source: ItemSource, at position: Int?) {
        for receiver in receivers {
            let destination: URL
            do {
                // A unique folder per promise; the sender chooses the file name.
                destination = try model.store.makeOwnedFileURL(preferredName: "promise").deletingLastPathComponent()
            } catch {
                Log.error("Could not prepare a folder for a promised file: \(error.localizedDescription)")
                continue
            }
            receiver.receivePromisedFiles(atDestination: destination, options: [:], operationQueue: promiseQueue) { url, error in
                Task { @MainActor in
                    if let error {
                        Log.error("Promised file failed: \(error.localizedDescription)")
                        return
                    }
                    model.hang(fileURLs: [url], source: source, at: position, ownership: .owned)
                }
            }
        }
    }
}
