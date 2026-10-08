import Foundation

/// What an item on the line represents. The kind decides how it is drawn
/// (photo print, paper sheet, folder, note card, tag) and how it is dragged out.
public enum ItemKind: String, Codable, CaseIterable, Sendable {
    case screenshot
    case image
    case pdf
    case folder
    case file
    case text
    case link

    public var displayName: String {
        switch self {
        case .screenshot: return "Screenshot"
        case .image: return "Image"
        case .pdf: return "PDF"
        case .folder: return "Folder"
        case .file: return "File"
        case .text: return "Note"
        case .link: return "Link"
        }
    }

    /// Whether the item is backed by a file on disk.
    public var isFileBacked: Bool {
        switch self {
        case .text, .link: return false
        default: return true
        }
    }
}

/// How an item got onto the line. Used for organisation and retention rules.
public enum ItemSource: String, Codable, Sendable {
    case screenshot
    case drop
    case clipboard
    case manual
}

/// Who owns the file behind a file-backed item.
///
/// This is the core of Clothesline's file-safety model:
/// - `.referenced`: the user's own file. Clothesline only remembers where it is.
///   Removing the item from the line never touches the file.
/// - `.owned`: a copy Clothesline created itself (e.g. an image dragged out of a
///   browser, a file promise, clipboard image data). It lives in Clothesline's
///   Application Support folder and is deleted when the item is removed, because
///   no one else has a reference to it.
public enum FileOwnership: String, Codable, Sendable {
    case referenced
    case owned
}

/// A durable pointer to a file on disk.
public struct FileReference: Codable, Equatable, Sendable {
    /// Last known path. Used for display and as a fallback when the bookmark
    /// cannot be resolved (e.g. bookmark data from a different machine).
    public var path: String
    /// Bookmark data. Bookmarks follow renames and moves on the same volume and
    /// carry security scope when the app runs sandboxed.
    public var bookmark: Data?
    public var ownership: FileOwnership

    public init(path: String, bookmark: Data?, ownership: FileOwnership) {
        self.path = path
        self.bookmark = bookmark
        self.ownership = ownership
    }

    public var url: URL { URL(fileURLWithPath: path) }
    public var fileName: String { (path as NSString).lastPathComponent }
}

/// One object hanging on a clothesline.
public struct HangingItem: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var kind: ItemKind
    public var source: ItemSource
    public var title: String
    public var dateAdded: Date
    public var lineID: UUID
    public var pinned: Bool
    public var file: FileReference?
    public var text: String?
    public var link: String?

    public init(
        id: UUID = UUID(),
        kind: ItemKind,
        source: ItemSource,
        title: String,
        dateAdded: Date = Date(),
        lineID: UUID,
        pinned: Bool = false,
        file: FileReference? = nil,
        text: String? = nil,
        link: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.source = source
        self.title = title
        self.dateAdded = dateAdded
        self.lineID = lineID
        self.pinned = pinned
        self.file = file
        self.text = text
        self.link = link
    }

    /// A key used to avoid hanging the same thing twice on one line.
    public var dedupeKey: String {
        if let file { return "file:" + (file.path as NSString).standardizingPath }
        if let link { return "link:" + link }
        if let text { return "text:" + text }
        return "id:" + id.uuidString
    }

    /// A deterministic pseudo-random value in [-1, 1] derived from the item id,
    /// used to give each item a stable, organic tilt and offset. Stable across
    /// launches so the line does not reshuffle every time it opens.
    public func jitter(_ channel: UInt64) -> Double {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325 ^ channel &* 0x9E37_79B9_7F4A_7C15
        withUnsafeBytes(of: id.uuid) { raw in
            for b in raw {
                h ^= UInt64(b)
                h = h &* 0x100_0000_01b3
            }
        }
        // xorshift finaliser for better distribution
        h ^= h >> 33
        h = h &* 0xff51_afd7_ed55_8ccd
        h ^= h >> 33
        return Double(h % 2_000_001) / 1_000_000.0 - 1.0
    }
}

/// A named clothesline. Users can keep several (e.g. Work, Personal, Temporary).
public struct Line: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    /// If set, unpinned items on this line are removed from it after this many hours.
    public var expiryHours: Double?

    public init(id: UUID = UUID(), name: String, expiryHours: Double? = nil) {
        self.id = id
        self.name = name
        self.expiryHours = expiryHours
    }
}
