import XCTest
@testable import ReclaimCore

final class ReconcilerTests: XCTestCase {
    // Qualified as ReclaimCore.LibraryItem: the bare name collides with
    // DeveloperToolsSupport.LibraryItem, which is in scope for the test target.
    private func lib(_ title: String, _ artist: String, _ album: String,
                     downloaded: Bool, id: String) -> ReclaimCore.LibraryItem {
        ReclaimCore.LibraryItem(title: title, artist: artist, album: album, persistentID: id, isDownloaded: downloaded)
    }

    func testStrongMatchDownloaded() {
        let p = PurchasedItem(title: "Song", artist: "Band", album: "Record")
        let l = [lib("Song", "Band", "Record", downloaded: true, id: "A")]
        let r = Reconciler().reconcile(purchases: [p], library: l)
        XCTAssertEqual(r[0].bucket, .downloaded)
        XCTAssertEqual(r[0].matchedPersistentID, "A")
    }

    func testStrongMatchCloudOnly() {
        let p = PurchasedItem(title: "Song", artist: "Band", album: "Record")
        let l = [lib("Song", "Band", "Record", downloaded: false, id: "A")]
        let r = Reconciler().reconcile(purchases: [p], library: l)
        XCTAssertEqual(r[0].bucket, .cloudOnly)
    }

    func testStrongMatchSurvivesNoiseSuffix() {
        // Purchase title carries a remaster suffix the library lacks.
        let p = PurchasedItem(title: "Song (Remastered 2011)", artist: "Band", album: "Record (Deluxe)")
        let l = [lib("Song", "Band", "Record", downloaded: true, id: "A")]
        let r = Reconciler().reconcile(purchases: [p], library: l)
        XCTAssertEqual(r[0].bucket, .downloaded)
    }

    func testWeakMatchIsUncertain() {
        // Same artist+title, different album → weak match only.
        let p = PurchasedItem(title: "Song", artist: "Band", album: "Greatest Hits")
        let l = [lib("Song", "Band", "Original Album", downloaded: true, id: "A")]
        let r = Reconciler().reconcile(purchases: [p], library: l)
        XCTAssertEqual(r[0].bucket, .uncertain)
        XCTAssertEqual(r[0].matchedPersistentID, "A")
    }

    func testNoMatchIsMissing() {
        let p = PurchasedItem(title: "Ghost", artist: "Nobody", album: "Nowhere")
        let l = [lib("Song", "Band", "Record", downloaded: true, id: "A")]
        let r = Reconciler().reconcile(purchases: [p], library: l)
        XCTAssertEqual(r[0].bucket, .missing)
        XCTAssertNil(r[0].matchedPersistentID)
    }

    func testStrongMatchPrefersDownloadedDuplicate() {
        let p = PurchasedItem(title: "Song", artist: "Band", album: "Record")
        let l = [
            lib("Song", "Band", "Record", downloaded: false, id: "cloud"),
            lib("Song", "Band", "Record", downloaded: true, id: "local"),
        ]
        let r = Reconciler().reconcile(purchases: [p], library: l)
        XCTAssertEqual(r[0].bucket, .downloaded)
        XCTAssertEqual(r[0].matchedPersistentID, "local")
    }
}
