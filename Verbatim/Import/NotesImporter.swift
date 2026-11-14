import Foundation

struct ImportReport {
    var imported = 0
    var unchanged = 0
    var locked = 0
    var failed = 0
}

enum NotesImporter {
    static func run(source: AppleNotesReading, folder: URL, progress: (String) -> Void = { _ in }) throws -> ImportReport {
        // Ask Notes for permission before creating anything at the destination.
        let ids = try source.identifiers()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var names = indexedNames(try FileManager.default.contentsOfDirectory(atPath: folder.path))
        var report = ImportReport()
        var seen = Set<String>()
        for (index, id) in ids.enumerated() {
            guard seen.insert(id).inserted else { continue }
            do {
                switch try source.read(identifier: id) {
                case .locked: report.locked += 1
                case .text(let text):
                    if try copy(text, to: folder, names: &names) { report.imported += 1 }
                    else { report.unchanged += 1 }
                }
            } catch {
                report.failed += 1
                progress("Could not import note \(index + 1): \(error.localizedDescription)")
            }
            if (index + 1).isMultiple(of: 100) { progress("Processed \(index + 1) of \(ids.count) notes…") }
        }
        return report
    }

    /// Re-runs skip exact byte matches along the title's collision sequence; no import index is stored.
    private static func indexedNames(_ names: [String]) -> [String: [String]] {
        names.reduce(into: [:]) { result, name in result[NoteNaming.key(name), default: []].append(name) }
    }

    private static func copy(_ text: String, to folder: URL, names: inout [String: [String]]) throws -> Bool {
        let base = NoteNaming.stem(for: NoteNaming.title(from: text))
        var suffix = 1
        while true {
            let name = suffix == 1 ? "\(base).txt" : "\(base) \(suffix).txt"
            let key = NoteNaming.key(name)
            if let actualNames = names[key] {
                for actualName in actualNames {
                    let existing = folder.appendingPathComponent(actualName)
                    if (try? AtomicFile.requireRegularFile(existing)) != nil,
                       (try? Data(contentsOf: existing)) == Data(text.utf8) { return false }
                }
            } else {
                let destination = folder.appendingPathComponent(name)
                do {
                    try AtomicFile.create(text, at: destination)
                    names[key, default: []].append(name)
                    return true
                } catch let error as POSIXError where error.code == .EEXIST {
                    names = indexedNames(try FileManager.default.contentsOfDirectory(atPath: folder.path))
                    continue
                }
            }
            suffix += 1
        }
    }
}
