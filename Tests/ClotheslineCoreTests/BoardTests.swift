import XCTest
@testable import ClotheslineCore

final class BoardTests: XCTestCase {
    private func fileItem(_ path: String, line: UUID, kind: ItemKind = .image, date: Date = Date(), pinned: Bool = false, owned: Bool = false) -> HangingItem {
        HangingItem(kind: kind, source: .drop, title: (path as NSString).lastPathComponent, dateAdded: date, lineID: line, pinned: pinned,
                    file: FileReference(path: path, bookmark: nil, ownership: owned ? .owned : .referenced))
    }

    func testAddAppendsAndDeduplicates() {
        var board = Board.makeDefault()
        let line = board.activeLineID
        XCTAssertEqual(board.add(fileItem("/tmp/a.png", line: line)).isAdded, true)
        XCTAssertEqual(board.add(fileItem("/tmp/b.png", line: line)).isAdded, true)
        // Same path (even written differently) is not hung twice.
        XCTAssertEqual(board.add(fileItem("/tmp/./a.png", line: line)).isAdded, false)
        XCTAssertEqual(board.activeItems.map(\.title), ["a.png", "b.png"])
    }

    func testSameFileMayHangOnDifferentLines() {
        var board = Board.makeDefault()
        let second = board.addLine(named: "Work")
        board.add(fileItem("/tmp/a.png", line: board.activeLineID))
        XCTAssertTrue(board.add(fileItem("/tmp/a.png", line: second.id)).isAdded)
        XCTAssertEqual(board.items.count, 2)
    }

    func testInsertAtPosition() {
        var board = Board.makeDefault()
        let line = board.activeLineID
        board.add(fileItem("/a", line: line))
        board.add(fileItem("/c", line: line))
        board.add(fileItem("/b", line: line), atLinePosition: 1)
        XCTAssertEqual(board.activeItems.map(\.title), ["a", "b", "c"])
    }

    func testRemoveReturnsRemovedItems() {
        var board = Board.makeDefault()
        let line = board.activeLineID
        let a = fileItem("/a", line: line), b = fileItem("/b", line: line)
        board.add(a); board.add(b)
        let removed = board.remove([a.id])
        XCTAssertEqual(removed.map(\.id), [a.id])
        XCTAssertEqual(board.activeItems.map(\.id), [b.id])
    }

    func testClearKeepsPinnedByDefault() {
        var board = Board.makeDefault()
        let line = board.activeLineID
        board.add(fileItem("/a", line: line, pinned: true))
        board.add(fileItem("/b", line: line))
        board.clear(lineID: line)
        XCTAssertEqual(board.activeItems.map(\.title), ["a"])
        board.clear(lineID: line, includingPinned: true)
        XCTAssertTrue(board.activeItems.isEmpty)
    }

    func testMoveWithinLineKeepsRelativeOrder() {
        var board = Board.makeDefault()
        let line = board.activeLineID
        let items = ["/a", "/b", "/c", "/d", "/e"].map { fileItem($0, line: line) }
        items.forEach { board.add($0) }
        // Move b and d to the front.
        board.move([items[1].id, items[3].id], toLinePosition: 0, lineID: line)
        XCTAssertEqual(board.activeItems.map(\.title), ["b", "d", "a", "c", "e"])
        // Move a to the end.
        board.move([items[0].id], toLinePosition: 99, lineID: line)
        XCTAssertEqual(board.activeItems.map(\.title), ["b", "d", "c", "e", "a"])
    }

    func testMoveWithinLineIgnoresOtherLines() {
        var board = Board.makeDefault()
        let main = board.activeLineID
        let work = board.addLine(named: "Work")
        board.add(fileItem("/w1", line: work.id))
        let a = fileItem("/a", line: main), b = fileItem("/b", line: main)
        board.add(a); board.add(b)
        board.add(fileItem("/w2", line: work.id))
        board.move([b.id], toLinePosition: 0, lineID: main)
        XCTAssertEqual(board.items(on: main).map(\.title), ["b", "a"])
        XCTAssertEqual(board.items(on: work.id).map(\.title), ["w1", "w2"])
    }

    func testMoveToLineSkipsDuplicates() {
        var board = Board.makeDefault()
        let main = board.activeLineID
        let work = board.addLine(named: "Work")
        let a = fileItem("/a", line: main), b = fileItem("/b", line: main)
        board.add(a); board.add(b)
        board.add(fileItem("/a", line: work.id))
        board.move([a.id, b.id], toLine: work.id)
        XCTAssertEqual(board.items(on: work.id).map(\.title), ["a", "b"])
        // a stays on main because work already had it.
        XCTAssertEqual(board.items(on: main).map(\.title), ["a"])
    }

    func testDeleteLineMovesItemsToNeighbour() {
        var board = Board.makeDefault()
        let main = board.activeLineID
        let work = board.addLine(named: "Work")
        board.add(fileItem("/w", line: work.id))
        board.activate(lineID: work.id)
        board.deleteLine(work.id)
        XCTAssertEqual(board.lines.count, 1)
        XCTAssertEqual(board.activeLineID, main)
        XCTAssertEqual(board.items(on: main).map(\.title), ["w"])
        // Last line cannot be deleted.
        board.deleteLine(main)
        XCTAssertEqual(board.lines.count, 1)
    }

    func testUniqueLineNames() {
        var board = Board.makeDefault()
        XCTAssertEqual(board.addLine(named: "Work").name, "Work")
        XCTAssertEqual(board.addLine(named: "Work").name, "Work 2")
        XCTAssertEqual(board.addLine(named: "  ").name, "Line")
    }

    func testSortPutsPinnedFirstAndIsStable() {
        var board = Board.makeDefault()
        let line = board.activeLineID
        let t0 = Date(timeIntervalSince1970: 1000)
        board.add(fileItem("/z.png", line: line, date: t0.addingTimeInterval(3)))
        board.add(fileItem("/b.pdf", line: line, kind: .pdf, date: t0.addingTimeInterval(1)))
        board.add(fileItem("/a.png", line: line, date: t0.addingTimeInterval(2), pinned: true))
        board.sort(lineID: line, by: .dateAdded)
        XCTAssertEqual(board.activeItems.map(\.title), ["a.png", "b.pdf", "z.png"])
        board.sort(lineID: line, by: .name)
        XCTAssertEqual(board.activeItems.map(\.title), ["a.png", "b.pdf", "z.png"])
        board.sort(lineID: line, by: .kind)
        XCTAssertEqual(board.activeItems.map(\.title), ["a.png", "z.png", "b.pdf"])
    }

    func testRepairFixesOrphansAndDuplicates() {
        let line = Line(name: "Main")
        let orphan = HangingItem(kind: .text, source: .manual, title: "x", lineID: UUID(), text: "x")
        var board = Board(lines: [line], items: [orphan, orphan], activeLineID: UUID())
        board.repair()
        XCTAssertEqual(board.items.count, 1)
        XCTAssertEqual(board.items[0].lineID, line.id)
        XCTAssertEqual(board.activeLineID, line.id)
    }

    func testJitterIsStableAndBounded() {
        let item = HangingItem(kind: .text, source: .manual, title: "x", lineID: UUID(), text: "x")
        let a = item.jitter(1), b = item.jitter(1), c = item.jitter(2)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
        for ch in 0..<50 {
            let v = item.jitter(UInt64(ch))
            XCTAssertGreaterThanOrEqual(v, -1)
            XCTAssertLessThanOrEqual(v, 1)
        }
    }
}

extension Board.AddOutcome {
    var isAdded: Bool {
        if case .added = self { return true }
        return false
    }
}
