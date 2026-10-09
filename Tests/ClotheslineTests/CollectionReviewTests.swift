import XCTest
import AppKit
import ClotheslineCore
@testable import Clothesline

final class CollectionReviewTests: XCTestCase {
    private let ids = (0..<8).map { _ in UUID() }

    func testEmptyGridHasNoNavigationTarget() {
        XCTAssertNil(CollectionNavigation.destination(ids: [], selected: [], anchor: nil, columns: 3, direction: .down))
    }

    func testVerticalNavigationUsesColumnsAndClampsIncompleteLastRow() {
        XCTAssertEqual(destination(from: 2, direction: .down), ids[5])
        XCTAssertEqual(destination(from: 5, direction: .down), ids[7])
        XCTAssertEqual(destination(from: 7, direction: .up), ids[4])
        XCTAssertEqual(destination(from: 1, direction: .up), ids[1])
        XCTAssertEqual(destination(from: 6, direction: .down), ids[6])
    }

    func testHorizontalNavigationStopsAtCollectionEdges() {
        XCTAssertEqual(destination(from: 0, direction: .left), ids[0])
        XCTAssertEqual(destination(from: 7, direction: .right), ids[7])
        XCTAssertEqual(destination(from: 2, direction: .right), ids[3])
    }

    func testStaleOrDeselectedAnchorUsesVisibleSelection() {
        XCTAssertEqual(CollectionNavigation.destination(ids: ids, selected: [ids[3]], anchor: UUID(), columns: 3, direction: .down), ids[6])
        XCTAssertEqual(CollectionNavigation.destination(ids: ids, selected: [ids[3]], anchor: ids[0], columns: 3, direction: .right), ids[4])
    }

    func testNoVisibleSelectionStartsAtFirstItemAndInvalidColumnsAreSafe() {
        XCTAssertEqual(CollectionNavigation.destination(ids: ids, selected: [UUID()], anchor: nil, columns: 3, direction: .up), ids[0])
        XCTAssertEqual(CollectionNavigation.destination(ids: ids, selected: [ids[0]], anchor: ids[0], columns: 0, direction: .down), ids[1])
    }

    func testDragPreviewSizePreservesAspectRatioAndHandlesInvalidImages() {
        XCTAssertEqual(CollectionDragPreview.size(for: CGSize(width: 600, height: 300)), CGSize(width: 96, height: 48))
        XCTAssertEqual(CollectionDragPreview.size(for: CGSize(width: 300, height: 600)), CGSize(width: 48, height: 96))
        XCTAssertEqual(CollectionDragPreview.size(for: .zero), CGSize(width: 48, height: 48))
    }

    private func destination(from index: Int, direction: CollectionNavigation.Direction) -> UUID? {
        CollectionNavigation.destination(ids: ids, selected: [ids[index]], anchor: ids[index], columns: 3, direction: direction)
    }
}


extension CollectionReviewTests {
    @MainActor func testNativeResponderNavigationDeleteUndoAndTextEditingIsolation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let saved = UserDefaults.standard.data(forKey: "settings.v1")
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: "settings.v1") }
            else { UserDefaults.standard.removeObject(forKey: "settings.v1") }
        }
        _ = NSApplication.shared
        let model = AppModel(store: BoardStore(directory: root))
        _ = model.hang(text: "First", source: .manual)
        _ = model.hang(text: "Second", source: .manual)
        let ids = model.visibleItems.map(\.id)
        let line = LineView(model: model)
        let actions = WorkflowActions(model: model, view: line)
        var moved: UUID?
        let keyboard = CollectionKeyboardView(model: model, actions: actions, columns: 1, onNavigate: { moved = $0 })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let content = try XCTUnwrap(window.contentView)
        content.addSubview(keyboard)
        let card = CollectionDragView(model: model, item: model.visibleItems[0], actions: actions)
        content.addSubview(card)
        XCTAssertTrue(card.accessibilityPerformPress())
        XCTAssertTrue(window.firstResponder === keyboard)
        keyboard.keyDown(with: key(code: 125, window: window))
        XCTAssertEqual(model.selectedIDs, [ids[1]])
        XCTAssertEqual(moved, ids[1])
        keyboard.keyDown(with: key(code: 51, window: window))
        XCTAssertNil(model.board.item(ids[1]))
        XCTAssertTrue(model.canUndoRemoval)
        XCTAssertTrue(keyboard.performKeyEquivalent(with: key(code: 6, characters: "z", flags: .command, window: window)))
        XCTAssertNotNil(model.board.item(ids[1]))
        XCTAssertTrue(keyboard.performKeyEquivalent(with: key(code: 0, characters: "a", flags: .command, window: window)))
        XCTAssertEqual(model.selectedIDs, Set(ids))
        let search = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
        content.addSubview(search)
        XCTAssertTrue(window.makeFirstResponder(search))
        model.selectedIDs = []
        XCTAssertFalse(keyboard.performKeyEquivalent(with: key(code: 0, characters: "a", flags: .command, window: window)))
        XCTAssertTrue(model.selectedIDs.isEmpty)
        withExtendedLifetime(line) {}
    }

    @MainActor private func key(code: UInt16, characters: String = "", flags: NSEvent.ModifierFlags = [], window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                         windowNumber: window.windowNumber, context: nil, characters: characters,
                         charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
    }
}
