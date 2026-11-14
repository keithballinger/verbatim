import Foundation
import XCTest
@testable import Verbatim

final class ImporterTests: XCTestCase {
    private final class FakeSource: AppleNotesReading {
        func identifiers() throws -> [String] { ["one", "two", "locked", "failed"] }
        func read(identifier: String) throws -> AppleNoteContent {
            switch identifier {
            case "one": return .text("Same title\n\"quotes\" -- café\r\n", modified: nil)
            case "two": return .text("Same title\ndifferent body", modified: nil)
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

    private struct DatedSource: AppleNotesReading {
        let modified: Date?
        func identifiers() throws -> [String] { ["dated"] }
        func read(identifier: String) throws -> AppleNoteContent { .text("Dated\nbody", modified: modified) }
    }

    private func importedModificationDate(from source: DatedSource) throws -> Date {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        XCTAssertEqual(try NotesImporter.run(source: source, folder: folder).imported, 1)
        let attributes = try FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent("Dated.txt").path)
        return try XCTUnwrap(attributes[.modificationDate] as? Date)
    }

    func testImportedFileCarriesTheNoteModificationDate() throws {
        let modified = Date(timeIntervalSince1970: 1_600_000_000)
        XCTAssertEqual(try importedModificationDate(from: DatedSource(modified: modified)), modified)
    }

    func testImportedFileWithoutASourceDateIsStampedWithTheImportTime() throws {
        let started = Date()
        let stamped = try importedModificationDate(from: DatedSource(modified: nil))
        XCTAssertLessThan(abs(stamped.timeIntervalSince(started)), 60)
    }

    func testAppleScriptCompilesWithoutExecutingOrReadingNotes() async throws {
        try await Task.detached { _ = try AppleNotesSource() }.value
    }
}
