import XCTest
@testable import ClotheslineCore

final class SearchFilterTests: XCTestCase {
    func testFiltersCombineAcrossLinesAndDateBoundary() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let a = Line(name:"A"), b = Line(name:"B")
        let matching = HangingItem(kind:.screenshot,source:.screenshot,title:"Café invoice",dateAdded:now,lineID:b.id)
        let old = HangingItem(kind:.screenshot,source:.screenshot,title:"Cafe invoice",dateAdded:now.addingTimeInterval(-10*86400),lineID:b.id)
        let wrong = HangingItem(kind:.pdf,source:.drop,title:"Cafe invoice",dateAdded:now,lineID:a.id)
        let board = Board(lines:[a,b],items:[matching,old,wrong])
        var filters = SearchFilters()
        filters.kind = .screenshot; filters.source = .screenshot; filters.lineID = b.id; filters.period = .week
        XCTAssertEqual(filters.results(board:board,query:"cafe invoice",now:now).map(\.id),[matching.id])
        XCTAssertTrue(filters.isActive)
        XCTAssertEqual(SearchFilters().results(board:board,query:"").map(\.id),[wrong.id])
    }
    func testOCRMatchesAndMatchExcerpt() {
        let line = Line(name:"Main")
        let item = HangingItem(kind:.image,source:.drop,title:"Photo",lineID:line.id)
        let board = Board(lines:[line],items:[item])
        XCTAssertEqual(SearchFilters().results(board:board,query:"order",recognizedText:[item.id:"Order number 123"]).map(\.id),[item.id])
        XCTAssertEqual(SearchFilters.excerpt("Header\nOrder number 123\nFooter",query:"order"),"Order number 123")
    }
}
