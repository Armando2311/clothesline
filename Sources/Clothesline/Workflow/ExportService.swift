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
    struct PlannedOutput { var inputIndex: Int; var name: String; var format: ExportImageFormat? }
    struct SizeEstimate { var outputs: [(name: String, bytes: Int)]; var totalBytes: Int { outputs.reduce(0) { $0 + $1.bytes } } }
    private static func plan(inputs: [ExportInput], options: RecipeOptions) -> [PlannedOutput] {
        var used: Set<String> = ["report.md"], imageIndex = 0
        var outputs: [PlannedOutput] = []
        for (index, input) in inputs.enumerated() {
            guard input.item.file != nil || input.url != nil else { continue }
            if options.recipe != .bugReport && [.image, .screenshot].contains(input.item.kind) {
                imageIndex += 1
                for format in options.imageFormats {
                    let name = ExportNames.unique("\(ExportNames.safe(options.prefix))-\(String(format: "%03d", imageIndex)).\(format.fileExtension)", used: &used)
                    outputs.append(PlannedOutput(inputIndex: index, name: name, format: format))
                }
            } else {
                outputs.append(PlannedOutput(inputIndex: index, name: ExportNames.unique(input.url?.lastPathComponent ?? input.item.file?.fileName ?? input.item.title, used: &used), format: nil))
            }
        }
        return outputs
    }
    static func plannedNames(inputs: [ExportInput], options: RecipeOptions) -> [String] {
        plan(inputs: inputs, options: options).map(\.name)
    }
    private static func imageData(url: URL, format: ExportImageFormat, options: RecipeOptions) throws -> Data {
        let image = try ImageProcessor.load(url)
        var edits = ImageEdits(); edits.maxEdge = options.maxEdge
        edits.crop = ImageProcessor.centerCrop(image, ratio: options.cropRatio)
        let rendered = try ImageProcessor.render(image, edits: edits)
        return try ImageProcessor.encode(rendered, format: format == .png ? .png : .jpeg,
                                         quality: options.quality, maxBytes: options.maximumImageBytes)
    }
    private static func report(inputs: [ExportInput], options: RecipeOptions, outputs: [PlannedOutput]) -> String {
        var report = "# \(options.packageName)\n\n"
        if options.recipe == .bugReport {
            report += "## Reproduction steps\n\(options.steps)\n\n## Expected result\n\(options.expected)\n\n## Actual result\n\(options.actual)\n\n"
        }
        report += "## Materials\n\n"
        for (index, input) in inputs.enumerated() {
            if input.url != nil {
                for output in outputs where output.inputIndex == index {
                    let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "()[]#?"))
                    let escaped = output.name.addingPercentEncoding(withAllowedCharacters: allowed) ?? output.name
                    let label = output.name.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
                    report += "- [\(label)](\(escaped))\n"
                }
            } else if let text = input.item.text { report += "\n### \(input.item.title)\n\n\(text)\n\n" }
            else if let link = input.item.link { report += "- \(input.item.title): \(link)\n" }
        }
        return report
    }
    /// Uses the export encoder, so per-image estimates are the exact encoded bytes.
    /// The total is before ZIP compression; directory attachments include nested files.
    static func estimate(inputs: [ExportInput], options: RecipeOptions,
                         cancellation: ExportCancellation = ExportCancellation()) throws -> SizeEstimate {
        try options.validate(); try cancellation.check()
        let outputs = plan(inputs: inputs, options: options)
        var sizes: [(name: String, bytes: Int)] = []
        for output in outputs {
            try cancellation.check()
            guard let url = inputs[output.inputIndex].url else { throw WorkflowError.unreadable(inputs[output.inputIndex].item.title) }
            let bytes: Int
            if let format = output.format { bytes = try imageData(url: url, format: format, options: options).count }
            else {
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                if values.isDirectory == true {
                    let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
                    var count = 0
                    while let child = enumerator?.nextObject() as? URL {
                        try cancellation.check()
                        let childValues = try child.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                        if childValues.isRegularFile == true { count += childValues.fileSize ?? 0 }
                    }
                    bytes = count
                } else { bytes = values.fileSize ?? 0 }
            }
            sizes.append((output.name, bytes))
        }
        sizes.append(("Report.md", report(inputs: inputs, options: options, outputs: outputs).utf8.count))
        return SizeEstimate(outputs: sizes)
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
        // Keep unpublished files on the destination volume without exposing staging
        // entries inside the folder the user selected.
        let stage = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask,
                               appropriateFor: destination, create: true)
        defer { try? fm.removeItem(at: stage) }
        let name = ExportNames.safe(options.packageName)
        let folder = stage.appendingPathComponent(name, isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: false)
        let outputs = plan(inputs: inputs, options: options)
        let report = report(inputs: inputs, options: options, outputs: outputs)
        for (position, input) in inputs.enumerated() {
            try cancellation.check()
            for output in outputs where output.inputIndex == position {
                try cancellation.check()
                guard let url = input.url else { throw WorkflowError.unreadable(input.item.title) }
                let destinationURL = folder.appendingPathComponent(output.name)
                if let format = output.format {
                    try imageData(url: url, format: format, options: options).write(to: destinationURL, options: .withoutOverwriting)
                } else { try fm.copyItem(at: url, to: destinationURL) }
            }
            progress(Double(position + 1) / Double(inputs.count + 1))
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
