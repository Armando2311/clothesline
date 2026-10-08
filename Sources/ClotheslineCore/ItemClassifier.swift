import Foundation

/// Classifies incoming content into item kinds.
public enum ItemClassifier {
    static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "heif", "tiff", "tif", "gif", "bmp", "webp", "avif", "raw", "dng", "svg", "ico", "icns",
    ]

    /// Kind for a file on disk. Packages such as `.app` or `.key` are treated as
    /// files, not folders, matching how Finder presents them.
    public static func kind(forFileName name: String, isDirectory: Bool, isPackage: Bool = false) -> ItemKind {
        if isDirectory && !isPackage { return .folder }
        let ext = (name as NSString).pathExtension.lowercased()
        if ext == "pdf" { return .pdf }
        if imageExtensions.contains(ext) { return .image }
        return .file
    }

    /// Display title for a file: the name without the extension for images and
    /// screenshots (the print says what it is), the full name otherwise.
    public static func title(forFileName name: String, kind: ItemKind) -> String {
        switch kind {
        case .screenshot, .image:
            return (name as NSString).deletingPathExtension
        default:
            return name
        }
    }

    /// If `string` is a single web link (optionally surrounded by whitespace),
    /// returns it normalised; otherwise `nil`. Plain words are never turned into
    /// links, so dropping "hello.txt" as text stays a note.
    public static func link(from string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: { $0.isWhitespace }) else { return nil }
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else { return nil }
        switch scheme {
        case "http", "https":
            guard let host = url.host, host.contains(".") || host == "localhost" else { return nil }
            return trimmed
        case "mailto", "ftp", "sftp", "ssh", "x-apple.systempreferences":
            return trimmed
        default:
            return nil
        }
    }

    /// Short human title for a link: host plus a hint of the path.
    public static func title(forLink link: String) -> String {
        guard let url = URL(string: link) else { return link }
        if url.scheme?.lowercased() == "mailto" {
            return String(link.dropFirst("mailto:".count))
        }
        var host = url.host ?? link
        if host.hasPrefix("www.") { host.removeFirst(4) }
        let path = url.path
        if path.isEmpty || path == "/" { return host }
        let last = (path as NSString).lastPathComponent
        return "\(host) › \(last)"
    }

    /// A title for a text note: its first non-empty line, shortened.
    public static func title(forText text: String, maxLength: Int = 60) -> String {
        let firstLine = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? "Note"
        if firstLine.count <= maxLength { return firstLine }
        return String(firstLine.prefix(maxLength - 1)) + "…"
    }

    /// A file name used when a note or link is dragged out as a file.
    public static func exportFileName(for item: HangingItem) -> String {
        switch item.kind {
        case .text:
            return BoardStore.sanitizedFileName(String(title(forText: item.text ?? "", maxLength: 40).prefix(40))) + ".txt"
        case .link:
            return BoardStore.sanitizedFileName(String(title(forLink: item.link ?? "").prefix(60))) + ".webloc"
        default:
            return item.file?.fileName ?? BoardStore.sanitizedFileName(item.title)
        }
    }
}
