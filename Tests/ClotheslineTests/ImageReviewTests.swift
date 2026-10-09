import XCTest
import AppKit
import ImageIO
@testable import Clothesline
import ClotheslineCore

final class ImageReviewTests: XCTestCase {
    private func fixture(alpha: CGFloat = 1) -> CGImage {
        let context = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [1, 0, 0, alpha])!)
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        return context.makeImage()!
    }
    private func pixel(_ image: CGImage, x: Int = 32, y: Int = 32) -> [UInt8] {
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: -x, y: -y, width: image.width, height: image.height))
        return Array(UnsafeBufferPointer(start: context.data!.assumingMemoryBound(to: UInt8.self), count: 4))
    }
    private func temporary() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }
    func testJPEGCompositesTransparentAndTranslucentPixelsOverWhite() throws {
        for (alpha, expected) in [(CGFloat(0), [255, 255, 255]), (CGFloat(0.5), [255, 127, 127])] {
            let data = try ImageProcessor.encode(fixture(alpha: alpha), format: .jpeg, quality: 1)
            let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
            let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            let actual = pixel(decoded)
            for component in 0..<3 { XCTAssertEqual(Int(actual[component]), expected[component], accuracy: 3) }
            XCTAssertEqual(actual[3], 255)
        }
    }
    func testPNGPreservesTransparency() throws {
        let data = try ImageProcessor.encode(fixture(alpha: 0.5), format: .png, quality: 1)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(Int(pixel(decoded)[3]), 128, accuracy: 1)
    }
    func testZeroLengthArrowAndRedactionLeavePixelsUntouched() throws {
        for kind in [ImageMark.Kind.arrow, .redact] {
            var edits = ImageEdits()
            edits.marks = [ImageMark(kind: kind, start: CGPoint(x: 0.5, y: 0.5), end: CGPoint(x: 0.5, y: 0.5))]
            let result = try ImageProcessor.render(fixture(), edits: edits)
            for x in 20...33 {
                for y in 31...32 { XCTAssertEqual(pixel(result, x: x, y: y), [255, 0, 0, 255]) }
            }
        }
    }
    func testNumberClickStillDrawsMarker() throws {
        var edits = ImageEdits()
        edits.marks = [ImageMark(kind: .number, start: CGPoint(x: 0.5, y: 0.5), end: CGPoint(x: 0.5, y: 0.5))]
        XCTAssertNotEqual(pixel(try ImageProcessor.render(fixture(), edits: edits), x: 24), [255, 0, 0, 255])
    }
    func testClickDoesNotCreateDragEditsButNumbersStillAdvance() {
        var edits = ImageEdits()
        let point = CGPoint(x: 0.5, y: 0.5)
        for tool in ["Arrow", "Redact", "Crop"] {
            XCTAssertFalse(edits.applyGesture(tool: tool, start: point, end: point))
            XCTAssertEqual(edits, ImageEdits())
        }
        XCTAssertTrue(edits.applyGesture(tool: "Number", start: point, end: point))
        XCTAssertTrue(edits.applyGesture(tool: "Number", start: point, end: point))
        XCTAssertEqual(edits.marks.map(\.number), [1, 2])
    }
    func testConfirmedSaveReplacesExistingResultWithoutLeavingTemporaryFiles() throws {
        let directory = try temporary(), destination = directory.appendingPathComponent("result.png")
        try Data("original".utf8).write(to: destination)
        let replacement = try ImageProcessor.encode(fixture(), format: .png, quality: 1)
        try ImageProcessor.saveResult(replacement, to: destination)
        XCTAssertEqual(try Data(contentsOf: destination), replacement)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["result.png"])
    }
    func testExportCancellationNeverStagesInDestination() throws {
        let destination = try temporary()
        let item = HangingItem(kind: .text, source: .manual, title: "Note", lineID: UUID(), text: "hello")
        let cancellation = ExportCancellation()
        var options = RecipeOptions(recipe: .clientHandoff); options.zip = false
        var observedEntries: [String] = []
        XCTAssertThrowsError(try ExportService.export(inputs: [ExportInput(item: item, url: nil)], options: options,
                                                     destination: destination, cancellation: cancellation) { progress in
            if progress < 1 {
                observedEntries = (try? FileManager.default.contentsOfDirectory(atPath: destination.path)) ?? []
                cancellation.cancel()
            }
        })
        XCTAssertEqual(observedEntries, [])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path), [])
    }
    func testSaveNeverReplacesOriginalOrAlias() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("original.png")
        let original = Data("original".utf8)
        try original.write(to: source)
        let link = root.appendingPathComponent("alias.png")
        try FileManager.default.linkItem(at: source,to: link)
        let symlink = root.appendingPathComponent("symlink.png")
        try FileManager.default.createSymbolicLink(at: symlink,withDestinationURL: source)
        for destination in [source,link,symlink] {
            XCTAssertThrowsError(try ImageProcessor.saveResult(Data("replacement".utf8),to: destination,protecting: source))
            XCTAssertEqual(try Data(contentsOf: source),original)
        }
    }

}
