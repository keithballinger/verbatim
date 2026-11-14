import XCTest
@testable import Verbatim

final class StorageTests: XCTestCase {
    var folder: URL!
    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: folder) }

    func testSaveRenamesAndDeduplicatesWithoutAlteringText() throws {
        let first = try NoteStorage.create(text: "Old\nbody", in: folder)
        _ = try NoteStorage.create(text: "New\nother", in: folder)
        let saved = try NoteStorage.save("New\n\"literal\" --  ", over: first).snapshot
        XCTAssertEqual(saved.url.lastPathComponent, "New 2.txt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.url.path))
        XCTAssertEqual(try AtomicFile.read(saved.url), "New\n\"literal\" --  ")
        XCTAssertEqual(try AtomicFile.read(folder.appendingPathComponent("New.txt")), "New\nother")
    }

    func testBodyOnlyEditKeepsExistingFilename() throws {
        let url = folder.appendingPathComponent("External filename.txt")
        try AtomicFile.create("Title\nbody", at: url)
        let result = try NoteStorage.save("Title\nedited", over: NoteStorage.load(url))
        XCTAssertEqual(result.snapshot.url, url)
    }

    func testExternalEditPreservesBothVersions() throws {
        let first = try NoteStorage.create(text: "Title\nbaseline", in: folder)
        try AtomicFile.write("Title\nexternal", to: first.url)
        let result = try NoteStorage.save("Title\nmine", over: first)
        XCTAssertNotNil(result.notice)
        XCTAssertNotEqual(result.snapshot.url, first.url)
        XCTAssertEqual(try AtomicFile.read(first.url), "Title\nexternal")
        XCTAssertEqual(try AtomicFile.read(result.snapshot.url), "Title\nmine")
    }

    func testExternalDeletionDoesNotResurrectOriginal() throws {
        let first = try NoteStorage.create(text: "Title\nbaseline", in: folder)
        try FileManager.default.removeItem(at: first.url)
        let result = try NoteStorage.save("Title\nmine", over: first)
        XCTAssertNotEqual(result.snapshot.url, first.url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.url.path))
        XCTAssertEqual(try AtomicFile.read(result.snapshot.url), "Title\nmine")
    }

    func testNormalizationOnlyEditIsSavedAsDifferentBytes() throws {
        let first = try NoteStorage.create(text: "Title\ncafé", in: folder)
        let updated = "Title\ncafe\u{301}"
        XCTAssertEqual(first.text, updated) // Swift's canonical-equivalence comparison.
        let result = try NoteStorage.save(updated, over: first)
        XCTAssertEqual(try Data(contentsOf: result.snapshot.url), Data(updated.utf8))
    }

    func testBOMBodyEditSavesWithoutFalseConflictOrByteRemoval() throws {
        let first = try NoteStorage.create(text: "\u{feff}Title\r\nbody", in: folder)
        let loaded = try NoteStorage.load(first.url)
        let edited = "\u{feff}Title\r\nnew body"
        let result = try NoteStorage.save(edited, over: loaded)
        XCTAssertNil(result.notice)
        XCTAssertEqual(result.snapshot.url, first.url)
        XCTAssertEqual(try Data(contentsOf: first.url), Data(edited.utf8))
    }

    func testAtomicCreateRefusesCollisionAndLeavesNoTemporaryFile() throws {
        let first = try NoteStorage.create(text: "Title\noriginal", in: folder)
        XCTAssertThrowsError(try AtomicFile.create("replacement", at: first.url))
        XCTAssertEqual(try AtomicFile.read(first.url), first.text)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["Title.txt"])
    }

    func testSerialAutosaveThenFlushUsesLatestBaseline() throws {
        let first = try NoteStorage.create(text: "First\noriginal", in: folder)
        let session = NoteSession(first)
        let done = expectation(description: "Background save")
        session.save("Second\nintermediate") { result in
            if case .failure(let error) = result { XCTFail(error.localizedDescription) }
            done.fulfill()
        }
        let receipt = try session.flush("Final\nlast")
        XCTAssertEqual(try AtomicFile.read(receipt.snapshot.url), "Final\nlast")
        XCTAssertEqual(receipt.snapshot.url.lastPathComponent, "Final.txt")
        wait(for: [done], timeout: 5)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["Final.txt"])
    }

    func testConflictNoticeSurvivesAnImmediateLifecycleFlush() throws {
        let first = try NoteStorage.create(text: "Title\nbaseline", in: folder)
        let session = NoteSession(first)
        try AtomicFile.write("Title\nexternal", to: first.url)
        let done = expectation(description: "Conflict save")
        session.save("Title\nmine") { result in
            if case .success(let receipt) = result { XCTAssertNotNil(receipt.notice) }
            else { XCTFail("Conflict save failed") }
            done.fulfill()
        }
        let flushed = try session.flush("Title\nmine")
        XCTAssertNotNil(flushed.notice)
        XCTAssertEqual(try AtomicFile.read(first.url), "Title\nexternal")
        XCTAssertEqual(try AtomicFile.read(flushed.snapshot.url), "Title\nmine")
        wait(for: [done], timeout: 5)
    }
}
