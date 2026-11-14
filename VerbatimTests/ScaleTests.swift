import XCTest
@testable import Verbatim

final class ScaleTests: XCTestCase {
    func testTenThousandNoteCatalogAndBodySearch() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for n in 0..<10_000 {
            let body = n == 9_999 ? "unique body needle" : "ordinary text"
            try Data("Title \(n)\n\(body)".utf8).write(to: folder.appendingPathComponent("Note \(n).txt"))
        }
        let start = ContinuousClock.now
        let notes = try NoteCatalog.list(folder)
        let enumerated = ContinuousClock.now
        XCTAssertEqual(notes.count, 10_000)
        XCTAssertTrue(notes.contains { $0.title == "Note 9999" }) // Enumeration did not read title contents.
        let opened = try NoteStorage.load(folder.appendingPathComponent("Note 9999.txt"))
        let loaded = ContinuousClock.now
        XCTAssertEqual(NoteNaming.title(from: opened.text), "Title 9999")
        let worker = SearchWorker()
        let filtered = try await worker.filter(notes, query: "BODY NEEDLE")
        let searched = ContinuousClock.now
        XCTAssertEqual(filtered.map(\.url.lastPathComponent), ["Note 9999.txt"])
        print("SCALE 10000 notes — metadata: \(start.duration(to: enumerated)); open: \(enumerated.duration(to: loaded)); uncached body search: \(loaded.duration(to: searched))")
        // Deliberately generous regression bound: hardware speed is not a correctness assertion.
        XCTAssertLessThan(start.duration(to: enumerated), .seconds(10))
    }
}
