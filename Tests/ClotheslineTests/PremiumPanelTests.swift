import XCTest
import AppKit
import ClotheslineCore
@testable import Clothesline

final class PremiumPanelTests: XCTestCase {
    @MainActor func testFittedPanelCentersAndFullWidthCanBeRestored() {
        withModel { model in
            let controller = PanelController(model: model)
            model.settings.panelLayout = .fitted
            controller.show(.explicit)
            let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main!
            XCTAssertEqual(controller.panel.frame.width, min(640,screen.frame.width - 16),accuracy: 1)
            XCTAssertEqual(controller.panel.frame.midX,screen.frame.midX,accuracy: 1)
            model.settings.panelLayout = .fullWidth
            controller.refreshLayout()
            XCTAssertEqual(controller.panel.frame.width,screen.frame.width - 16,accuracy: 1)
            controller.hide()
            controller.panel.orderOut(nil)
        }
    }
    @MainActor func testNoThemeEmptySpaceDiffersFromCardAndRopeSurfaces() {
        withModel { model in
            model.settings.theme = .noTheme
            let view = LineView(model: model)
            view.frame.size = NSSize(width: 900,height: 210)
            view.relayout(animated: false)
            XCTAssertFalse(view.containsInteractiveSurface(CGPoint(x: 100,y: 145)))
            let id = model.createNote("Drop destination")!
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            view.relayout(animated: false)
            let rect = view.rect(for: id)!
            XCTAssertTrue(view.containsInteractiveSurface(CGPoint(x: rect.midX,y: rect.midY)))
        }
    }
    @MainActor private func withModel(_ run: (AppModel) -> Void) {
        let defaults = UserDefaults.standard
        let saved = defaults.data(forKey: "settings.v1")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: root)
            if let saved { defaults.set(saved,forKey: "settings.v1") } else { defaults.removeObject(forKey: "settings.v1") }
        }
        let model = AppModel(store: BoardStore(directory: root))
        model.settings = AppSettings()
        run(model)
    }
}
