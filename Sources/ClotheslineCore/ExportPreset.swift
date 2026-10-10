import Foundation

public struct ExportPreset: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var options: RecipeOptions
    public var destinationBookmark: Data?
    public var destinationPath: String?
    public init(id: UUID = UUID(), name: String, options: RecipeOptions,
                destinationBookmark: Data? = nil, destinationPath: String? = nil) {
        self.id = id; self.name = name; self.options = options
        self.destinationBookmark = destinationBookmark; self.destinationPath = destinationPath
    }
}

/// Separate atomic storage keeps named presets independent of board recovery.
public final class ExportPresetStore {
    public let url: URL
    public init(directory: URL) { url = directory.appendingPathComponent("export-presets.json") }
    public func load() throws -> [ExportPreset] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let presets = try JSONDecoder().decode([ExportPreset].self, from: Data(contentsOf: url))
        for preset in presets {
            try preset.options.validate()
            guard !preset.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WorkflowError.invalidOptions }
        }
        return presets
    }
    public func save(_ presets: [ExportPreset]) throws {
        for preset in presets {
            guard !preset.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WorkflowError.invalidOptions }
            try preset.options.validate()
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(presets).write(to: url, options: .atomic)
    }
}
