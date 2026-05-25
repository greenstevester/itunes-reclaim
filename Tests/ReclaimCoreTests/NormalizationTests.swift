import XCTest
@testable import ReclaimCore

final class NormalizationTests: XCTestCase {
    func testLowercasesAndTrims() {
        XCTAssertEqual(normalize("  Hello World  "), "hello world")
    }
    func testFoldsDiacritics() {
        XCTAssertEqual(normalize("Beyoncé"), "beyonce")
    }
    func testNormalizesAmpersand() {
        XCTAssertEqual(normalize("Simon & Garfunkel"), "simon and garfunkel")
    }
    func testStripsParentheticalNoise() {
        XCTAssertEqual(normalize("Song (Remastered 2011)"), "song")
        XCTAssertEqual(normalize("Album [Deluxe Edition]"), "album")
    }
    func testStripsFeaturing() {
        XCTAssertEqual(normalize("Track feat. Someone"), "track")
        XCTAssertEqual(normalize("Track featuring Someone Else"), "track")
    }
    func testCollapsesPunctuationAndWhitespace() {
        XCTAssertEqual(normalize("Rock'n'Roll!!  Now"), "rock n roll now")
    }
}
