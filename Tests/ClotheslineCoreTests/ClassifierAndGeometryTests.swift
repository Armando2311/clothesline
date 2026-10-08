import XCTest
@testable import ClotheslineCore

final class ScreenshotClassifierTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 2_000_000)
    let classifier = ScreenshotClassifier()

    func testAttributeIsAuthoritative() {
        let c = ScreenshotClassifier.Candidate(fileName: "My custom name.png", hasScreenCaptureAttribute: true, creationDate: nil)
        XCTAssertEqual(classifier.classify(c, now: now), .screenshot)
    }

    func testHiddenTempFilesAreIgnored() {
        let c = ScreenshotClassifier.Candidate(fileName: ".Screenshot 2026-10-08 at 10.00.00.png", hasScreenCaptureAttribute: true, creationDate: now)
        XCTAssertEqual(classifier.classify(c, now: now), .notScreenshot)
    }

    func testNonImagesIgnored() {
        let c = ScreenshotClassifier.Candidate(fileName: "Screenshot notes.txt", hasScreenCaptureAttribute: true, creationDate: now)
        XCTAssertEqual(classifier.classify(c, now: now), .notScreenshot)
        let dir = ScreenshotClassifier.Candidate(fileName: "Screenshot.png", isDirectory: true, hasScreenCaptureAttribute: true, creationDate: now)
        XCTAssertEqual(classifier.classify(dir, now: now), .notScreenshot)
    }

    func testRecordingsOnlyWhenEnabled() {
        let c = ScreenshotClassifier.Candidate(fileName: "Screen Recording 2026-10-08 at 10.00.00.mov", hasScreenCaptureAttribute: true, creationDate: now)
        XCTAssertEqual(classifier.classify(c, now: now), .notScreenshot)
        XCTAssertEqual(ScreenshotClassifier(includeRecordings: true).classify(c, now: now), .recording)
    }

    func testNameFallbackRequiresFreshFile() {
        let fresh = ScreenshotClassifier.Candidate(fileName: "Screenshot 2026-10-08 at 10.00.00.png", hasScreenCaptureAttribute: nil, creationDate: now.addingTimeInterval(-3))
        XCTAssertEqual(classifier.classify(fresh, now: now), .screenshot)
        let old = ScreenshotClassifier.Candidate(fileName: "Screenshot 2026-10-08 at 10.00.00.png", hasScreenCaptureAttribute: false, creationDate: now.addingTimeInterval(-86400))
        XCTAssertEqual(classifier.classify(old, now: now), .notScreenshot)
        let unrelated = ScreenshotClassifier.Candidate(fileName: "holiday.png", hasScreenCaptureAttribute: false, creationDate: now)
        XCTAssertEqual(classifier.classify(unrelated, now: now), .notScreenshot)
    }

    func testLocalisedAndCustomNames() {
        XCTAssertTrue(classifier.matchesScreenshotName("Bildschirmfoto 2026-10-08 um 10.00.00.png"))
        XCTAssertTrue(classifier.matchesScreenshotName("Screen Shot 2019-01-01 at 1.00.00 PM.png"))
        XCTAssertTrue(classifier.matchesScreenshotName("Screenshot.png"))
        XCTAssertTrue(classifier.matchesScreenshotName("Screenshot 2.png"))
        XCTAssertFalse(classifier.matchesScreenshotName("Screenshots-folder-index.png"))
        XCTAssertTrue(ScreenshotClassifier(customPrefix: "shot").matchesScreenshotName("shot 2026-10-08.png"))
    }

    func testPreferencesFolderResolution() {
        let home = "/Users/me"
        XCTAssertEqual(ScreenshotPreferences().resolvedFolder(homeDirectory: home).path, "/Users/me/Desktop")
        XCTAssertEqual(ScreenshotPreferences(location: "~/Pictures/Shots").resolvedFolder(homeDirectory: home).path, "/Users/me/Pictures/Shots")
        XCTAssertEqual(ScreenshotPreferences(location: "/Volumes/X/Caps/").resolvedFolder(homeDirectory: home).path, "/Volumes/X/Caps")
        XCTAssertEqual(ScreenshotPreferences(location: "file:///Users/me/Downloads/").resolvedFolder(homeDirectory: home).path, "/Users/me/Downloads")
        XCTAssertEqual(ScreenshotPreferences(location: "relative/path").resolvedFolder(homeDirectory: home).path, "/Users/me/Desktop")
        XCTAssertTrue(ScreenshotPreferences(target: nil).savesToFile)
        XCTAssertTrue(ScreenshotPreferences(target: "file").savesToFile)
        XCTAssertFalse(ScreenshotPreferences(target: "clipboard").savesToFile)
    }
}

