import Foundation
import ClotheslineCore

struct ExportInput { var item: HangingItem; var url: URL? }
struct ExportResult { var url: URL; var report: String }
final class ExportCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    func check() throws { lock.lock(); let value = cancelled; lock.unlock(); if value { throw WorkflowError.cancelled } }
}

enum ExportService {
    static func plannedNames(inputs: [ExportInput], options: RecipeOptions) -> [String] {
        var used: Set<String> = ["report.md"], imageIndex = 0
        return inputs.compactMap { input in
            guard input.item.file != nil || input.url != nil else { return nil }
            if options.recipe != .bugReport && [.image,.screenshot].contains(input.item.kind) {
                imageIndex += 1
                return ExportNames.unique("\(ExportNames.safe(options.prefix))-\(String(format: "%03d", imageIndex)).jpg", used: &used)
            }
            return ExportNames.unique(input.url?.lastPathComponent ?? input.item.file?.fileName ?? input.item.title, used: &used)
        }
    }
    static func export(inputs: [ExportInput], options: RecipeOptions, destination: URL,
                       cancellation: ExportCancellation = ExportCancellation(), progress: (Double) -> Void = { _ in }) throws -> ExportResult {
        try cancellation.check(); try options.validate()
        guard !inputs.isEmpty else { throw WorkflowError.invalidOptions }
        if options.recipe == .productListing && inputs.contains(where: { ![.image,.screenshot].contains($0.item.kind) }) {
            throw NSError(domain: "Clothesline", code: 1, userInfo: [NSLocalizedDescriptionKey: "Product Listing accepts images only. Choose Client Handoff for a mixed selection."])
        }
        let fm = FileManager.default
        let missing = inputs.filter { ($0.item.kind.isFileBacked || $0.url != nil) && ($0.url == nil || !fm.fileExists(atPath: $0.url!.path)) }
        guard missing.isEmpty else { throw WorkflowError.unreadable(missing.map { $0.item.title }.joined(separator: ", ")) }
        let canonicalDestination = destination.resolvingSymlinksInPath().standardizedFileURL.path
        for input in inputs {
            guard let url = input.url,
                  (try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let source = url.resolvingSymlinksInPath().standardizedFileURL.path
            guard canonicalDestination != source, !canonicalDestination.hasPrefix(source + "/") else {
                throw NSError(domain: "Clothesline",code: 3,userInfo: [NSLocalizedDescriptionKey: "Choose an export folder outside the folders you are exporting."])
            }
        }
        let stage = destination.appendingPathComponent(".clothesline-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: stage, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: stage) }
        let name = ExportNames.safe(options.packageName)
        let folder = stage.appendingPathComponent(name, isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: false)
        let names = plannedNames(inputs: inputs, options: options)
        var index = 0
        var report = "# \(options.packageName)\n\n"
        if options.recipe == .bugReport {
            report += "## Reproduction steps\n\(options.steps)\n\n## Expected result\n\(options.expected)\n\n## Actual result\n\(options.actual)\n\n"
        }
        report += "## Materials\n\n"
        for (position,input) in inputs.enumerated() {
            try cancellation.check()
            if let url = input.url {
                let fileName = names[index]; index += 1
                let output = folder.appendingPathComponent(fileName)
                if options.recipe != .bugReport && [.image,.screenshot].contains(input.item.kind) {
                    let image = try ImageProcessor.load(url)
                    var edits = ImageEdits(); edits.maxEdge = options.maxEdge; edits.crop = ImageProcessor.centerCrop(image, ratio: options.cropRatio)
                    let rendered = try ImageProcessor.render(image, edits: edits)
                    try ImageProcessor.encode(rendered, format: .jpeg, quality: options.quality).write(to: output, options: .withoutOverwriting)
                } else {
                    try fm.copyItem(at: url, to: output)
                }
                let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "()[]#?"))
                let escaped = fileName.addingPercentEncoding(withAllowedCharacters: allowed) ?? fileName
                let label = fileName.replacingOccurrences(of: "[",with: "\\[").replacingOccurrences(of: "]",with: "\\]")
                report += "- [\(label)](\(escaped))\n"
            } else if let text = input.item.text { report += "\n### \(input.item.title)\n\n\(text)\n\n" }
            else if let link = input.item.link { report += "- \(input.item.title): \(link)\n" }
            progress(Double(position+1)/Double(inputs.count+1))
        }
        try Data(report.utf8).write(to: folder.appendingPathComponent("Report.md"), options: .withoutOverwriting)
        try cancellation.check()
        var source = folder
        if options.zip {
            source = stage.appendingPathComponent(name + ".zip")
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-c", "-k", "--keepParent", folder.path, source.path]
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            try process.run()
            do {
                while process.isRunning { try cancellation.check(); Thread.sleep(forTimeInterval: 0.05) }
                process.waitUntilExit()
            } catch { if process.isRunning { process.terminate() }; process.waitUntilExit(); throw error }
            guard process.terminationStatus == 0 else { throw NSError(domain: "Clothesline", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not create the ZIP archive."]) }
        }
        try cancellation.check()
        var used = Set((try fm.contentsOfDirectory(atPath: destination.path)).map { $0.lowercased() })
        let final = destination.appendingPathComponent(ExportNames.unique(source.lastPathComponent, used: &used))
        // moveItem refuses an existing destination even if it appeared after name planning.
        try fm.moveItem(at: source, to: final)
        progress(1)
        return ExportResult(url: final, report: report)
    }
}
