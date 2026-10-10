import XCTest
@testable import ClotheslineCore
final class ReleaseVersionTests:XCTestCase {
    func testNumericVersionsAndUntrustedReleaseLinks() {
        XCTAssertTrue(ReleaseVersion.isNewer("v1.10.0",than:"1.9.9"))
        XCTAssertFalse(ReleaseVersion.isNewer("1.0.0",than:"1.0"))
        XCTAssertFalse(ReleaseVersion.isNewer("v2.0.0-beta",than:"1.0"))
        XCTAssertTrue(ReleaseVersion.isTrustedReleaseURL(URL(string:"https://github.com/Armando2311/clothesline/releases/tag/v1.0.0")!))
        XCTAssertFalse(ReleaseVersion.isTrustedReleaseURL(URL(string:"https://github.com.evil.test/Armando2311/clothesline/releases/tag/v1.0.0")!))
        XCTAssertFalse(ReleaseVersion.isTrustedReleaseURL(URL(string:"http://github.com/Armando2311/clothesline/releases/tag/v1.0.0")!))
    }
}
