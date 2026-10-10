import XCTest
import AppKit
import ClotheslineCore
@testable import Clothesline

final class PremiumModelTests: XCTestCase {
    @MainActor func testOwnedRemovedItemRestoresAfterRelaunchAndGarbageCollection() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let store = BoardStore(directory:root)
        let model = AppModel(store:store)
        let url = try store.makeOwnedFileURL(preferredName:"sample.txt")
        try Data("original".utf8).write(to:url)
        let id = try XCTUnwrap(model.hang(fileURLs:[url],source:.drop,ownership:.owned).first)
        model.remove([id]); model.prepareForTermination()
        XCTAssertTrue(FileManager.default.fileExists(atPath:url.path))
        let restarted = AppModel(store:store)
        XCTAssertTrue(restarted.board.items.isEmpty)
        let removed = try XCTUnwrap(restarted.activity.history.first { $0.action == .removed })
        restarted.restoreActivity(removed)
        XCTAssertNotNil(restarted.board.item(id))
        XCTAssertEqual(try String(contentsOf:url),"original")
    }
    @MainActor func testRulesRoutingFiltersDuplicateFeedbackAndGroupsPersist() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let model = AppModel(store:BoardStore(directory:root))
        let original = model.board.activeLineID
        let target = model.addLine(named:"Screenshots").id
        model.activate(lineID:original)
        model.activity.upsert(CollectionRule(name:"Clipboard notes",lineID:target,source:.clipboard,kind:.text))
        let id = try XCTUnwrap(model.hang(text:"A routed note",source:.clipboard))
        XCTAssertEqual(model.board.item(id)?.lineID,target)
        XCTAssertNil(model.hang(text:"A routed note",source:.clipboard))
        XCTAssertEqual(model.statusMessage,"Already collected")
        model.searchFilters.kind = .text
        XCTAssertEqual(model.visibleItems.map(\.id),[id])
        model.searchFilters = SearchFilters(); model.activate(lineID:target)
        let second = try XCTUnwrap(model.createNote("Other"))
        model.groupItems([id,second],named:"Research")
        model.saveNow()
        let restarted = AppModel(store:BoardStore(directory:root))
        XCTAssertEqual(restarted.groupName(for:try XCTUnwrap(restarted.board.item(id))),"Research")
        XCTAssertEqual(restarted.activity.rules.count,1)
    }
    @MainActor func testEveryMutationIsDurableWithoutWaitingForDebounce() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let store = BoardStore(directory:root)
        let model = AppModel(store:store)
        let id = try XCTUnwrap(model.createNote("Recover me"))
        XCTAssertNotNil(AppModel(store:store).board.item(id))
    }
    @MainActor func testCollapsedGroupsNeverHideSearchMatches() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let model = AppModel(store:BoardStore(directory:root))
        let a = try XCTUnwrap(model.createNote("First")), b = try XCTUnwrap(model.createNote("Second"))
        model.groupItems([a,b],named:"Stack")
        XCTAssertEqual(model.ropeItems.count,1)
        XCTAssertEqual(model.groupDisplayName(for:try XCTUnwrap(model.board.item(a))),"Stack · 2 items")
        model.query = "Second"
        XCTAssertEqual(model.ropeItems.map(\.id),[b])
        model.query = ""
        XCTAssertTrue(model.expandGroup(for:try XCTUnwrap(model.board.item(a))))
        XCTAssertEqual(model.ropeItems.count,2)
    }
    @MainActor func testCopyOCRWorksWithoutSearchingFirst() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let image = NSImage(size:NSSize(width:40,height:40),flipped:false) { rect in NSColor.white.setFill(); rect.fill(); return true }
        let rep = try XCTUnwrap(NSBitmapImageRep(data:try XCTUnwrap(image.tiffRepresentation)))
        let url = root.appendingPathComponent("text.png")
        try XCTUnwrap(rep.representation(using:.png,properties:[:])).write(to:url)
        let index = OCRIndex(cacheURL:root.appendingPathComponent("ocr.json"),recognizer:{ _ in "Recognized content" })
        let model = AppModel(store:BoardStore(directory:root.appendingPathComponent("state")),ocrIndex:index)
        model.hang(fileURLs:[url],source:.drop)
        XCTAssertFalse(model.isSearching)
        let text = await model.textForCopy(model.activeItems)
        XCTAssertEqual(text,"Recognized content")
        XCTAssertEqual(model.recognizedText.count,1)
    }

    @MainActor func testFailedSaveRemainsVisibleAfterAddFeedback() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let blocked = root.appendingPathComponent("blocked")
        try Data("file blocks directory".utf8).write(to:blocked)
        let model = AppModel(store:BoardStore(directory:blocked))
        model.createNote("Must not claim saved")
        XCTAssertTrue(model.statusMessage?.contains("Could not save") == true)
    }
    @MainActor func testDropDestinationOverridesActiveLineDuplicateAndRules() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let model = AppModel(store:BoardStore(directory:root))
        let a = model.board.activeLineID, b = model.addLine(named:"B").id
        model.activate(lineID:a)
        let text = "A duplicated drop"
        model.hang(text:text,source:.drop)
        let pb = NSPasteboard.withUniqueName(); defer { pb.releaseGlobally() }
        pb.setString(text,forType:.string)
        let ids = PasteboardImporter.importContents(of:pb,into:model,source:.drop,lineID:b)
        XCTAssertEqual(ids.count,1)
        XCTAssertEqual(model.board.items(on:b).first?.text,text)
        XCTAssertEqual(model.board.activeLineID,a)
    }
    @MainActor func testCollapsedStackDropBoundaryUsesFullBoardPosition() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let model = AppModel(store:BoardStore(directory:root))
        let a = model.createNote("A")!, b = model.createNote("B")!, c = model.createNote("C")!, d = model.createNote("D")!
        model.groupItems([a,b],named:"Stack")
        model.move([d],toPosition:model.linePosition(forVisibleInsertion:3,movingIDs:[d]))
        XCTAssertEqual(model.activeItems.map(\.id),[a,b,c,d])
        XCTAssertEqual(model.dragItems(for:[a]).map(\.id),[a,b])
    }

}
