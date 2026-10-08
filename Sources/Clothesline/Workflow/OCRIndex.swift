import Foundation
import Vision

@MainActor
final class OCRIndex {
    private var keys: [UUID: String] = [:]
    private var cache: [UUID: String] = [:]
    private var task: Task<Void, Never>?
    var changed: (([UUID: String]) -> Void)?
    func refresh(_ inputs: [(UUID, URL)]) {
        var next: [UUID: String] = [:]
        for (id,url) in inputs {
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey,.fileSizeKey]))
            next[id] = "\(url.path)|\(date?.contentModificationDate?.timeIntervalSince1970 ?? 0)|\(date?.fileSize ?? 0)"
        }
        guard next != keys || task == nil else { return }
        task?.cancel()
        cache = cache.filter { next[$0.key] == keys[$0.key] && next[$0.key] != nil }
        keys = next; changed?(cache)
        task = Task { [weak self] in
            for (id,url) in inputs {
                guard let self, !Task.isCancelled else { return }
                guard self.cache[id] == nil else { continue }
                let signature = next[id]
                let text = await Task.detached(priority: .utility) { () -> String in
                    guard let image = try? ImageProcessor.load(url) else { return "" }
                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel = .accurate
                    request.usesLanguageCorrection = true
                    do { try VNImageRequestHandler(cgImage: image).perform([request]) } catch { return "" }
                    return request.results?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n") ?? ""
                }.value
                guard !Task.isCancelled, self.keys[id] == signature else { return }
                self.cache[id] = text; self.changed?(self.cache)
            }
        }
    }
    func stop() { task?.cancel(); task = nil }
}
