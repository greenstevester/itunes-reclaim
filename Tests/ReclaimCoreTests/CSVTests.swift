import XCTest
@testable import ReclaimCore

final class CSVTests: XCTestCase {
    func testSimpleRows() {
        XCTAssertEqual(parseCSV("a,b,c\n1,2,3"), [["a","b","c"], ["1","2","3"]])
    }
    func testQuotedFieldWithComma() {
        XCTAssertEqual(parseCSV("\"a,b\",c"), [["a,b", "c"]])
    }
    func testEscapedQuotes() {
        XCTAssertEqual(parseCSV("\"she said \"\"hi\"\"\",x"), [["she said \"hi\"", "x"]])
    }
    func testCRLFLineEndings() {
        XCTAssertEqual(parseCSV("a,b\r\n1,2\r\n"), [["a","b"], ["1","2"]])
    }
    func testIgnoresTrailingBlankLine() {
        XCTAssertEqual(parseCSV("a,b\n1,2\n"), [["a","b"], ["1","2"]])
    }
}