final class ItemClassifierTests: XCTestCase {
    func testKinds() {
        XCTAssertEqual(ItemClassifier.kind(forFileName: "a.PDF", isDirectory: false), .pdf)
        XCTAssertEqual(ItemClassifier.kind(forFileName: "a.heic", isDirectory: false), .image)
        XCTAssertEqual(ItemClassifier.kind(forFileName: "Stuff", isDirectory: true), .folder)
        XCTAssertEqual(ItemClassifier.kind(forFileName: "Pages.app", isDirectory: true, isPackage: true), .file)
        XCTAssertEqual(ItemClassifier.kind(forFileName: "notes.md", isDirectory: false), .file)
    }

    func testLinkDetection() {
        XCTAssertEqual(ItemClassifier.link(from: "  https://example.com/a?b=c \n"), "https://example.com/a?b=c")
        XCTAssertNil(ItemClassifier.link(from: "hello world"))
        XCTAssertNil(ItemClassifier.link(from: "notes.txt"))
        XCTAssertNil(ItemClassifier.link(from: "https://example.com and more"))
        XCTAssertNil(ItemClassifier.link(from: "http://nodot"))
        XCTAssertEqual(ItemClassifier.link(from: "mailto:me@example.com"), "mailto:me@example.com")
    }

    func testTitles() {
        XCTAssertEqual(ItemClassifier.title(forLink: "https://www.example.com/"), "example.com")
        XCTAssertEqual(ItemClassifier.title(forLink: "https://example.com/docs/page.html"), "example.com › page.html")
        XCTAssertEqual(ItemClassifier.title(forText: "\n\n  First line  \nsecond"), "First line")
        XCTAssertEqual(ItemClassifier.title(forText: String(repeating: "a", count: 100), maxLength: 10).count, 10)
        XCTAssertEqual(ItemClassifier.title(forFileName: "Screenshot 1.png", kind: .screenshot), "Screenshot 1")
        XCTAssertEqual(ItemClassifier.title(forFileName: "doc.pdf", kind: .pdf), "doc.pdf")
    }

    func testExportNames() {
        let note = HangingItem(kind: .text, source: .manual, title: "", lineID: UUID(), text: "Shopping/list: milk")
        XCTAssertEqual(ItemClassifier.exportFileName(for: note), "Shopping-list- milk.txt")
        let link = HangingItem(kind: .link, source: .manual, title: "", lineID: UUID(), link: "https://example.com")
        XCTAssertEqual(ItemClassifier.exportFileName(for: link), "example.com.webloc")
    }
}

final class GeometryTests: XCTestCase {
    func testRopeIsContinuousAndSagsBetweenHooks() {
        let g = LineGeometry(width: 1500, centerHookX: 750)
        XCTAssertEqual(g.hooks.count, 3)
        XCTAssertEqual(g.segments.count, 2)
        let left = g.segments[0]
        XCTAssertEqual(left.y(atX: left.start.x), left.start.y, accuracy: 1e-9)
        XCTAssertEqual(left.y(atX: left.end.x), left.end.y, accuracy: 1e-9)
        // Lowest point is between the hooks, below both.
        let mid = (left.start.x + left.end.x) / 2
        XCTAssertGreaterThan(left.y(atX: mid), max(left.start.y, left.end.y))
        // Slope matches a numeric derivative.
        let x = left.start.x + 100, h = 0.001
        XCTAssertEqual(left.slope(atX: x), (left.y(atX: x + h) - left.y(atX: x - h)) / (2 * h), accuracy: 1e-5)
    }

    func testNoCenterHookWithoutNotchOrTooCloseToEdge() {
        XCTAssertEqual(LineGeometry(width: 1500, centerHookX: nil).hooks.count, 2)
        XCTAssertEqual(LineGeometry(width: 1500, centerHookX: 60).hooks.count, 2)
    }

