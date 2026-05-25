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

final class AlbumRollupTests: XCTestCase {
    private func result(_ title: String, _ album: String, _ bucket: Bucket) -> ReconResult {
        ReconResult(purchase: PurchasedItem(title: title, artist: "Band", album: album),
                    bucket: bucket, matchedPersistentID: nil)
    }

    func testFullyDownloaded() {
        let reports = rollupByAlbum([result("T1", "Rec", .downloaded), result("T2", "Rec", .downloaded)])
        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(reports[0].status, .fullyDownloaded)
        XCTAssertEqual(reports[0].album, "Rec")
    }

    func testFullyMissing() {
        let reports = rollupByAlbum([result("T1", "Rec", .missing), result("T2", "Rec", .missing)])
        XCTAssertEqual(reports[0].status, .fullyMissing)
    }

    func testPartiallyDownloaded() {
        let reports = rollupByAlbum([result("T1", "Rec", .downloaded), result("T2", "Rec", .cloudOnly)])
        XCTAssertEqual(reports[0].status, .partiallyDownloaded)
    }

    func testGroupsSeparateAlbums() {
        let reports = rollupByAlbum([result("T1", "Rec A", .downloaded), result("T2", "Rec B", .missing)])
        XCTAssertEqual(reports.count, 2)
    }
}
