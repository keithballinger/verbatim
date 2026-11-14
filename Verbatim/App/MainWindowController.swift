import AppKit

final class MainWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSTextViewDelegate, NSMenuItemValidation {
    let editor = VerbatimTextView()
    private let search = NSSearchField()
    private let table = NSTableView()
    private let status = NSTextField(labelWithString: "Choose a notes folder to begin.")
    private let access: FolderAccess
    private let defaults: UserDefaults
    private let worker = SearchWorker()
    private var notes: [NoteRecord] = []
    private var visible: [NoteRecord] = []
    private var folder: URL?
    private var currentURL: URL?
    private var original = ""
    private var session: NoteSession?
    private var appliedSaveSequence = 0
    private var autosave: DispatchWorkItem?
    private var notice: String?
    private var searchTask: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var suppressSelection = false
    private var searching = false
    private var generation = 0
    private var watcher: FolderWatcher?
    private var watchDebounce: DispatchWorkItem?
    private var trashInProgress = false
    private var settings: SettingsWindowController?
    private var initialCatalogLoaded = false
    private let searchEditor: VerbatimTextView = {
        let view = VerbatimTextView()
        view.isFieldEditor = true
        view.textContainerInset = .zero
        view.font = .systemFont(ofSize: NSFont.systemFontSize)
        return view
    }()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        access = FolderAccess(defaults: defaults)
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
        editor.font = EditorPreferences.font(defaults: defaults)
        editor.isContinuousSpellCheckingEnabled = defaults.bool(forKey: "spellChecking")
        editor.isGrammarCheckingEnabled = defaults.bool(forKey: "grammarChecking")
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
        guard !trashInProgress, flush(), let window else { return }
        access.choose(for: window) { [weak self] result in
            switch result {
            case .success(let url): if let url { self?.useFolder(url) }
            case .failure(let error): self?.show(error)
            }
        }
    }

    func useFolder(_ url: URL) {
        watcher = nil
        watchDebounce?.cancel()
        loadTask?.cancel()
        currentURL = nil
        session = nil
        notice = nil
        editor.string = ""
        original = ""
        notes = []
        initialCatalogLoaded = false
        editor.isEditable = false
        folder = url
        window?.representedURL = url
        do {
            watcher = try FolderWatcher(folder: url) { [weak self] in
                DispatchQueue.main.async { self?.folderChanged() }
            }
        } catch { show(error) }
        refresh()
        if let last = defaults.string(forKey: "lastNoteFilename"),
           defaults.string(forKey: "lastNoteFolder") == url.path,
           !last.contains("/"), last != ".", last != "..", last.lowercased().hasSuffix(".txt") {
            open(url.appendingPathComponent(last))
        }
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
                let prior = Dictionary(uniqueKeysWithValues: self.notes.map { ($0.url, $0) })
                self.notes = records.map { record in
                    var record = record
                    if let old = prior[record.url], old.modified == record.modified, old.size == record.size { record.title = old.title }
                    return record
                }
                self.initialCatalogLoaded = true
                self.applyFilter()
                if self.session == nil, self.loadTask == nil {
                    if let first = records.first { self.open(first.url) }
                    else { self.create(title: "") }
                }
                let changed = records.filter { record in
                    guard let old = prior[record.url] else { return true }
                    return old.modified != record.modified || old.size != record.size
                }
                for start in stride(from: 0, to: changed.count, by: 128) {
                    let batch = Array(changed[start..<min(start + 128, changed.count)])
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
        if !searching { status.stringValue = notice ?? "\(records.count) of \(notes.count) notes" }
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

    func open(_ url: URL) {
        guard !trashInProgress, url != currentURL, flush() else { return }
        loadTask?.cancel()
        editor.isEditable = false
        loadTask = Task { @MainActor [weak self] in
            do {
                let text = try await Task.detached(priority: .userInitiated) { try AtomicFile.read(url) }.value
                guard let self, !Task.isCancelled else { return }
                self.currentURL = url
                self.loadTask = nil
                self.original = text
                self.session = NoteSession(NoteSnapshot(url: url, text: text))
                self.appliedSaveSequence = 0
                self.editor.string = text
                self.editor.undoManager?.removeAllActions()
                self.editor.isEditable = true
                self.editor.setSelectedRange(NSRange(location: 0, length: 0))
                self.window?.title = "\(NoteNaming.title(from: text)) — Verbatim"
                self.rememberSelection()
                self.updateList(self.visible)
                LaunchMeasurement.editorReady()
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.editor.isEditable = self.session != nil
                self.loadTask = nil
                self.show(error)
                if self.initialCatalogLoaded, self.session == nil, let first = self.notes.first, first.url != url { self.open(first.url) }
            }
        }
    }

    @objc func focusSearch(_ sender: Any?) { window?.makeFirstResponder(search); search.selectText(nil) }
    @objc func newNote(_ sender: Any?) { create(title: "") }
    private func create(title: String) {
        guard !trashInProgress, let folder, flush() else { return }
        do {
            loadTask?.cancel()
            let snapshot = try NoteStorage.create(text: title, in: folder)
            currentURL = snapshot.url
            session = NoteSession(snapshot)
            appliedSaveSequence = 0
            original = title
            rememberSelection()
            window?.title = "\(NoteNaming.title(from: title)) — Verbatim"
            editor.string = title
            editor.isEditable = true
            editor.undoManager?.removeAllActions()
            editor.setSelectedRange(NSRange(location: (title as NSString).length, length: 0))
            search.stringValue = ""
            refresh()
            window?.makeFirstResponder(editor)
            LaunchMeasurement.editorReady()
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
        autosave?.cancel()
        guard let session else { return true }
        do { apply(try session.flush(editor.string), session: session); return true }
        catch { show(error); return false }
    }

    func textDidChange(_ notification: Notification) {
        guard let session else { return }
        window?.isDocumentEdited = true
        autosave?.cancel()
        let text = editor.string
        let item = DispatchWorkItem { [weak self, session] in
            session.save(text) { [weak self, session] result in
                guard let self, self.session === session else { return }
                switch result {
                case .success(let receipt): self.apply(receipt, session: session)
                case .failure(let error): self.show(error)
                }
            }
        }
        autosave = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    private func apply(_ receipt: SaveReceipt, session: NoteSession) {
        guard self.session === session, receipt.sequence >= appliedSaveSequence else { return }
        appliedSaveSequence = receipt.sequence
        let previousURL = currentURL
        currentURL = receipt.snapshot.url
        original = receipt.snapshot.text
        rememberSelection()
        window?.isDocumentEdited = !editor.string.utf8.elementsEqual(original.utf8)
        window?.title = "\(NoteNaming.title(from: editor.string)) — Verbatim"
        if let message = receipt.notice { notice = message; status.stringValue = message }
        if let index = notes.firstIndex(where: { $0.url == previousURL }) {
            notes[index] = NoteRecord(url: receipt.snapshot.url, title: NoteNaming.title(from: original),
                                      modified: Date(), size: receipt.snapshot.bytes.count)
            applyFilter()
        }
    }

    func windowDidResignKey(_ notification: Notification) { _ = flush() }

    private func folderChanged() {
        watchDebounce?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.searchTask?.cancel()
            Task { await self.worker.invalidate() }
            self.reconcileOpenNote()
            self.refresh()
        }
        watchDebounce = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
    }

    private func reconcileOpenNote() {
        guard !trashInProgress, let session else { return }
        session.inspectDisk { [weak self, session] result in
            guard let self, self.session === session else { return }
            do {
                let state = try result.get()
                guard state.sequence >= self.appliedSaveSequence else { return }
                if let disk = state.diskText, disk.utf8.elementsEqual(state.baseline.text.utf8) { return }
                if !self.editor.string.utf8.elementsEqual(state.baseline.text.utf8) {
                    self.autosave?.cancel()
                    session.save(self.editor.string) { [weak self, session] result in
                        guard let self, self.session === session else { return }
                        switch result {
                        case .success(let receipt): self.apply(receipt, session: session); self.refresh()
                        case .failure(let error): self.show(error)
                        }
                    }
                } else if let disk = state.diskText {
                    let selection = self.editor.selectedRange()
                    self.editor.string = disk
                    self.editor.undoManager?.removeAllActions()
                    self.editor.setSelectedRange(NSRange(location: min(selection.location, (disk as NSString).length), length: 0))
                    self.original = disk
                    self.session = NoteSession(NoteSnapshot(url: state.baseline.url, text: disk))
                    self.appliedSaveSequence = 0
                    self.window?.title = "\(NoteNaming.title(from: disk)) — Verbatim"
                } else {
                    self.loadTask?.cancel()
                    self.currentURL = nil
                    self.session = nil
                    self.editor.string = ""
                    self.editor.isEditable = false
                    self.original = ""
                    self.notice = "The open note was moved or removed outside Verbatim."
                    self.status.stringValue = self.notice!
                }
            } catch { self.show(error) }
        }
    }

    func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?) -> Any? {
        (client as? NSSearchField) === search ? searchEditor : nil
    }

    private func rememberSelection() {
        defaults.set(currentURL?.lastPathComponent, forKey: "lastNoteFilename")
        defaults.set(folder?.path, forKey: "lastNoteFolder")
    }

    @objc func showSettings(_ sender: Any?) {
        if settings == nil {
            settings = SettingsWindowController(font: editor.font ?? EditorPreferences.font()) { [weak self] font in
                self?.editor.font = font
            }
        }
        settings?.showWindow(nil)
    }

    @objc func toggleSpelling(_ sender: Any?) {
        editor.isContinuousSpellCheckingEnabled.toggle()
        defaults.set(editor.isContinuousSpellCheckingEnabled, forKey: "spellChecking")
    }

    @objc func toggleGrammar(_ sender: Any?) {
        editor.isGrammarCheckingEnabled.toggle()
        defaults.set(editor.isGrammarCheckingEnabled, forKey: "grammarChecking")
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleSpelling(_:)) {
            menuItem.state = editor.isContinuousSpellCheckingEnabled ? .on : .off
        } else if menuItem.action == #selector(toggleGrammar(_:)) {
            menuItem.state = editor.isGrammarCheckingEnabled ? .on : .off
        } else if menuItem.action == #selector(trashNote(_:)) { return currentURL != nil && !trashInProgress }
        return !trashInProgress
    }

    @objc func trashNote(_ sender: Any?) {
        guard !trashInProgress, flush(), let currentURL else { return }
        trashInProgress = true
        loadTask?.cancel()
        editor.isEditable = false
        NSWorkspace.shared.recycle([currentURL]) { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.trashInProgress = false
                if let error { self.show(error); self.editor.isEditable = true; return }
                self.currentURL = nil
                self.session = nil
                self.editor.string = ""
                self.original = ""
                self.refresh()
            }
        }
    }

    private func show(_ error: Error) { notice = error.localizedDescription; status.stringValue = error.localizedDescription; status.toolTip = notice }
    func windowShouldClose(_ sender: NSWindow) -> Bool { flush() }
}
