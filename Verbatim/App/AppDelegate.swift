import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private let editor = VerbatimTextView()
    private var fileURL: URL?
    private var original = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hosted unit tests must never open panels or touch the user's notes.
        guard NSClassFromString("XCTestCase") == nil else { return }
        installMenu()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 680),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Verbatim"
        window.delegate = self
        window.isReleasedWhenClosed = false
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.documentView = editor
        window.contentView = scroll
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(editor)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func installMenu() {
        let main = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Verbatim", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let file = NSMenu()
        file.addItem(withTitle: "Open…", action: #selector(openFile), keyEquivalent: "o")
        file.addItem(withTitle: "Save", action: #selector(saveFile), keyEquivalent: "s")
        let edit = NSMenu()
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        for (title, menu) in [("Verbatim", appMenu), ("File", file), ("Edit", edit)] {
            let item = main.addItem(withTitle: title, action: nil, keyEquivalent: "")
            item.submenu = menu
        }
        NSApp.mainMenu = main
    }

    @objc private func openFile() {
        guard saveIfNeeded() else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let text = try AtomicFile.read(url)
            fileURL = url
            editor.string = text
            editor.undoManager?.removeAllActions()
            original = text
            window.title = url.lastPathComponent
        } catch { NSApp.presentError(error) }
    }

    @objc private func saveFile() { _ = saveIfNeeded() }

    private func saveIfNeeded() -> Bool {
        guard editor.string != original else { return true }
        if fileURL == nil {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.plainText]
            panel.nameFieldStringValue = "Untitled.txt"
            guard panel.runModal() == .OK else { return false }
            fileURL = panel.url
        }
        guard let url = fileURL else { return false }
        do {
            try AtomicFile.write(editor.string, to: url)
            original = editor.string
            window.title = url.lastPathComponent
            return true
        } catch { NSApp.presentError(error); return false }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { saveIfNeeded() }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        saveIfNeeded() ? .terminateNow : .terminateCancel
    }
}
