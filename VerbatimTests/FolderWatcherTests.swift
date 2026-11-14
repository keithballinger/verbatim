import XCTest
@testable import Verbatim

final class FolderWatcherTests: XCTestCase {
    func testDetectsCreationInPlaceWriteAtomicReplacementRenameAndRemoval() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("one.txt")
        let renamed = folder.appendingPathComponent("two.txt")
        let lock = NSLock()
        var pending: XCTestExpectation?
        let watcher = try FolderWatcher(folder: folder) { _ in
            lock.lock()
            let expectation = pending
            pending = nil
            lock.unlock()
            expectation?.fulfill()
        }
        func observe(_ name: String, change: () throws -> Void) throws {
            let event = expectation(description: name)
            lock.lock(); pending = event; lock.unlock()
            try change()
            wait(for: [event], timeout: 5)
        }
        try observe("create") { try AtomicFile.create("One", at: url) }
        try observe("in-place write") {
            let file = try FileHandle(forWritingTo: url)
            try file.write(contentsOf: Data("Edited".utf8))
            try file.close()
        }
        try observe("atomic replacement") { try AtomicFile.write("Replaced", to: url) }
        try observe("rename") { try FileManager.default.moveItem(at: url, to: renamed) }
        try observe("remove") { try FileManager.default.removeItem(at: renamed) }
        withExtendedLifetime(watcher) { }
    }

    func testCatalogIgnoresNestedFilesAndSymlinks() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let sub = folder.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try AtomicFile.create("Visible", at: folder.appendingPathComponent("visible.TXT"))
        try AtomicFile.create("Nested", at: sub.appendingPathComponent("nested.txt"))
        try AtomicFile.create("Hidden", at: folder.appendingPathComponent(".hidden.txt"))
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("link.txt"),
                                                  withDestinationURL: folder.appendingPathComponent("visible.TXT"))
        XCTAssertEqual(try NoteCatalog.list(folder).map(\.title), ["visible"])
    }
}
