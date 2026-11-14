import AppKit
import XCTest
@testable import Verbatim

final class ExternalEditTests: XCTestCase {
    @MainActor func testTimestampPreservingExternalEditRefreshesTitleAndEditor() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = try NoteStorage.create(text: "Title\nbody", in: folder)
        let attributes = try FileManager.default.attributesOfItem(atPath: first.url.path)
        let suite = "VerbatimTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = MainWindowController(defaults: defaults)
        controller.useFolder(folder)
        func rowTitle() -> String? { rowTitles(controller).first }
        try await eventually { controller.editor.isEditable && rowTitle() == "Title" }
        try AtomicFile.write("Other\nbody", to: first.url) // Same byte length, original mtime restored.
        try FileManager.default.setAttributes([.modificationDate: attributes[.modificationDate]!], ofItemAtPath: first.url.path)
        try await eventually { controller.editor.string == "Other\nbody" && rowTitle() == "Other" }
        controller.close()
    }

    @MainActor func testSingleReturnWaitsForBodySearchBeforeCreatingNote() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = try NoteStorage.create(text: "Existing\nbody", in: folder)
        let suite = "VerbatimTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = MainWindowController(defaults: defaults)
        controller.useFolder(folder)
        try await eventually { controller.editor.isEditable && controller.editor.string == first.text }
        let field = controller.search
        let query = "New \"literal\" -- title"
        field.stringValue = query
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        XCTAssertTrue(controller.control(field, textView: controller.editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        try await eventually { controller.editor.string == query }
        let notes = try NoteCatalog.list(folder)
        XCTAssertEqual(notes.count, 2)
        let created = try XCTUnwrap(notes.first { $0.url != first.url })
        XCTAssertEqual(try AtomicFile.read(created.url), query)
        field.stringValue = "body"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        XCTAssertTrue(controller.control(field, textView: controller.editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        try await eventually { controller.editor.string == first.text }
        XCTAssertEqual(try NoteCatalog.list(folder).count, 2, "A body-only match must not create a duplicate note")
        controller.close()
    }

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

    @MainActor func testCatalogListsMostRecentlyModifiedFirst() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let now = Date()
        for (name, age) in [("Middle", 200.0), ("Oldest", 300.0), ("Newest", 100.0)] {
            let note = try NoteStorage.create(text: name, in: folder)
            try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: note.url.path)
        }
        XCTAssertEqual(try NoteCatalog.list(folder).map(\.title), ["Newest", "Middle", "Oldest"])
    }

    @MainActor func testEditedNoteMovesToTopOfListImmediately() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let older = try NoteStorage.create(text: "Older\nbody", in: folder)
        let newer = try NoteStorage.create(text: "Newer\nbody", in: folder)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-200)], ofItemAtPath: older.url.path)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-100)], ofItemAtPath: newer.url.path)
        let suite = "VerbatimTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = MainWindowController(defaults: defaults)
        controller.useFolder(folder)
        controller.open(older.url)
        try await eventually {
            controller.editor.isEditable && controller.editor.string == older.text && rowTitles(controller) == ["Newer", "Older"]
        }
        controller.window?.makeFirstResponder(controller.editor)
        controller.editor.insertText("!", replacementRange: NSRange(location: 10, length: 0))
        XCTAssertEqual(controller.editor.string, "Older\nbody!")
        XCTAssertTrue(controller.flush())
        XCTAssertEqual(rowTitles(controller), ["Older", "Newer"], "A saved edit must reorder the list without waiting for a rescan")
        controller.close()
    }

    @MainActor func testLeavingAnUneditedNoteKeepsItsPlaceAndDate() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let older = try NoteStorage.create(text: "Older\nbody", in: folder)
        let newer = try NoteStorage.create(text: "Newer\nbody", in: folder)
        let olderDate = Date(timeIntervalSince1970: 1_600_000_000)
        try FileManager.default.setAttributes([.modificationDate: olderDate], ofItemAtPath: older.url.path)
        try FileManager.default.setAttributes([.modificationDate: olderDate.addingTimeInterval(86_400)], ofItemAtPath: newer.url.path)
        let suite = "VerbatimTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = MainWindowController(defaults: defaults)
        controller.useFolder(folder)
        controller.open(older.url)
        try await eventually {
            controller.editor.isEditable && controller.editor.string == older.text && rowTitles(controller) == ["Newer", "Older"]
        }
        controller.open(newer.url) // What clicking another row does: the note being left is flushed first.
        XCTAssertEqual(rowTitles(controller), ["Newer", "Older"], "Leaving a note without editing it must not reorder the list")
        let cell = try XCTUnwrap(controller.table.view(atColumn: 0, row: 1, makeIfNecessary: true) as? NoteCellView)
        XCTAssertEqual(cell.detail.stringValue, NoteDateText.string(for: olderDate))
        controller.close()
    }

    @MainActor func testRowShowsWhenTheNoteWasLastModified() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let note = try NoteStorage.create(text: "Old note", in: folder)
        let modified = Date(timeIntervalSince1970: 1_600_000_000)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: note.url.path)
        let suite = "VerbatimTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = MainWindowController(defaults: defaults)
        controller.useFolder(folder)
        try await eventually { rowTitles(controller) == ["Old note"] }
        let cell = try XCTUnwrap(controller.table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NoteCellView)
        XCTAssertEqual(cell.detail.stringValue, NoteDateText.string(for: modified))
        XCTAssertFalse(cell.detail.stringValue.isEmpty)
        controller.close()
    }

    @MainActor func testStatusCountsNotesAndNarrowsWhileSearching() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = try NoteStorage.create(text: "Apples", in: folder)
        _ = try NoteStorage.create(text: "Pears", in: folder)
        let suite = "VerbatimTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = MainWindowController(defaults: defaults)
        controller.useFolder(folder)
        try await eventually { controller.editor.isEditable && controller.status.stringValue == "2 notes" }
        controller.search.stringValue = "pear"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: controller.search))
        try await eventually { controller.status.stringValue == "1 of 2 notes" }
        controller.close()
    }

    @MainActor private func rowTitles(_ controller: MainWindowController) -> [String] {
        (0..<controller.table.numberOfRows).compactMap { row in
            (controller.table.view(atColumn: 0, row: row, makeIfNecessary: true) as? NoteCellView)?.textField?.stringValue
        }
    }

    @MainActor private func eventually(_ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !predicate(), Date() < deadline { try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertTrue(predicate(), "Timed out waiting for folder reconciliation")
    }
}
