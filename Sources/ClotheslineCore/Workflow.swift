import Foundation

public enum AppearanceStyle: String, Codable, CaseIterable, Sendable {
    case illustrated, compact
    public var displayName: String { self == .compact ? "Compact" : "Illustrated" }
    public var panelHeight: Double { self == .compact ? 190 : 210 }
}

public enum ItemSearch {
    public static func results(board: Board, query: String, recognizedText: [UUID: String] = [:]) -> [HangingItem] {
        let terms = query.trimmingCharacters(in: .whitespacesAndNewlines).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return board.activeItems }
        return board.items.filter { item in
            let values = [item.title, item.text ?? "", item.link ?? "", item.file?.fileName ?? "", item.kind.displayName,
                          board.line(item.lineID)?.name ?? "", recognizedText[item.id] ?? ""]
            let haystack = values.joined(separator: " ")
            return terms.allSatisfy { haystack.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }
}

public enum ExportRecipe: String, Codable, CaseIterable, Sendable {
    case clientHandoff, bugReport, productListing
    public var title: String {
        switch self { case .clientHandoff: return "Client Handoff"; case .bugReport: return "Bug Report"; case .productListing: return "Product Listing" }
    }
}

public enum ExportImageFormat: String, Codable, CaseIterable, Sendable {
    case png, jpeg
    public var fileExtension: String { self == .jpeg ? "jpg" : "png" }
}

public struct RecipeOptions: Codable, Equatable, Sendable {
    public var recipe: ExportRecipe
    public var packageName: String
    public var prefix: String
    public var maxEdge: Int
    public var quality: Double
    public var cropRatio: Double?
    public var zip: Bool
    public var steps: String = ""
    public var expected: String = ""
    public var actual: String = ""
    public var imageFormats: [ExportImageFormat] = [.jpeg]
    public var maximumImageBytes: Int?
    public init(recipe: ExportRecipe) {
        self.recipe = recipe
        packageName = recipe.title
        prefix = recipe == .productListing ? "product" : "image"
        maxEdge = 1600
        quality = 0.85
        zip = recipe != .productListing
    }
    private enum CodingKeys: String, CodingKey {
        case recipe, packageName, prefix, maxEdge, quality, cropRatio, zip, steps, expected, actual, imageFormats, maximumImageBytes
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(recipe: try values.decode(ExportRecipe.self, forKey: .recipe))
        packageName = try values.decodeIfPresent(String.self, forKey: .packageName) ?? packageName
        prefix = try values.decodeIfPresent(String.self, forKey: .prefix) ?? prefix
        maxEdge = try values.decodeIfPresent(Int.self, forKey: .maxEdge) ?? maxEdge
        quality = try values.decodeIfPresent(Double.self, forKey: .quality) ?? quality
        cropRatio = try values.decodeIfPresent(Double.self, forKey: .cropRatio)
        zip = try values.decodeIfPresent(Bool.self, forKey: .zip) ?? zip
        steps = try values.decodeIfPresent(String.self, forKey: .steps) ?? ""
        expected = try values.decodeIfPresent(String.self, forKey: .expected) ?? ""
        actual = try values.decodeIfPresent(String.self, forKey: .actual) ?? ""
        imageFormats = try values.decodeIfPresent([ExportImageFormat].self, forKey: .imageFormats) ?? [.jpeg]
        maximumImageBytes = try values.decodeIfPresent(Int.self, forKey: .maximumImageBytes)
    }
    public func validate() throws {
        guard !imageFormats.isEmpty, Set(imageFormats).count == imageFormats.count,
              maximumImageBytes == nil || maximumImageBytes! > 0, (1...12000).contains(maxEdge), quality.isFinite, (0.05...1).contains(quality),
              cropRatio == nil || (cropRatio!.isFinite && cropRatio! > 0 && cropRatio! <= 100),
              !packageName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WorkflowError.invalidOptions
        }
    }
}

public enum WorkflowError: LocalizedError {
    case invalidOptions, unreadable(String), sizeLimit, cancelled
    public var errorDescription: String? {
        switch self {
        case .invalidOptions: return "Choose valid dimensions, quality and a package name."
        case .unreadable(let name): return "Could not read \(name). Locate the file or reconnect its drive and try again."
        case .sizeLimit: return "The image cannot fit the requested size limit. Reduce its dimensions or increase the limit."
        case .cancelled: return "Export cancelled."
        }
    }
}

public enum ExportNames {
    public static func safe(_ value: String) -> String {
        let last = value.replacingOccurrences(of: "\\", with: "/").components(separatedBy: "/").last ?? ""
        let chars = last.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) && !":/\\".unicodeScalars.contains($0) }
        let cleaned = String(String.UnicodeScalarView(chars)).trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        let possibleExtension = (cleaned as NSString).pathExtension
        let ext = possibleExtension.utf8.count <= 32 ? possibleExtension : ""
        let base = ext.isEmpty ? cleaned : (cleaned as NSString).deletingPathExtension
        let suffix = ext.isEmpty ? "" : "." + ext
        var result = ""
        for character in base {
            guard result.utf8.count + String(character).utf8.count <= 180 - suffix.utf8.count else { break }
            result.append(character)
        }
        return (result.isEmpty ? "Item" : result) + suffix
    }

    public static func unique(_ value: String, used: inout Set<String>) -> String {
        let name = safe(value)
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        var candidate = name, n = 2
        while used.contains(candidate.lowercased()) {
            candidate = "\(base) \(n)" + (ext.isEmpty ? "" : ".\(ext)")
            n += 1
        }
        used.insert(candidate.lowercased())
        return candidate
    }
}
