import XCTest
@testable import Verbatim

final class NamingAndSearchTests: XCTestCase {
    func testFirstLineTitleWithoutChangingWhitespace() {
        XCTAssertEqual(NoteNaming.title(from: "  title  \r\nbody"), "  title  ")
        XCTAssertEqual(NoteNaming.title(from: "\nbody"), "Untitled")
        XCTAssertEqual(NoteNaming.title(from: ""), "Untitled")
        XCTAssertEqual(NoteNaming.title(from: "A\u{2028}B"), "A")
    }
    func testSanitizationAndUTF8ByteLimit() {
        XCTAssertEqual(NoteNaming.stem(for: " ../a:b\\c?  "), "-a-b-c-")
        XCTAssertEqual(NoteNaming.stem(for: "..."), "Untitled")
        let name = NoteNaming.stem(for: String(repeating: "👋", count: 200))
        XCTAssertLessThanOrEqual(name.utf8.count, 180)
        XCTAssertFalse(name.isEmpty)
    }
    func testDedupIsCaseInsensitiveAndUnicodeAware() {
        XCTAssertEqual(NoteNaming.filename(for: "Hello", existing: ["hello.TXT", "Hello 2.txt"]), "Hello 3.txt")
        XCTAssertEqual(NoteNaming.filename(for: "café", existing: ["cafe\u{301}.txt"]), "café 2.txt")
    }
    func testCaseInsensitiveSubstringSearch() {
        XCTAssertTrue(SearchMatcher.matches("WORLD", title: "Hello world", body: ""))
        XCTAssertTrue(SearchMatcher.matches("needle", title: "Other", body: "A NEEDLE in text"))
        XCTAssertFalse(SearchMatcher.matches("absent", title: "Title", body: "Body"))
        XCTAssertTrue(SearchMatcher.matches("", title: "", body: ""))
        XCTAssertFalse(SearchMatcher.matches("two words", title: "two", body: "words"))
    }
}
