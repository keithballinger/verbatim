import AppKit

final class FolderAccess {
    private(set) var url: URL?
    private var scoped = false
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    deinit { if scoped { url?.stopAccessingSecurityScopedResource() } }

    func restore() throws -> URL? {
        guard let data = defaults.data(forKey: "notesFolderBookmark") else { return nil }
        var stale = false
        let resolved = try URL(resolvingBookmarkData: data, options: [.withSecurityScope], bookmarkDataIsStale: &stale)
        guard resolved.startAccessingSecurityScopedResource() else { throw CocoaError(.fileReadNoPermission) }
        if scoped { url?.stopAccessingSecurityScopedResource() }
        url = resolved
        scoped = true
        if stale { try remember(resolved) }
        return resolved
    }

    @MainActor func choose(for window: NSWindow, completion: @escaping (Result<URL?, Error>) -> Void) {
        let panel = NSOpenPanel()
        panel.title = "Choose Your Verbatim Notes Folder"
        panel.message = "Your notes are ordinary UTF-8 .txt files in this folder. Create a Verbatim folder in Documents, or choose an existing folder."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        panel.directoryURL = url ?? URL(fileURLWithPath: NSHomeDirectoryForUser(NSUserName()) ?? NSHomeDirectory())
            .appendingPathComponent("Documents/Verbatim", isDirectory: true)
        panel.beginSheetModal(for: window) { [self] response in
            guard response == .OK, let selected = panel.url else { completion(.success(nil)); return }
            do {
                try remember(selected)
                if scoped { url?.stopAccessingSecurityScopedResource() }
                url = selected
                scoped = selected.startAccessingSecurityScopedResource()
                completion(.success(selected))
            } catch { completion(.failure(error)) }
        }
    }

    private func remember(_ url: URL) throws {
        defaults.set(try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil,
                                         relativeTo: nil), forKey: "notesFolderBookmark")
    }
}
