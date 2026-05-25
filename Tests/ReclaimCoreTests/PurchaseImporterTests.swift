import XCTest
@testable import ReclaimCore

final class PurchaseImporterTests: XCTestCase {
    func testDetectsCommonColumns() {
        let m = detectColumns(header: ["Item Title", "Artist Name", "Collection Name", "Purchase Date"])
        XCTAssertEqual(m.title, 0)
        XCTAssertEqual(m.artist, 1)
        XCTAssertEqual(m.album, 2)
        XCTAssertEqual(m.date, 3)
    }

    func testArtistNameDoesNotStealTitleColumn() {
        // "Artist Name" contains "name"; artist is detected first so title falls to "Song".
        let m = detectColumns(header: ["Artist Name", "Song", "Album"])
        XCTAssertEqual(m.artist, 0)
        XCTAssertEqual(m.title, 1)
        XCTAssertEqual(m.album, 2)
    }

    func testImportMapsRowsAndSkipsBlankTitles() throws {
        let csv = "Title,Artist,Album\nSong A,Band,Record\n,Band,Record\nSong B,Band,Record\n"
        let items = try importPurchases(csv: csv)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0], PurchasedItem(title: "Song A", artist: "Band", album: "Record"))
        XCTAssertEqual(items[1].title, "Song B")
    }

    func testHonorsExplicitMapping() throws {
        let csv = "col0,col1\nThe Artist,The Song\n"
        var mapping = ColumnMapping()
        mapping.title = 1
        mapping.artist = 0
        let items = try importPurchases(csv: csv, mapping: mapping)
        XCTAssertEqual(items[0], PurchasedItem(title: "The Song", artist: "The Artist"))
    }

    func testThrowsWhenNoTitleColumn() {
        let csv = "Foo,Bar\n1,2\n"
        XCTAssertThrowsError(try importPurchases(csv: csv)) { error in
            XCTAssertEqual(error as? ImportError, .noTitleColumn)
        }
    }
}
