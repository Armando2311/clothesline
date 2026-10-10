import XCTest
@testable import ClotheslineCore

final class PremiumSearchTests: XCTestCase {
    func testPremiumSettingsDecodeAndRoundTrip() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"panelLayout":"fullWidth","cardScale":1.2,"noThemeClickThrough":true}"#.utf8))
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as! [String:Any]
        XCTAssertEqual(object["panelLayout"] as? String,"fullWidth")
        XCTAssertEqual(object["cardScale"] as? Double,1.2)
        XCTAssertEqual(object["noThemeClickThrough"] as? Bool,true)
    }
}
