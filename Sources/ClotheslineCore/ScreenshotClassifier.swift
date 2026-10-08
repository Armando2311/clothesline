import Foundation

/// The parts of the macOS screenshot configuration Clothesline cares about.
/// Values come from the `com.apple.screencapture` preferences domain, which is
/// what both the keyboard shortcuts and the Screenshot app (⇧⌘5) use.
public struct ScreenshotPreferences: Equatable, Sendable {
    /// `location` key. `nil` means the macOS default (the Desktop).
    public var location: String?
    /// `target` key: "file", "clipboard", "preview", "mail", "messages".
    /// `nil` means "file".
    public var target: String?
    /// `name` key: a custom filename prefix, if the user set one with `defaults`.
    public var namePrefix: String?

    public init(location: String? = nil, target: String? = nil, namePrefix: String? = nil) {
        self.location = location
        self.target = target
        self.namePrefix = namePrefix
    }

    /// True when screenshots are written to disk (the only case Clothesline can
    /// observe without clipboard monitoring).
    public var savesToFile: Bool {
        guard let target, !target.isEmpty else { return true }
        return target == "file"
    }

    /// Resolves the folder screenshots are saved to.
    public func resolvedFolder(homeDirectory: String) -> URL {
        let desktop = URL(fileURLWithPath: homeDirectory).appendingPathComponent("Desktop", isDirectory: true)
        guard var raw = location?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return desktop
        }
        if raw.hasPrefix("file://"), let url = URL(string: raw), url.isFileURL {
            raw = url.path
        }
        if raw == "~" {
            raw = homeDirectory
        } else if raw.hasPrefix("~/") {
            raw = homeDirectory + String(raw.dropFirst(1))
        }
        guard raw.hasPrefix("/") else { return desktop }
        return URL(fileURLWithPath: raw, isDirectory: true).standardizedFileURL
    }
}

/// Decides whether a newly appeared file is a screenshot.
///
/// The primary signal is the `com.apple.metadata:kMDItemIsScreenCapture`
/// extended attribute that `screencapture` writes onto every screenshot file.
/// It is local, needs no Spotlight index and survives custom file names. The
/// filename heuristics are only a fallback for files that have no such
/// attribute (e.g. volumes without xattr support), and in that case the file
/// must also be brand new so old files copied into the folder are not imported.
public struct ScreenshotClassifier: Sendable {
    public static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "tiff", "tif", "gif", "pdf", "bmp"]
    public static let recordingExtensions: Set<String> = ["mov", "mp4"]

    /// Default prefixes macOS uses for screenshot file names in common locales.
    /// Only consulted when the screen-capture attribute is unavailable.
    public static let knownPrefixes: [String] = [
        "Screenshot", "Screen Shot", "Bildschirmfoto", "Capture d’écran", "Capture d'écran",
        "Captura de pantalla", "Istantanea schermo", "Schermafbeelding", "Skärmavbild",
        "Skjermbilde", "Skærmbillede", "Näyttökuva", "Zrzut ekranu", "Snímek obrazovky",
        "Captura de Tela", "Captura de ecrã", "Снимок экрана", "スクリーンショット",
        "截屏", "螢幕截圖", "스크린샷", "Ekran Resmi", "Ảnh màn hình",
    ]

    public var includeRecordings: Bool
    public var customPrefix: String?
    /// How recently a file must have been created for the filename fallback.
    public var freshnessWindow: TimeInterval

    public init(includeRecordings: Bool = false, customPrefix: String? = nil, freshnessWindow: TimeInterval = 120) {
        self.includeRecordings = includeRecordings
        self.customPrefix = customPrefix
        self.freshnessWindow = freshnessWindow
    }

    /// Evidence gathered about one file.
    public struct Candidate: Sendable {
        public var fileName: String
        public var isDirectory: Bool
        /// `true`/`false` if the attribute could be read; `nil` if unknown.
        public var hasScreenCaptureAttribute: Bool?
        public var creationDate: Date?

        public init(fileName: String, isDirectory: Bool = false, hasScreenCaptureAttribute: Bool?, creationDate: Date?) {
            self.fileName = fileName
            self.isDirectory = isDirectory
            self.hasScreenCaptureAttribute = hasScreenCaptureAttribute
            self.creationDate = creationDate
        }
    }

    public enum Verdict: Equatable, Sendable {
        case screenshot
        case recording
        case notScreenshot
    }

    public func classify(_ c: Candidate, now: Date = Date()) -> Verdict {
        // screencapture first writes a hidden ".Screenshot …" temp file and then
        // renames it; only the final, visible name is complete.
        if c.fileName.hasPrefix(".") || c.isDirectory { return .notScreenshot }
        let ext = (c.fileName as NSString).pathExtension.lowercased()
        let isImage = Self.imageExtensions.contains(ext)
        let isRecording = Self.recordingExtensions.contains(ext)
        guard isImage || (isRecording && includeRecordings) else { return .notScreenshot }

        let hit: Verdict = isRecording ? .recording : .screenshot
        if c.hasScreenCaptureAttribute == true { return hit }

        // Fallback: name-based detection for brand-new files only.
        guard matchesScreenshotName(c.fileName) else { return .notScreenshot }
        guard let created = c.creationDate, now.timeIntervalSince(created) <= freshnessWindow,
              created.timeIntervalSince(now) < 5 else { return .notScreenshot }
        return hit
    }

    public func matchesScreenshotName(_ fileName: String) -> Bool {
        let stem = (fileName as NSString).deletingPathExtension
        var prefixes = Self.knownPrefixes
        if let customPrefix, !customPrefix.isEmpty { prefixes.insert(customPrefix, at: 0) }
        for prefix in prefixes where stem.hasPrefix(prefix) {
            let rest = stem.dropFirst(prefix.count)
            if rest.isEmpty { return true }
            // "Screenshot 2", "Screenshot 2024-05-01 at 10.12.33", "Screenshot 2024-05-01 at 10.12.33 (2)"
            if rest.first == " " || rest.first == "_" || rest.first == "-" { return true }
        }
        return false
    }
}
