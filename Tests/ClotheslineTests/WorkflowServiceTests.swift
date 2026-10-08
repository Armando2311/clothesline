import XCTest
import AppKit
import ImageIO
import UniformTypeIdentifiers
@testable import Clothesline
import ClotheslineCore

final class WorkflowServiceTests: XCTestCase {
    private func fixture() -> CGImage {
        let c = CGContext(data: nil, width: 100, height: 60, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: 100, height: 60))
        return c.makeImage()!
    }
    private func temporary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    func testResizeCropAndFlattenedOpaqueRedaction() throws {
        var edits = ImageEdits()
        edits.maxEdge = 50
        edits.marks = [ImageMark(kind: .redact, start: CGPoint(x: 0.2, y: 0.2), end: CGPoint(x: 0.8, y: 0.8))]
        let out = try ImageProcessor.render(fixture(), edits: edits)
        XCTAssertEqual(out.width, 50); XCTAssertEqual(out.height, 30)
        let pixel = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        pixel.draw(out, in: CGRect(x: -25, y: -15, width: 50, height: 30))
        let bytes = pixel.data!.assumingMemoryBound(to: UInt8.self)
        XCTAssertEqual(bytes[0], 0); XCTAssertEqual(bytes[3], 255)
        edits = ImageEdits(); edits.crop = CGRect(x: 0, y: 0, width: 0.5, height: 1)
        XCTAssertEqual(try ImageProcessor.render(fixture(), edits: edits).width, 50)
    }
    func testJPEGSizeLimitAndImpossibleLimit() throws {
        let data = try ImageProcessor.encode(fixture(), format: .jpeg, quality: 0.85, maxBytes: 5000)
        XCTAssertLessThanOrEqual(data.count, 5000)
        XCTAssertThrowsError(try ImageProcessor.encode(fixture(), format: .jpeg, quality: 0.85, maxBytes: 1))
    }
    func testExportCopiesOriginalAndAvoidsCollisions() throws {
        let root = try temporary(), src = root.appendingPathComponent("original.png")
        let original = try ImageProcessor.encode(fixture(), format: .png, quality: 1)
        try original.write(to: src)
        let line = UUID()
        let item = HangingItem(kind: .image, source: .drop, title: "Picture", lineID: line)
        let input = ExportInput(item: item, url: src)
        var options = RecipeOptions(recipe: .productListing); options.packageName = "Listing"
        let first = try ExportService.export(inputs: [input], options: options, destination: root)
        let second = try ExportService.export(inputs: [input], options: options, destination: root)
        XCTAssertNotEqual(first.url, second.url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.url.appendingPathComponent("product-001.jpg").path))
        XCTAssertEqual(try Data(contentsOf: src), original)
    }
    func testMixedZIPIncludesManifestAndUniqueAttachments() throws {
        let root = try temporary(), a = root.appendingPathComponent("a"), b = root.appendingPathComponent("b")
        try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        let first = a.appendingPathComponent("report.txt"), second = b.appendingPathComponent("report.txt")
        try Data("first".utf8).write(to: first); try Data("second".utf8).write(to: second)
        let line = UUID()
        let items = [HangingItem(kind: .file, source: .drop, title: "Report", lineID: line), HangingItem(kind: .file, source: .drop, title: "Report", lineID: line)]
        let note = HangingItem(kind: .text, source: .manual, title: "Note", lineID: line, text: "Check the invoice")
        let result = try ExportService.export(inputs: [ExportInput(item: items[0], url: first), ExportInput(item: items[1], url: second), ExportInput(item: note, url: nil)], options: RecipeOptions(recipe: .bugReport), destination: root)
        XCTAssertEqual(result.url.pathExtension, "zip")
        XCTAssertTrue(result.report.contains("report 2.txt")); XCTAssertTrue(result.report.contains("Check the invoice"))
        let unpacked = root.appendingPathComponent("Unpacked")
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", result.url.path, unpacked.path]
        try process.run(); process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: unpacked.appendingPathComponent("Bug Report/Report.md").path))
    }
    func testMissingInputAndCancellationLeaveNoOutput() throws {
        let root = try temporary()
        let item = HangingItem(kind: .file, source: .drop, title: "Missing", lineID: UUID())
        XCTAssertThrowsError(try ExportService.export(inputs: [ExportInput(item: item, url: root.appendingPathComponent("missing"))], options: RecipeOptions(recipe: .clientHandoff), destination: root))
        let cancel = ExportCancellation(); cancel.cancel()
        XCTAssertThrowsError(try ExportService.export(inputs: [], options: RecipeOptions(recipe: .clientHandoff), destination: root, cancellation: cancel))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    }
}

extension WorkflowServiceTests {
    @MainActor func testSearchSelectionResetsWithoutChangingBoardOrder() async throws {
        let root = try temporary()
        let saved = UserDefaults.standard.data(forKey: "settings.v1")
        defer { if let saved { UserDefaults.standard.set(saved, forKey: "settings.v1") } else { UserDefaults.standard.removeObject(forKey: "settings.v1") } }
        let model = AppModel(store: BoardStore(directory: root))
        let a = model.hang(text: "Work note", source: .manual)!
        let line = model.addLine(named: "Other")
        let b = model.hang(text: "Invoice café", source: .manual)!
        model.query = "CAFE"
        XCTAssertEqual(model.visibleItems.map(\.id), [b])
        model.selectedIDs = [b]
        model.query = "Work"
        XCTAssertTrue(model.selectedIDs.isEmpty)
        XCTAssertEqual(model.visibleItems.map(\.id), [a])
        model.query = ""
        XCTAssertEqual(model.visibleItems.map(\.id), [b])
        XCTAssertEqual(model.board.items.map(\.id), [a,b])
        XCTAssertEqual(model.board.activeLineID, line.id)
    }
}
