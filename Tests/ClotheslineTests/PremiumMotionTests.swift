import XCTest
import AppKit
import ClotheslineCore
@testable import Clothesline

final class PremiumMotionTests: XCTestCase {
    @MainActor func testWorkspaceSwitchRetainsOutgoingCardsUntilTransitionCompletes() {
        withModel { model in
            let first = model.createNote("First workspace")!
            let oldLine = model.board.activeLineID
            model.addLine(named: "Work")
            let second = model.createNote("Second workspace")!
            model.activate(lineID: oldLine)
            let view = LineView(model: model)
            view.willAppear(animated: false)
            spin(0.08)
            model.activate(lineID: model.board.lines.last!.id)
            spin(0.03)
            XCTAssertNotNil(view.rect(for: second))
            XCTAssertNil(view.rect(for: first))
            XCTAssertEqual(view.workspaceTransitionCount, 1)
            model.activate(lineID: oldLine)
            spin(0.03)
            XCTAssertEqual(view.workspaceTransitionCount, 1, "Rapid switching keeps only one outgoing workspace")
            spin(0.5)
            XCTAssertEqual(view.workspaceTransitionCount, 0)
            XCTAssertNotNil(view.rect(for: first), "An old completion must never remove the current workspace")
            view.willDisappear()
        }
    }
    @MainActor func testSelectionAndHoverAnimateWithoutChangingCardGeometry() {
        let item = ItemLayer(itemID: UUID())
        let note = HangingItem(kind: .text, source: .manual, title: "Test", lineID: UUID(), text: "Test")
        let theme = Theme.resolve(.summerAfternoon, appearance: NSAppearance(named: .aqua)!)
        item.configure(card: Artwork.card(.init(item: note, thumbnail: nil, icon: nil, availability: .available, theme: theme, scale: 2)), pin: nil, theme: theme, scale: 2)
        let bounds = item.bounds
        item.isSelected = true
        XCTAssertEqual(item.selectionLayer.opacity, 1)
        XCTAssertFalse(item.selectionLayer.isHidden)
        item.isSelected = false
        XCTAssertEqual(item.selectionLayer.opacity, 0)
        item.isHovered = true
        XCTAssertEqual(item.bounds, bounds)
        XCTAssertEqual(item.cardLayer.shadowRadius, 6)
        item.isHovered = false
        XCTAssertEqual(item.cardLayer.shadowRadius, 3.5)
    }
    @MainActor func testHidingDuringWorkspaceSwitchCleansUpTransientLayers() {
        withModel { model in
            _ = model.createNote("First")
            let first = model.board.activeLineID
            model.addLine(named: "Work")
            _ = model.createNote("Second")
            let view = LineView(model: model)
            view.willAppear(animated: false)
            spin(0.04)
            model.activate(lineID: first)
            spin(0.04)
            XCTAssertEqual(view.workspaceTransitionCount, 1)
            view.willDisappear()
            XCTAssertEqual(view.workspaceTransitionCount, 0)
            spin(0.35)
            view.willAppear(animated: false)
            XCTAssertEqual(view.workspaceTransitionCount, 0)
        }
    }
    @MainActor func testWorkflowWindowPresentationSettlesWithoutChangingFrame() {
        let window = NSWindow(contentRect: CGRect(x: 0,y: 0,width: 640,height: 400),styleMask: [.titled,.closable],backing: .buffered,defer: false)
        window.isReleasedWhenClosed = false
        defer { window.orderOut(nil) }
        window.contentView = NSView(frame: CGRect(x: 0,y: 0,width: 640,height: 400))
        let frame = window.frame
        Motion.present(window)
        Motion.present(window)
        spin(0.4)
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(window.alphaValue, 1, accuracy: 0.01)
        XCTAssertEqual(window.frame, frame)
        XCTAssertEqual(window.contentView?.layer?.transform.m42 ?? 0, 0)
    }
    @MainActor func testStatusStartsInvisibleAndClearsWithoutBlankBanner() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(store: BoardStore(directory: root))
        let view = LineView(model: model)
        try await Task.sleep(nanoseconds: 40_000_000)
        let status = view.layer?.sublayers?.first { $0.name == "statusFeedback" }
        XCTAssertEqual(status?.opacity, 0)
        model.notice("Copied selection")
        try await Task.sleep(nanoseconds: 40_000_000)
        XCTAssertEqual(status?.opacity, 1)
        try await Task.sleep(nanoseconds: 4_200_000_000)
        XCTAssertEqual(status?.opacity, 0)
    }
    @MainActor func testRapidCloseAndReopenDoesNotLetOldCompletionHidePanel() {
        withModel { model in
            let controller = PanelController(model: model)
            defer { controller.hide(); controller.panel.orderOut(nil) }
            controller.show(.explicit)
            controller.hide()
            spin(0.04)
            controller.show(.explicit)
            controller.hide()
            spin(0.04)
            controller.show(.explicit)
            spin(0.4)
            XCTAssertTrue(controller.isVisible)
            XCTAssertTrue(controller.panel.isVisible)
            XCTAssertEqual(controller.panel.alphaValue, 1, accuracy: 0.01)
        }
    }
    func testReducedMotionUsesShortFadesWithoutTravel() {
        XCTAssertEqual(Motion.duration(reduced: true), 0.12)
        XCTAssertEqual(Motion.travel(reduced: true), 0)
        XCTAssertLessThan(Motion.duration(reduced: false), 0.4)
        XCTAssertLessThanOrEqual(Motion.travel(reduced: false), 24)
    }
    @MainActor private func withModel(_ run: (AppModel) throws -> Void) rethrows {
        let defaults = UserDefaults.standard
        let saved = defaults.data(forKey: "settings.v1")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root); if let saved { defaults.set(saved,forKey:"settings.v1") } else { defaults.removeObject(forKey:"settings.v1") } }
        let model = AppModel(store: BoardStore(directory: root))
        model.settings = AppSettings()
        try run(model)
    }
    @MainActor private func spin(_ duration: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(duration)) }
}
