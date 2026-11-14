import Foundation

struct NoteRecord: Equatable {
    let url: URL
    var title: String
    let modified: Date
    let size: Int
}

enum NoteCatalog {
    /// No file contents are read by enumeration. Only immediate, regular .txt files qualify.
    static func list(_ folder: URL) throws -> [NoteRecord] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey]
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys),
                                                           options: [.skipsHiddenFiles]).compactMap { url in
            guard url.pathExtension.lowercased() == "txt" else { return nil }
            let v = try url.resourceValues(forKeys: keys)
            guard v.isRegularFile == true, v.isSymbolicLink != true else { return nil }
            return NoteRecord(url: url, title: url.deletingPathExtension().lastPathComponent,
                              modified: v.contentModificationDate ?? .distantPast, size: v.fileSize ?? 0)
        }.sorted {
            if $0.modified != $1.modified { return $0.modified > $1.modified }
            return $0.url.lastPathComponent < $1.url.lastPathComponent
        }
    }

    static func title(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        while let chunk = try handle.read(upToCount: 4096), !chunk.isEmpty {
            if let end = chunk.firstIndex(where: { $0 == 10 || $0 == 13 }) {
                data.append(chunk[..<end])
                break
            }
            data.append(chunk)
        }
        let line = try AtomicFile.decode(data)
        return NoteNaming.title(from: line)
    }
}

enum SearchMatcher {
    static func matches(_ query: String, title: String, body: String) -> Bool {
        query.isEmpty || title.range(of: query, options: .caseInsensitive) != nil ||
            body.range(of: query, options: .caseInsensitive) != nil
    }
}

actor SearchWorker {
    private let cache = NSCache<NSURL, CachedBody>()
    init() { cache.totalCostLimit = 16 * 1024 * 1024 }
    func invalidate() { cache.removeAllObjects() }

    func titles(_ notes: [NoteRecord]) throws -> [URL: String] {
        var result: [URL: String] = [:]
        for note in notes {
            try Task.checkCancellation()
            if let title = try? NoteCatalog.title(note.url) { result[note.url] = title }
        }
        return result
    }

    func filter(_ notes: [NoteRecord], query: String) throws -> [NoteRecord] {
        var result: [NoteRecord] = []
        for note in notes {
            try Task.checkCancellation()
            if SearchMatcher.matches(query, title: note.title, body: "") { result.append(note); continue }
            let body: String
            if let cached = cache.object(forKey: note.url as NSURL), cached.modified == note.modified, cached.size == note.size {
                body = cached.text
            } else {
                guard let text = try? AtomicFile.read(note.url) else { continue }
                body = text
                cache.setObject(CachedBody(text: text, modified: note.modified, size: note.size),
                                forKey: note.url as NSURL, cost: text.utf8.count)
            }
            if SearchMatcher.matches(query, title: note.title, body: body) { result.append(note) }
        }
        return result
    }
}

private final class CachedBody {
    let text: String
    let modified: Date
    let size: Int
    init(text: String, modified: Date, size: Int) { self.text = text; self.modified = modified; self.size = size }
}
