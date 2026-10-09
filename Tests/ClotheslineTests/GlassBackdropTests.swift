import XCTest
import AppKit
import ClotheslineCore
@testable import Clothesline

final class GlassBackdropTests: XCTestCase {
    @MainActor func testGlassHasPersistentActiveBehindWindowFrostDuringInteractions() throws {
        let defaults = UserDefaults.standard
        let saved = defaults.data(forKey: "settings.v1")
        defer { if let saved { defaults.set(saved,forKey: "settings.v1") } else { defaults.removeObject(forKey: "settings.v1") } }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(store: BoardStore(directory: root))
        model.settings.theme = .liquidGlass
        let note = model.createNote("Glass test")!
        let controller = PanelController(model: model)
        controller.show(.explicit)
        defer { controller.hide(); controller.panel.orderOut(nil) }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let content = try XCTUnwrap(controller.panel.contentView)
        let backdrop = try XCTUnwrap(descendants(content).compactMap { $0 as? NSVisualEffectView }.first { $0.blendingMode == .behindWindow }, "Glass must blur windows behind the panel, independently of adaptive foreground glass")
        content.updateTrackingAreas()
        XCTAssertTrue(content.trackingAreas.contains { ($0.owner as? NSView) === controller.lineView && $0.options.contains(.mouseEnteredAndExited) }, "The glass wrapper must forward whole-panel hover tracking to the interactive line")
        XCTAssertEqual(backdrop.state,.active)
        XCTAssertEqual(backdrop.material,.popover)
        XCTAssertFalse(backdrop.isEmphasized)
        controller.lineView.setToolbarVisible(true,animated: false)
        model.selectedIDs = [note]
        controller.panel.resignKey()
        controller.lineView.setToolbarVisible(false,animated: false)
        controller.refreshLayout()
        XCTAssertTrue(controller.panel.contentView === content)
        XCTAssertTrue(descendants(content).contains { $0 === backdrop })
        XCTAssertEqual(backdrop.state,.active)
        XCTAssertEqual(backdrop.material,.popover)
        XCTAssertEqual(backdrop.frame.size.width,controller.panel.frame.width,accuracy: 1)
        XCTAssertEqual(backdrop.frame.size.height,controller.panel.frame.height,accuracy: 1)
        XCTAssertTrue(controller.lineView.window === controller.panel)
    }
}
