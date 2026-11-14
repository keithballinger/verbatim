import AppKit
import XCTest
@testable import Verbatim

final class ExternalEditTests: XCTestCase {
    @MainActor func testReturningToCurrentNoteCancelsPendingLoadAndFolderSwitchStillLoads() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let other = root.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let a = try NoteStorage.create(text: "A\none", in: root)
        let b = try NoteStorage.create(text: "B\ntwo", in: root)
        let c = try NoteStorage.create(text: "C\nthree", in: other)
        let suite = "VerbatimTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = MainWindowController(defaults: defaults)
        controller.useFolder(root)
        controller.open(a.url)
        try await eventually { controller.editor.isEditable && controller.editor.string == a.text }
        controller.open(b.url)
        controller.open(a.url)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(controller.editor.string, a.text)
        XCTAssertTrue(controller.editor.isEditable)
        controller.open(b.url)
        controller.useFolder(other)
        try await eventually { controller.editor.isEditable && controller.editor.string == c.text }
        controller.close()
    }

    @MainActor func testCleanReloadAndDirtyConflictThroughWindowController() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = try NoteStorage.create(text: "Title\nbaseline", in: folder)
        let suite = "VerbatimTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = MainWindowController(defaults: defaults)
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
