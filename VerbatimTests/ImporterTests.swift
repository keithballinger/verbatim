import Foundation
import XCTest
@testable import Verbatim

final class ImporterTests: XCTestCase {
    private final class FakeSource: AppleNotesReading {
        func identifiers() throws -> [String] { ["one", "two", "locked", "failed"] }
        func read(identifier: String) throws -> AppleNoteContent {
            switch identifier {
            case "one": return .text("Same title\n\"quotes\" -- café\r\n")
            case "two": return .text("Same title\ndifferent body")
            case "locked": return .locked
            default: throw ImportError.script("Synthetic read failure")
            }
        }
    }

    func testImportPreservesPlaintextDeduplicatesAndReportsSkippedNotes() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = try NotesImporter.run(source: FakeSource(), folder: folder)
        XCTAssertEqual(first.imported, 2)
        XCTAssertEqual(first.locked, 1)
        XCTAssertEqual(first.failed, 1)
        XCTAssertEqual(try AtomicFile.read(folder.appendingPathComponent("Same title.txt")), "Same title\n\"quotes\" -- café\r\n")
        XCTAssertEqual(try AtomicFile.read(folder.appendingPathComponent("Same title 2.txt")), "Same title\ndifferent body")
        let second = try NotesImporter.run(source: FakeSource(), folder: folder)
        XCTAssertEqual(second.imported, 0)
        XCTAssertEqual(second.unchanged, 2)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).count, 2)
    }

    func testAppleScriptCompilesWithoutExecutingOrReadingNotes() async throws {
        try await Task.detached { _ = try AppleNotesSource() }.value
    }
}
