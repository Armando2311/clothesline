import XCTest
@testable import ClotheslineCore

final class ExportPresetTests: XCTestCase {
    func testLegacyOptionsDefaultNewFields() throws {
        let data = Data(#"{"recipe":"clientHandoff","packageName":"Legacy","prefix":"photo","maxEdge":1600,"quality":0.85,"zip":true}"#.utf8)
        let value = try JSONDecoder().decode(RecipeOptions.self, from: data)
        XCTAssertEqual(value.imageFormats, [.jpeg])
        XCTAssertNil(value.maximumImageBytes)
        XCTAssertEqual(value.steps, "")
    }
    func testPresetRoundTripKeepsOptionsAndDestination() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var options = RecipeOptions(recipe: .productListing)
        options.imageFormats = [.png, .jpeg]
        options.maximumImageBytes = 250_000
        let preset = ExportPreset(name: "Marketplace", options: options, destinationBookmark: Data([1,2]), destinationPath: "/Export")
        let store = ExportPresetStore(directory: directory)
        try store.save([preset])
        XCTAssertEqual(try store.load(), [preset])
    }
    func testInvalidPersistedPresetIsRejectedAndPreserved() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = ExportPresetStore(directory: directory)
        var options = RecipeOptions(recipe: .productListing); options.maxEdge = 0
        let data = try JSONEncoder().encode([ExportPreset(name: "Invalid", options: options)])
        try data.write(to: store.url)
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try Data(contentsOf: store.url), data)
    }
    func testImageOptionsRejectEmptyFormatsAndNonPositiveLimit() throws {
        var options = RecipeOptions(recipe: .productListing)
        options.imageFormats = []
        XCTAssertThrowsError(try options.validate())
        options.imageFormats = [.jpeg]
        options.maximumImageBytes = 0
        XCTAssertThrowsError(try options.validate())
    }
}
