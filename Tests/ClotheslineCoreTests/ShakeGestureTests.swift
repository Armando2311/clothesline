import XCTest
@testable import ClotheslineCore

final class ShakeGestureTests: XCTestCase {
    func testThreeDeliberateReversalsWithinWindowReveal() {
        var shake = ShakeGesture()
        XCTAssertFalse(shake.update(x: 100,time: 0))
        XCTAssertFalse(shake.update(x: 140,time: 0.1))
        XCTAssertFalse(shake.update(x: 95,time: 0.2))
        XCTAssertFalse(shake.update(x: 145,time: 0.3))
        XCTAssertTrue(shake.update(x: 90,time: 0.4))
    }
    func testJitterAndSlowChangesDoNotReveal() {
        var shake = ShakeGesture()
        for (i,x) in [100.0,105,99,104,98,102].enumerated() {
            XCTAssertFalse(shake.update(x:x,time:Double(i) * 0.05))
        }
        var slow = ShakeGesture()
        for (i,x) in [100.0,140,95,145,90].enumerated() {
            XCTAssertFalse(slow.update(x:x,time:Double(i)))
        }
    }
}
