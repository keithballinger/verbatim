import AppKit
import XCTest
@testable import Verbatim

final class ExternalEditTests: XCTestCase {
    @MainActor func testCleanReloadAndDirtyConflictThroughWindowController() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = try NoteStorage.create(text: "Title\nbaseline", in: folder)
        let controller = MainWindowController()
        controller.useFolder(folder)
        controller.open(first.url)
        try await eventually { controller.editor.isEditable }
        XCTAssertEqual(controller.editor.string, first.text)

        try AtomicFile.write("Title\nexternal", to: first.url)
        try await eventually { controller.editor.string == "Title\nexternal" }

        controller.window?.makeFirstResponder(controller.editor)
        controller.editor.insertText("mine", replacementRange: NSRange(location: 6, length: 8))
        XCTAssertEqual(controller.editor.string, "Title\nmine")
        try AtomicFile.write("Title\nsecond external", to: first.url)
        try await eventually {
            (try? NoteCatalog.list(folder).count) == 2
        }
        XCTAssertEqual(try AtomicFile.read(first.url), "Title\nsecond external")
        let copies = try NoteCatalog.list(folder).filter { $0.url != first.url }
        XCTAssertEqual(try AtomicFile.read(copies[0].url), "Title\nmine")
        XCTAssertEqual(controller.editor.string, "Title\nmine")
        XCTAssertTrue(controller.flush())
        controller.close()
    }

    @MainActor private func eventually(_ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !predicate(), Date() < deadline { try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertTrue(predicate(), "Timed out waiting for folder reconciliation")
    }
}
