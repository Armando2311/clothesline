import XCTest
import AppKit
import ClotheslineCore
@testable import Clothesline

final class HoverThemeTests: XCTestCase {
    @MainActor func testEscapeClosesEvenWithSelectionAndSearch() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(store: BoardStore(directory: root))
        let id = model.createNote("Keep this note")!
        let controller = PanelController(model: model)
        controller.show(.explicit)
        model.selectedIDs = [id]
        model.query = "Keep"
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: controller.panel.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
        controller.lineView.keyDown(with: event)
        XCTAssertFalse(controller.isVisible)
        XCTAssertNotNil(model.board.item(id))
        controller.panel.orderOut(nil)
    }

    @MainActor func testToolbarStartsHiddenAndHoverRevealsIt() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let view = LineView(model: AppModel(store: BoardStore(directory: root)))
        view.willAppear(animated: false)
        let toolbar = view.subviews.first!
        XCTAssertTrue(toolbar.isHidden)
        let enter = NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
        view.mouseEntered(with: enter)
        XCTAssertFalse(toolbar.isHidden)
        let exit = NSEvent.enterExitEvent(with: .mouseExited, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
        view.mouseExited(with: exit)
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        XCTAssertTrue(toolbar.isHidden)
        view.focusSearch()
        XCTAssertFalse(toolbar.isHidden)
        view.willDisappear()
        view.willAppear(animated: false)
        XCTAssertTrue(toolbar.isHidden)
        view.willDisappear()
    }

    @MainActor func testKeyboardSearchPinsToolbarWhilePointerLeaves() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = PanelController(model: AppModel(store: BoardStore(directory: root)))
        controller.show(.explicit)
        controller.lineView.focusSearch()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        XCTAssertTrue(controller.lineView.toolbarVisible)
        XCTAssertFalse(controller.panel.firstResponder === controller.lineView)
        let exit = NSEvent.enterExitEvent(with: .mouseExited, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: controller.panel.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
        controller.lineView.mouseExited(with: exit)
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        XCTAssertTrue(controller.lineView.toolbarVisible)
        controller.hide()
        controller.panel.orderOut(nil)
    }

    @MainActor func testNativeGlassSwitchKeepsLineAsInteractiveContent() throws {
        let defaults = UserDefaults.standard
        let saved = defaults.data(forKey: "settings.v1")
        defer { if let saved { defaults.set(saved,forKey: "settings.v1") } else { defaults.removeObject(forKey: "settings.v1") } }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(store: BoardStore(directory: root))
        model.settings.theme = .liquidGlass
        let controller = PanelController(model: model)
        controller.show(.explicit)
        XCTAssertFalse(controller.panel.isOpaque)
        XCTAssertTrue(controller.lineView.window === controller.panel)
        XCTAssertEqual(controller.lineView.bounds.width,controller.panel.frame.width,accuracy: 1)
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            let container = try XCTUnwrap(controller.panel.contentView as? GlassBackdropView)
            let effect = try XCTUnwrap(container.subviews.compactMap { $0 as? NSGlassEffectView }.first)
            XCTAssertTrue(effect.contentView === controller.lineView)
            XCTAssertEqual(effect.style,.clear)
        }
        #endif
        model.settings.theme = .sakuraMorning
        controller.refreshLayout()
        XCTAssertTrue(controller.panel.contentView === controller.lineView)
        XCTAssertEqual(controller.lineView.theme.id,.sakuraMorning)
        controller.hide()
        controller.panel.orderOut(nil)
    }

    func testExpandedThemesArePersistableAndNamed() throws {
        for name in ["sakuraMorning", "oceanBreeze", "lavenderTwilight", "liquidGlass"] {
            let choice = try XCTUnwrap(ThemeChoice(rawValue: name))
            XCTAssertFalse(choice.displayName.isEmpty)
            XCTAssertEqual(try JSONDecoder().decode(ThemeChoice.self,from: JSONEncoder().encode(choice)),choice)
        }
    }
    @MainActor func testPinnedToolbarSurvivesPointerExitAndReopening() throws {
        let defaults = UserDefaults.standard
        let saved = defaults.data(forKey: "settings.v1")
        defer { if let saved { defaults.set(saved,forKey: "settings.v1") } else { defaults.removeObject(forKey: "settings.v1") } }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(store: BoardStore(directory: root))
        model.settings = try JSONDecoder().decode(AppSettings.self,from: Data(#"{"keepToolbarVisible":true}"#.utf8))
        let view = LineView(model: model)
        view.willAppear(animated: false)
        XCTAssertTrue(view.toolbarVisible)
        let exit = NSEvent.enterExitEvent(with: .mouseExited, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
        view.mouseExited(with: exit)
        XCTAssertTrue(view.toolbarVisible)
        view.willDisappear()
        XCTAssertFalse(view.toolbarVisible)
        view.willAppear(animated: false)
        XCTAssertTrue(view.toolbarVisible)
        model.settings = AppSettings()
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        XCTAssertFalse(view.toolbarVisible)
        view.willDisappear()
    }

    func testToolbarPinSettingRoundTripsAndDefaultsOff() throws {
        for value in [true,false] {
            let settings = try JSONDecoder().decode(AppSettings.self,from: Data("{\"keepToolbarVisible\":\(value)}".utf8))
            let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as! [String:Any]
            XCTAssertEqual(encoded["keepToolbarVisible"] as? Bool,value)
        }
        let legacy = try JSONDecoder().decode(AppSettings.self,from: Data("{}".utf8))
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as! [String:Any]
        XCTAssertEqual(encoded["keepToolbarVisible"] as? Bool,false)
    }

    @MainActor func testNoThemeHasNoBackdropInEitherStyle() throws {
        let choice = try XCTUnwrap(ThemeChoice(rawValue: "noTheme"))
        let defaults = UserDefaults.standard
        let saved = defaults.data(forKey: "settings.v1")
        defer { if let saved { defaults.set(saved,forKey: "settings.v1") } else { defaults.removeObject(forKey: "settings.v1") } }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(store: BoardStore(directory: root))
        model.settings.theme = .liquidGlass
        let controller = PanelController(model: model)
        controller.show(.explicit)
        model.settings.theme = choice
        for style in [AppearanceStyle.illustrated,.compact] {
            model.settings.appearanceStyle = style
            controller.refreshLayout()
            XCTAssertTrue(controller.panel.contentView === controller.lineView)
            XCTAssertFalse(controller.panel.isOpaque)
            XCTAssertFalse(controller.panel.hasShadow)
            XCTAssertNil(controller.lineView.layer?.backgroundColor)
            let sky = try XCTUnwrap(controller.lineView.layer?.sublayers?.compactMap { $0 as? SkyLayer }.first)
            XCTAssertTrue(sky.isHidden)
        }
        controller.hide()
        controller.panel.orderOut(nil)
    }

}
