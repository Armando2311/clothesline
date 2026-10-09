import XCTest
import AppKit
import ClotheslineCore
@testable import Clothesline

final class LineReviewTests: XCTestCase {
    @MainActor func testCompactBitmapUsesRetinaScaleAndPreservesPortraitAspect() {
        let context = CGContext(data: nil,width: 40,height: 100,bitsPerComponent: 8,bytesPerRow: 0,space: CGColorSpaceCreateDeviceRGB(),bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0,green: 0,blue: 1,alpha: 1)); context.fill(CGRect(x: 0,y: 0,width: 40,height: 100))
        let item = HangingItem(kind: .image,source: .drop,title: "Portrait",lineID: UUID())
        let input = Artwork.CardInput(item: item,thumbnail: context.makeImage(),icon: nil,availability: .available,theme: .summerAfternoon,scale: 2)
        let card = Artwork.compactCard(input)
        XCTAssertEqual(card.image?.width,Int(card.size.width*2))
        XCTAssertEqual(card.image?.height,Int(card.size.height*2))
        let bitmap = NSBitmapImageRep(cgImage: card.image!)
        // Letterboxing must remain paper rather than stretching the blue image to the edges.
        XCTAssertGreaterThan(bitmap.colorAt(x: 20,y: 40)!.usingColorSpace(.deviceRGB)!.redComponent,0.8)
    }
    @MainActor func testSearchHidesCardsWithoutDeletionAnimationAndPreservesBoard() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let saved = UserDefaults.standard.data(forKey: "settings.v1")
        defer { if let saved { UserDefaults.standard.set(saved,forKey: "settings.v1") } else { UserDefaults.standard.removeObject(forKey: "settings.v1") } }
        let model = AppModel(store: BoardStore(directory: root))
        let a = model.createNote("Alpha")!, b = model.createNote("Beta")!
        let view = LineView(model: model)
        view.configure(notchCenterX: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        view.willAppear(animated: false)
        func descendants(_ layer: CALayer) -> [CALayer] { [layer] + (layer.sublayers ?? []).flatMap(descendants) }
        let beta = descendants(view.layer!).compactMap { $0 as? ItemLayer }.first { $0.itemID == b }!
        model.query = "Alpha"
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertNil(beta.animation(forKey: "remove"))
        XCTAssertEqual(Set(model.board.items.map(\.id)),Set([a,b]))
        model.query = ""
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(model.visibleItems.count,2)
        view.willDisappear()
    }
    @MainActor func testPanelVerticalMovementAndExplicitClose() {
        let defaults = UserDefaults.standard
        let oldOffsets = defaults.object(forKey: "panel.verticalOffsets")
        let oldSettings = defaults.data(forKey: "settings.v1")
        defer {
            if let oldOffsets { defaults.set(oldOffsets,forKey: "panel.verticalOffsets") } else { defaults.removeObject(forKey: "panel.verticalOffsets") }
            if let oldSettings { defaults.set(oldSettings,forKey: "settings.v1") } else { defaults.removeObject(forKey: "settings.v1") }
        }
        defaults.removeObject(forKey: "panel.verticalOffsets")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(store: BoardStore(directory: root))
        model.settings.hideWhenClickingOutside = true // Legacy preferences cannot restore unwanted dismissal.
        let controller = PanelController(model: model)
        controller.show(.explicit)
        let original = controller.panel.frame
        controller.lineViewRequestsVerticalMove(controller.lineView,delta: -80)
        XCTAssertEqual(controller.panel.frame.origin.y,original.origin.y-80,accuracy: 1)
        XCTAssertEqual(controller.panel.frame.origin.x,original.origin.x)
        controller.panel.resignKey()
        XCTAssertTrue(controller.isVisible)
        controller.lineView.workflow.perform(.close)
        XCTAssertFalse(controller.isVisible)
        controller.panel.orderOut(nil)
    }

}
