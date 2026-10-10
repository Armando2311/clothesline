import Foundation
import ImageIO
import Vision

/// Keeps filesystem I/O, thumbnail decoding, and Vision work off the UI actor.
private actor OCRWorker {
    struct Signature: Codable, Equatable {
        let url: URL
        let modificationDate: Date
        let fileSize: Int
    }
    private struct Entry: Codable {
        let signature: Signature
        let text: String
    }
    private let cacheURL: URL
    private let recognizer: @Sendable (CGImage) throws -> String
    private var entries: [String: Entry] = [:]
    private var loaded = false

    init(cacheURL: URL, recognizer: @escaping @Sendable (CGImage) throws -> String) {
        self.cacheURL = cacheURL
        self.recognizer = recognizer
    }

    private func signature(_ url: URL) -> Signature? {
        var url = url
        url.removeAllCachedResourceValues()
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let date = values.contentModificationDate, let size = values.fileSize else { return nil }
        return Signature(url: url.standardizedFileURL, modificationDate: date, fileSize: size)
    }

    func recognize(_ url: URL) -> String? {
        guard !Task.isCancelled, let before = signature(url) else { return nil }
        if !loaded {
            loaded = true
            if let data = try? Data(contentsOf: cacheURL),
               let stored = try? JSONDecoder().decode([String: Entry].self, from: data) { entries = stored }
        }
        let key = before.url.absoluteString
        if let cached = entries[key], cached.signature == before { return cached.text }
        guard !Task.isCancelled, let image = OCRIndex.thumbnail(url),
              let text = try? recognizer(image), !Task.isCancelled, signature(url) == before else { return nil }
        entries[key] = Entry(signature: before, text: text)
        // Replace each URL's previous revision and cap long-lived caches.
        if entries.count > 2000 {
            let oldest = entries.min { $0.value.signature.modificationDate < $1.value.signature.modificationDate }
            if let oldest { entries.removeValue(forKey: oldest.key) }
        }
        if let data = try? JSONEncoder().encode(entries) {
            do {
                try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: cacheURL, options: .atomic)
            } catch {
                // OCR remains available if the cache is unwritable. Never log paths or recognized text.
            }
        }
        return text
    }
}

@MainActor
final class OCRIndex {
    private let worker: OCRWorker
    private let debounceNanoseconds: UInt64
    private var inputs: [UUID: URL] = [:]
    private var cache: [UUID: String] = [:]
    private var task: Task<Void, Never>?
    private var generation = UUID()
    var changed: (([UUID: String]) -> Void)?

    init(cacheURL: URL? = nil, debounceNanoseconds: UInt64 = 150_000_000, recognizer: @escaping @Sendable (CGImage) throws -> String = { try OCRIndex.recognize($0) }) {
        self.debounceNanoseconds = debounceNanoseconds
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        worker = OCRWorker(cacheURL: cacheURL ?? directory.appendingPathComponent("app.clothesline/OCR-v1.json"), recognizer: recognizer)
    }

    nonisolated static func thumbnail(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 3000,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }

    nonisolated private static func recognize(_ image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image).perform([request])
        return request.results?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n") ?? ""
    }

    func text(for url:URL) async -> String? { await worker.recognize(url) }

    func refresh(_ requested: [(UUID, URL)]) {
        let next = Dictionary(requested, uniquingKeysWith: { _, latest in latest })
        task?.cancel()
        generation = UUID()
        let current = generation
        let previous = inputs
        inputs = next
        let delay = debounceNanoseconds
        task = Task { [weak self, worker] in
            do { try await Task.sleep(nanoseconds: delay) } catch { return }
            guard let self, !Task.isCancelled, self.generation == current else { return }
            self.cache = self.cache.filter { next[$0.key] == previous[$0.key] && next[$0.key] != nil }
            self.changed?(self.cache)
            for (id, url) in requested {
                guard !Task.isCancelled, self.generation == current else { return }
                let text = await worker.recognize(url)
                guard !Task.isCancelled, self.generation == current else { return }
                if let text { self.cache[id] = text } else { self.cache.removeValue(forKey: id) }
                self.changed?(self.cache)
            }
            if self.generation == current { self.task = nil }
        }
    }

    func stop() {
        generation = UUID()
        task?.cancel()
        task = nil
    }
}
