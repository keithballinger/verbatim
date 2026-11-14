import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindow: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard NSClassFromString("XCTestCase") == nil else { return }
        let controller = MainWindowController()
        mainWindow = controller
        installMenu()
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        controller.start()
    }

    private func installMenu() {
        let main = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Verbatim", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(MainWindowController.showSettings(_:)), keyEquivalent: ",").target = mainWindow
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Verbatim", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Verbatim", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let file = NSMenu()
        file.addItem(withTitle: "New Note", action: #selector(MainWindowController.newNote(_:)), keyEquivalent: "n").target = mainWindow
        file.addItem(withTitle: "Choose Notes Folder…", action: #selector(MainWindowController.chooseFolder(_:)), keyEquivalent: "o").target = mainWindow
        file.addItem(withTitle: "Save", action: #selector(MainWindowController.saveNote(_:)), keyEquivalent: "s").target = mainWindow
        file.addItem(withTitle: "Move Note to Trash", action: #selector(MainWindowController.trashNote(_:)), keyEquivalent: "\u{7f}").target = mainWindow
        file.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let edit = NSMenu()
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z").keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Search Notes", action: #selector(MainWindowController.focusSearch(_:)), keyEquivalent: "l").target = mainWindow
        let find = edit.addItem(withTitle: "Find in Note…", action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "f")
        find.tag = NSTextFinder.Action.showFindInterface.rawValue
        edit.addItem(.separator())
        edit.addItem(withTitle: "Check Spelling While Typing", action: #selector(MainWindowController.toggleSpelling(_:)), keyEquivalent: "").target = mainWindow
        edit.addItem(withTitle: "Check Grammar With Spelling", action: #selector(MainWindowController.toggleGrammar(_:)), keyEquivalent: "").target = mainWindow
        for (title, menu) in [("Verbatim", appMenu), ("File", file), ("Edit", edit)] {
            main.addItem(withTitle: title, action: nil, keyEquivalent: "").submenu = menu
        }
        NSApp.mainMenu = main
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        mainWindow?.showWindow(nil)
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        mainWindow?.flush() == false ? .terminateCancel : .terminateNow
    }

    func applicationDidResignActive(_ notification: Notification) { _ = mainWindow?.flush() }
}
