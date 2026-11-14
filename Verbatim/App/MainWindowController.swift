import AppKit

final class MainWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSTextViewDelegate {
    let editor = VerbatimTextView()
    private let search = NSSearchField()
    private let table = NSTableView()
    private let status = NSTextField(labelWithString: "Choose a notes folder to begin.")
    private let access = FolderAccess()
    private let worker = SearchWorker()
    private var notes: [NoteRecord] = []
    private var visible: [NoteRecord] = []
    private var folder: URL?
    private var currentURL: URL?
    private var original = ""
    private var searchTask: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var suppressSelection = false
    private var searching = false
    private var generation = 0

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Verbatim"
        window.minSize = NSSize(width: 620, height: 380)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setFrameAutosaveName("VerbatimMainWindow")
        buildUI()
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("Use init()") }

    private func buildUI() {
        let root = NSView()
        window?.contentView = root
        search.placeholderString = "Search notes or type a title…"
        search.delegate = self
        search.sendsSearchStringImmediately = true
        search.sendsWholeSearchString = false
        search.setAccessibilityLabel("Search notes or create a note")
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title")))
        table.headerView = nil
        table.rowHeight = 30
        table.style = .sourceList
        table.delegate = self
        table.dataSource = self
        table.allowsEmptySelection = true
        table.setAccessibilityLabel("Notes")
        let listScroll = NSScrollView()
        listScroll.hasVerticalScroller = true
        listScroll.documentView = table
        let editorScroll = NSScrollView()
        editorScroll.hasVerticalScroller = true
        editorScroll.autohidesScrollers = true
        editorScroll.documentView = editor
        editor.delegate = self
        editor.isEditable = false
        editor.setAccessibilityLabel("Note text")
        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.addArrangedSubview(listScroll)
        split.addArrangedSubview(editorScroll)
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingMiddle
        for view in [search, split, status] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            search.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            search.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            search.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            split.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 12),
            split.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            split.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -6),
            status.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            status.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            status.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8),
            listScroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
            editorScroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 300)
        ])
        split.setPosition(280, ofDividerAt: 0)
    }

    func start() {
        window?.makeFirstResponder(search)
        do {
            if let restored = try access.restore() { useFolder(restored) }
            else { chooseFolder(nil) }
        } catch { show(error); chooseFolder(nil) }
    }

    @objc func chooseFolder(_ sender: Any?) {
        guard flush(), let window else { return }
        access.choose(for: window) { [weak self] result in
            switch result {
            case .success(let url): if let url { self?.useFolder(url) }
            case .failure(let error): self?.show(error)
            }
        }
    }

    private func useFolder(_ url: URL) {
        loadTask?.cancel()
        currentURL = nil
        editor.string = ""
        original = ""
        editor.isEditable = false
        folder = url
        window?.representedURL = url
        refresh()
    }

    private func refresh() {
        guard let folder else { return }
        generation += 1
        let version = generation
        scanTask?.cancel()
        searchTask?.cancel()
        status.stringValue = "Loading notes…"
        scanTask = Task { @MainActor [weak self] in
            do {
                let records = try await Task.detached(priority: .userInitiated) { try NoteCatalog.list(folder) }.value
                guard let self, !Task.isCancelled, self.generation == version else { return }
                self.notes = records
                self.applyFilter()
                for start in stride(from: 0, to: records.count, by: 128) {
                    let batch = Array(records[start..<min(start + 128, records.count)])
                    let titles = try await self.worker.titles(batch)
                    guard !Task.isCancelled, self.generation == version else { return }
                    for index in self.notes.indices {
                        if let title = titles[self.notes[index].url] { self.notes[index].title = title }
                    }
                }
                self.applyFilter()
            } catch is CancellationError { } catch { self?.show(error) }
        }
    }

    func controlTextDidChange(_ obj: Notification) { applyFilter() }

    private func applyFilter() {
        searchTask?.cancel()
        let query = search.stringValue
        let records = notes
        if query.isEmpty {
            searching = false
            updateList(records)
            return
        }
        searching = true
        updateList(records.filter { SearchMatcher.matches(query, title: $0.title, body: "") })
        status.stringValue = "Searching note text…"
        searchTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(80))
                guard let self else { return }
                let result = try await self.worker.filter(records, query: query)
                try Task.checkCancellation()
                self.searching = false
                self.updateList(result)
            } catch is CancellationError { } catch { self?.show(error) }
        }
    }

    private func updateList(_ records: [NoteRecord]) {
        suppressSelection = true
        visible = records
        table.reloadData()
        if let currentURL, let row = visible.firstIndex(where: { $0.url == currentURL }) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else { table.deselectAll(nil) }
        suppressSelection = false
        if !searching { status.stringValue = "\(records.count) of \(notes.count) notes" }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { visible.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("NoteTitle")
        let field = table.makeView(withIdentifier: identifier, owner: self) as? NSTextField ?? NSTextField(labelWithString: "")
        field.identifier = identifier
        field.stringValue = visible[row].title
        field.lineBreakMode = .byTruncatingTail
        return field
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !suppressSelection, visible.indices.contains(table.selectedRow) else { return }
        open(visible[table.selectedRow].url)
    }

    private func open(_ url: URL) {
        guard url != currentURL, flush() else { return }
        loadTask?.cancel()
        editor.isEditable = false
        loadTask = Task { @MainActor [weak self] in
            do {
                let text = try await Task.detached(priority: .userInitiated) { try AtomicFile.read(url) }.value
                guard let self, !Task.isCancelled else { return }
                self.currentURL = url
                self.original = text
                self.editor.string = text
                self.editor.undoManager?.removeAllActions()
                self.editor.isEditable = true
                self.editor.setSelectedRange(NSRange(location: 0, length: 0))
                self.window?.title = "\(NoteNaming.title(from: text)) — Verbatim"
            } catch { self?.show(error) }
        }
    }

    @objc func focusSearch(_ sender: Any?) { window?.makeFirstResponder(search); search.selectText(nil) }
    @objc func newNote(_ sender: Any?) { create(title: "") }
    private func create(title: String) {
        guard let folder, flush() else { return }
        do {
            loadTask?.cancel()
            let existing = Set(try FileManager.default.contentsOfDirectory(atPath: folder.path))
            let name = NoteNaming.filename(for: NoteNaming.title(from: title), existing: existing)
            let url = folder.appendingPathComponent(name)
            try Data(title.utf8).write(to: url, options: .withoutOverwriting)
            currentURL = url
            original = title
            editor.string = title
            editor.isEditable = true
            editor.undoManager?.removeAllActions()
            editor.setSelectedRange(NSRange(location: (title as NSString).length, length: 0))
            search.stringValue = ""
            refresh()
            window?.makeFirstResponder(editor)
        } catch { show(error) }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.moveDown(_:)) || commandSelector == #selector(NSResponder.moveUp(_:)) {
            guard !visible.isEmpty else { return true }
            let down = commandSelector == #selector(NSResponder.moveDown(_:))
            let row = table.selectedRow < 0 ? (down ? 0 : visible.count - 1) : min(max(table.selectedRow + (down ? 1 : -1), 0), visible.count - 1)
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            table.scrollRowToVisible(row)
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            guard !searching else { status.stringValue = "Search is still running. Press Return when it finishes."; return true }
            if visible.isEmpty { create(title: search.stringValue) }
            else {
                let row = table.selectedRow >= 0 ? table.selectedRow : 0
                table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                window?.makeFirstResponder(editor)
            }
            return true
        }
        return false
    }

    @objc func saveNote(_ sender: Any?) { if flush() { refresh() } }
    @discardableResult func flush() -> Bool {
        guard let currentURL, editor.string != original else { return true }
        do { try AtomicFile.write(editor.string, to: currentURL); original = editor.string; return true }
        catch { show(error); return false }
    }

    @objc func trashNote(_ sender: Any?) {
        guard let currentURL, flush() else { return }
        editor.isEditable = false
        NSWorkspace.shared.recycle([currentURL]) { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error { self.show(error); self.editor.isEditable = true; return }
                self.currentURL = nil
                self.editor.string = ""
                self.original = ""
                self.refresh()
            }
        }
    }

    private func show(_ error: Error) { status.stringValue = error.localizedDescription }
    func windowShouldClose(_ sender: NSWindow) -> Bool { flush() }
}