    func testUsableMappingRoundTripsAndSkipsHook() {
        let g = LineGeometry(width: 1500, centerHookX: 750)
        for d in stride(from: 0.0, through: g.usableLength, by: 37) {
            XCTAssertEqual(g.usableDistance(atX: g.x(alongUsable: d)), d, accuracy: 1e-9)
        }
        // No usable position lands within the clearance zone around the centre hook.
        for d in stride(from: 0.0, through: g.usableLength, by: 1) {
            XCTAssertFalse(abs(g.x(alongUsable: d) - 750) < g.hookClearance - 1e-9)
        }
    }

    func testLayoutCentersFewItemsAndCrowdsMany() {
        let g = LineGeometry(width: 1400, centerHookX: nil)
        let few = LineLayout(geometry: g, itemWidth: 90, jitters: [0, 0, 0])
        XCTAssertEqual(few.slots.count, 3)
        XCTAssertEqual(few.slots[1].x, 700, accuracy: 0.001)
        XCTAssertEqual(few.overflow, 0)
        XCTAssertTrue(few.slots.allSatisfy(\.visible))

        let many = LineLayout(geometry: g, itemWidth: 90, jitters: Array(repeating: 0, count: 60))
        XCTAssertEqual(many.pitch, 90 * 0.55, accuracy: 0.001)
        XCTAssertGreaterThan(many.overflow, 0)
        XCTAssertTrue(many.slots.contains { !$0.visible })
        // Scrolling reveals the right end.
        let scrolled = LineLayout(geometry: g, itemWidth: 90, jitters: Array(repeating: 0, count: 60), scroll: .greatestFiniteMagnitude)
        XCTAssertTrue(scrolled.slots.last!.visible)
        // Order is preserved left-to-right.
        XCTAssertEqual(many.slots.map(\.x), many.slots.map(\.x).sorted())
    }

    func testInsertionIndex() {
        let g = LineGeometry(width: 1400, centerHookX: nil)
        let l = LineLayout(geometry: g, itemWidth: 90, jitters: [0, 0, 0])
        XCTAssertEqual(LineLayout.insertionIndex(forX: 0, in: l.slots), 0)
        XCTAssertEqual(LineLayout.insertionIndex(forX: l.slots[1].x - 1, in: l.slots), 1)
        XCTAssertEqual(LineLayout.insertionIndex(forX: 10_000, in: l.slots), 3)
    }

    func testPanelPlacementNotchedAndPlain() {
        // 14" MacBook Pro-like: 1512x982 points, menu bar 37pt tall with notch.
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let visible = CGRect(x: 0, y: 70, width: 1512, height: 875)
        let notch = CGRect(x: 662, y: 945, width: 188, height: 37)
        let p = PanelPlacement(screenFrame: screen, visibleFrame: visible, safeAreaTop: 37, notchRect: notch, height: 240)
        XCTAssertEqual(p.frame.maxY, 945, accuracy: 0.001)
        XCTAssertEqual(p.frame.height, 240, accuracy: 0.001)
        XCTAssertTrue(p.hasNotch)
        XCTAssertEqual(p.notchCenterX!, 756 - 8, accuracy: 0.001)

        // Auto-hidden menu bar on a notched display: still stay below the notch.
        let full = PanelPlacement(screenFrame: screen, visibleFrame: screen, safeAreaTop: 37, notchRect: notch, height: 240)
        XCTAssertEqual(full.frame.maxY, 945, accuracy: 0.001)

        // External display to the right, no notch, menu bar 25pt.
        let ext = CGRect(x: 1512, y: -200, width: 2560, height: 1440)
        let extVisible = CGRect(x: 1512, y: -200, width: 2560, height: 1415)
        let e = PanelPlacement(screenFrame: ext, visibleFrame: extVisible, safeAreaTop: 0, notchRect: nil, height: 240)
        XCTAssertEqual(e.frame.maxY, 1215, accuracy: 0.001)
        XCTAssertEqual(e.frame.minX, 1520, accuracy: 0.001)
        XCTAssertFalse(e.hasNotch)
        XCTAssertNil(e.notchCenterX)
    }
}
