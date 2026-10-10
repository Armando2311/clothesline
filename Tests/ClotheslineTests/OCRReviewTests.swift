import XCTest
import AppKit
import ImageIO
import UniformTypeIdentifiers
import ClotheslineCore
@testable import Clothesline

final class OCRReviewTests: XCTestCase {
    private func temporary() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func image(at url: URL, width: Int = 100, height: Int = 60) throws {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    @MainActor private func recognize(_ index: OCRIndex, url: URL) async throws -> String {
        let id = UUID(), ready = expectation(description: "OCR published")
        var result = ""
        index.changed = { values in
            if let value = values[id] { result = value; ready.fulfill() }
        }
        index.refresh([(id, url)])
        await fulfillment(of: [ready], timeout: 5)
        index.stop()
        return result
    }

    @MainActor func testDurableCacheSurvivesNewIndexAndInvalidatesChangedFile() async throws {
        let root = try temporary(), url = root.appendingPathComponent("image.png"), cache = root.appendingPathComponent("ocr.json")
        try image(at: url)
        let originalDate = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate!
        let first = try await recognize(OCRIndex(cacheURL: cache, recognizer: { _ in "invoice" }), url: url)
        XCTAssertEqual(first, "invoice")
        let reused = try await recognize(OCRIndex(cacheURL: cache, recognizer: { _ in "incorrect rerun" }), url: url)
        XCTAssertEqual(reused, "invoice")
        try image(at: url, width: 120)
        try FileManager.default.setAttributes([.modificationDate: originalDate], ofItemAtPath: url.path)
        let changed = try await recognize(OCRIndex(cacheURL: cache, recognizer: { _ in "updated" }), url: url)
        XCTAssertEqual(changed, "updated")
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1234)], ofItemAtPath: url.path)
        let dated = try await recognize(OCRIndex(cacheURL: cache, recognizer: { _ in "dated" }), url: url)
        XCTAssertEqual(dated, "dated")
        let another = root.appendingPathComponent("another.png")
        try FileManager.default.copyItem(at: url, to: another)
        let distinct = try await recognize(OCRIndex(cacheURL: cache, recognizer: { _ in "distinct URL" }), url: another)
        XCTAssertEqual(distinct, "distinct URL")
    }

    func testRecognitionDecodesBoundedThumbnail() throws {
        let url = try temporary().appendingPathComponent("large.png")
        try image(at: url, width: 4000, height: 2000)
        let decoded = try XCTUnwrap(OCRIndex.thumbnail(url))
        XCTAssertLessThanOrEqual(max(decoded.width, decoded.height), 3000)
        XCTAssertEqual(decoded.width / decoded.height, 2)
    }

    @MainActor func testStopDuringDebouncePublishesNothingAndCanResume() async throws {
        let root = try temporary(), url = root.appendingPathComponent("image.png")
        try image(at: url)
        // The debounce must comfortably outlast the 50 ms sleep below even on a
        // loaded CI machine; with the 150 ms default the sleep could overrun it.
        let index = OCRIndex(cacheURL: root.appendingPathComponent("ocr.json"), debounceNanoseconds: 1_000_000_000, recognizer: { _ in "resumed" })
        let stopped = expectation(description: "Canceled OCR did not publish")
        stopped.isInverted = true
        index.changed = { _ in stopped.fulfill() }
        index.refresh([(UUID(), url)])
        try await Task.sleep(nanoseconds: 50_000_000)
        index.stop()
        await fulfillment(of: [stopped], timeout: 0.25)
        let resumed = try await recognize(index, url: url)
        XCTAssertEqual(resumed, "resumed")
    }
    @MainActor func testStopDiscardsInFlightResultAndResumes() async throws {
        let root = try temporary(), url = root.appendingPathComponent("image.png"), id = UUID()
        try image(at: url)
        let index = OCRIndex(cacheURL: root.appendingPathComponent("ocr.json"), recognizer: { _ in
            Thread.sleep(forTimeInterval: 0.35)
            return "finished"
        })
        let canceled = expectation(description: "Canceled result is discarded")
        canceled.isInverted = true
        index.changed = { values in if values[id] != nil { canceled.fulfill() } }
        index.refresh([(id, url)])
        try await Task.sleep(nanoseconds: 220_000_000)
        index.stop()
        await fulfillment(of: [canceled], timeout: 0.4)
        let resumed = try await recognize(index, url: url)
        XCTAssertEqual(resumed, "finished")
    }
    @MainActor func testChangingNonemptyQueryRefreshesModifiedImage() async throws {
        let root = try temporary(), url = root.appendingPathComponent("mutable.png")
        try image(at: url)
        let index = OCRIndex(cacheURL: root.appendingPathComponent("cache.json"),recognizer: { $0.width == 100 ? "invoice" : "receipt" })
        let model = AppModel(store: BoardStore(directory: root.appendingPathComponent("state")),ocrIndex: index)
        model.hang(fileURLs: [url],source: .drop)
        model.query = "invoice"
        for _ in 0..<80 {
            if model.recognizedText.values.contains("invoice") { break }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertTrue(model.recognizedText.values.contains("invoice"))
        try image(at: url,width: 120)
        model.query = "receipt"
        for _ in 0..<80 {
            if model.recognizedText.values.contains("receipt") { break }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertTrue(model.recognizedText.values.contains("receipt"))
        XCTAssertFalse(model.recognizedText.values.contains("invoice"))
        model.query = ""
    }

}
