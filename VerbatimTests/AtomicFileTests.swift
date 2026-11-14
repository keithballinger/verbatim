import XCTest
@testable import Verbatim

final class AtomicFileTests: XCTestCase {
    var folder: URL!
    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: folder) }

    func testExactUTF8RoundTripAndReplacement() throws {
        let url = folder.appendingPathComponent("note.txt")
        let text = "\"quotes\" -- café 👋\r\n\t trailing  \n"
        try AtomicFile.write(text, to: url)
        XCTAssertEqual(try Data(contentsOf: url), Data(text.utf8))
        try AtomicFile.write("replacement", to: url)
        XCTAssertEqual(try AtomicFile.read(url), "replacement")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["note.txt"])
    }

    func testInvalidUTF8IsRejectedWithoutChangingFile() throws {
        let url = folder.appendingPathComponent("note.txt")
        let bytes = Data([0xff, 0xfe])
        try bytes.write(to: url)
        XCTAssertThrowsError(try AtomicFile.read(url))
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    func testSymlinkIsNotOverwritten() throws {
        let target = folder.appendingPathComponent("original.txt")
        let link = folder.appendingPathComponent("link.txt")
        try Data("original".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertThrowsError(try AtomicFile.write("changed", to: link))
        XCTAssertEqual(try AtomicFile.read(target), "original")
    }

    func testConcurrentReadersSeeOnlyCompleteAtomicWrites() async throws {
        let url = folder.appendingPathComponent("atomic.txt")
        let old = String(repeating: "a", count: 32_768)
        let new = String(repeating: "👋", count: 8_192)
        try AtomicFile.write(old, to: url)
        let writer = Task.detached {
            for n in 0..<100 { try AtomicFile.write(n.isMultiple(of: 2) ? new : old, to: url) }
        }
        for _ in 0..<200 {
            let bytes = try Data(contentsOf: url)
            XCTAssertTrue(bytes == Data(old.utf8) || bytes == Data(new.utf8))
        }
        try await writer.value
    }
}
