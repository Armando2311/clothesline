import XCTest
@testable import ClotheslineCore

final class AdaptivePanelTests: XCTestCase {
    func testFittedWidthGrowsWithContentAndCapsAtDisplay() {
        XCTAssertEqual(AdaptivePanel.width(available: 1400, itemCount: 1, cardWidth: 100, fitted: true), 640)
        XCTAssertEqual(AdaptivePanel.width(available: 1400, itemCount: 8, cardWidth: 100, fitted: true), 1040)
        XCTAssertEqual(AdaptivePanel.width(available: 800, itemCount: 30, cardWidth: 100, fitted: true), 800)
        XCTAssertEqual(AdaptivePanel.width(available: 1400, itemCount: 1, cardWidth: 100, fitted: false), 1400)
    }
    func testInvalidScaleDoesNotPoisonLayout() {
        XCTAssertEqual(AdaptivePanel.cardScale(.nan), 1)
        XCTAssertEqual(AdaptivePanel.cardScale(9), 1.2)
        XCTAssertEqual(AdaptivePanel.cardScale(0), 0.8)
    }
    func testCompactToolbarThresholdTracksAvailableWidth() {
        XCTAssertTrue(AdaptivePanel.compactToolbar(width: 650))
        XCTAssertFalse(AdaptivePanel.compactToolbar(width: 1200))
    }
}
