import XCTest
@testable import ClotheslineCore

final class WorkflowTests: XCTestCase {
    func testSearchAcrossLinesAndAccentsWithoutReordering() {
        let a = Line(name: "Work"), b = Line(name: "Personal")
        let note = HangingItem(kind: .text, source: .manual, title: "Café", lineID: b.id, text: "Invoice due")
        let image = HangingItem(kind: .image, source: .drop, title: "Picture", lineID: a.id)
        let board = Board(lines: [a, b], items: [image, note])
        XCTAssertEqual(ItemSearch.results(board: board, query: "CAFE").map(\.id), [note.id])
        XCTAssertEqual(ItemSearch.results(board: board, query: "invoice").map(\.id), [note.id])
        XCTAssertEqual(ItemSearch.results(board: board, query: "receipt", recognizedText: [image.id: "Receipt total"]).map(\.id), [image.id])
        XCTAssertEqual(ItemSearch.results(board: board, query: "  ").map(\.id), [image.id])
        XCTAssertEqual(board.items.map(\.id), [image.id, note.id])
    }
    func testEditingNoteKeepsIdentityAndLine() {
        var board = Board.makeDefault()
        let note = HangingItem(kind: .text, source: .manual, title: "Old", lineID: board.activeLineID, text: "Old")
        board.add(note)
        board.editNote(note.id, text: "New content")
        XCTAssertEqual(board.item(note.id)?.text, "New content")
        XCTAssertEqual(board.item(note.id)?.title, "New content")
        XCTAssertEqual(board.item(note.id)?.lineID, note.lineID)
    }
    func testLegacySettingsAndCompactRoundTrip() throws {
        let legacy = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(legacy.appearanceStyle, .illustrated)
        var compact = legacy
        compact.appearanceStyle = .compact
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(compact)).appearanceStyle, .compact)
    }
    func testNamesCannotEscapeAndCollisionsAreCaseInsensitive() {
        XCTAssertEqual(ExportNames.safe("../../Report: Q1"), "Report Q1")
        XCTAssertEqual(ExportNames.safe("..."), "Item")
        var used = Set<String>()
        XCTAssertEqual(ExportNames.unique("Report.pdf", used: &used), "Report.pdf")
        XCTAssertEqual(ExportNames.unique("report.pdf", used: &used), "report 2.pdf")
        XCTAssertEqual(ExportNames.unique("report.pdf", used: &used), "report 3.pdf")
    }
    func testRecipeRejectsInvalidDimensionsAndQuality() {
        var options = RecipeOptions(recipe: .clientHandoff)
        XCTAssertNoThrow(try options.validate())
        options.maxEdge = 0
        XCTAssertThrowsError(try options.validate())
        options.maxEdge = 1600
        options.quality = .nan
        XCTAssertThrowsError(try options.validate())
    }
}
