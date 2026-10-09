import XCTest
import AppKit
import SwiftUI
import ClotheslineCore
@testable import Clothesline

final class SettingsLayoutTests: XCTestCase {
    @MainActor func testSettingsOpensWithEnoughHeightForOptions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(store: BoardStore(directory: root))
        SettingsWindowController.shared.show(model: model)
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        let window = try XCTUnwrap(NSApplication.shared.windows.first { $0.title == "Clothesline Settings" })
        defer { window.close() }
        let content = try XCTUnwrap(window.contentView)
        XCTAssertGreaterThanOrEqual(content.bounds.height,440,"Settings content collapsed to \(content.bounds.height) points, leaving no room for its scrollable options")
        XCTAssertGreaterThanOrEqual(content.bounds.width,540)
    }
}
