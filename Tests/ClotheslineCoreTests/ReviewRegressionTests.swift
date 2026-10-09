import XCTest
@testable import ClotheslineCore

final class ReviewRegressionTests: XCTestCase {
    func testUnicodeExportNamesFitFilesystemWithSuffixes() {
        let value = String(repeating: "👨‍👩‍👧‍👦", count: 180)
        let name = ExportNames.safe(value)
        XCTAssertLessThanOrEqual(name.utf8.count, 180)
        XCTAssertFalse(name.isEmpty)
        var used = Set<String>()
        let a = ExportNames.unique(value + ".jpeg", used: &used)
        let b = ExportNames.unique(value + ".jpeg", used: &used)
        XCTAssertNotEqual(a, b)
        XCTAssertLessThanOrEqual(b.utf8.count, 255)
        XCTAssertTrue(b.hasSuffix(".jpeg"))
    }
    func testCrossLineMoveDestinationsFollowItems() {
        let a = Line(name: "Active"), b = Line(name: "Other")
        let item = HangingItem(kind: .text, source: .manual, title: "Note", lineID: b.id)
        let board = Board(lines: [a,b], items: [item], activeLineID: a.id)
        XCTAssertEqual(board.moveDestinations(for: [item]).map(\.id), [a.id])
        let another = HangingItem(kind: .text, source: .manual, title: "Second", lineID: a.id)
        XCTAssertEqual(board.moveDestinations(for: [item,another]).map(\.id), [a.id,b.id])
    }
    func testVerticalPlacementClampsToDisplayAndKeepsWidth() {
        let screen = CGRect(x: -1440, y: -200, width: 1440, height: 900)
        let visible = CGRect(x: -1440, y: -170, width: 1440, height: 846)
        let top = PanelPlacement(screenFrame: screen, visibleFrame: visible, safeAreaTop: 24, notchRect: nil, height: 210)
        let bottom = PanelPlacement(screenFrame: screen, visibleFrame: visible, safeAreaTop: 24, notchRect: nil, height: 210, verticalOffset: 10000)
        XCTAssertEqual(bottom.frame.minY, visible.minY)
        XCTAssertEqual(bottom.frame.minX, top.frame.minX)
        XCTAssertEqual(bottom.frame.width, top.frame.width)
        let above = PanelPlacement(screenFrame: screen, visibleFrame: visible, safeAreaTop: 24, notchRect: nil, height: 210, verticalOffset: -100)
        XCTAssertEqual(above.frame, top.frame)
    }
}
