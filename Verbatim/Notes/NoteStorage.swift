import Foundation

struct NoteSnapshot {
    let url: URL
    let text: String
    var bytes: Data { Data(text.utf8) }
}

struct SaveReceipt {
    let snapshot: NoteSnapshot
    let sequence: Int
    let notice: String?
}

struct DiskState {
    let baseline: NoteSnapshot
    let diskText: String?
    let sequence: Int
}

enum NoteStorage {
    static func load(_ url: URL) throws -> NoteSnapshot {
        NoteSnapshot(url: url, text: try AtomicFile.read(url))
    }

    static func create(text: String, in folder: URL, title: String? = nil) throws -> NoteSnapshot {
        // Retry if another writer wins a filename between enumeration and publication.
        for _ in 0..<20 {
            let names = Set(try FileManager.default.contentsOfDirectory(atPath: folder.path))
            let name = NoteNaming.filename(for: title ?? NoteNaming.title(from: text), existing: names)
            let url = folder.appendingPathComponent(name)
            do { try AtomicFile.create(text, at: url); return NoteSnapshot(url: url, text: text) }
            catch let error as POSIXError where error.code == .EEXIST { continue }
        }
        throw CocoaError(.fileWriteFileExists)
    }

    /// Coordinates with cooperating editors/sync clients. Non-cooperating writers can still race.
    static func save(_ text: String, over baseline: NoteSnapshot, sequence: Int = 0) throws -> SaveReceipt {
        if Data(text.utf8) == baseline.bytes {
            return SaveReceipt(snapshot: baseline, sequence: sequence, notice: nil)
        }
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var result: Result<SaveReceipt, Error>?
        coordinator.coordinate(writingItemAt: baseline.url, options: .forReplacing, error: &coordinationError) { url in
            result = Result {
                let folder = url.deletingLastPathComponent()
                let exists = FileManager.default.fileExists(atPath: url.path)
                if exists { try AtomicFile.requireRegularFile(url) }
                let disk = exists ? try Data(contentsOf: url) : nil
                // Compare bytes, not Swift String equality (which equates Unicode normalization forms).
                guard disk == baseline.bytes else {
                    let copy = try create(text: text, in: folder,
                                          title: "\(NoteNaming.title(from: text)) (conflict)")
                    return SaveReceipt(snapshot: copy, sequence: sequence,
                                       notice: "The disk version changed. Your edits were saved as \(copy.url.lastPathComponent); the other version was left untouched.")
                }
                try AtomicFile.write(text, to: url)
                var savedURL = url
                var notice: String?
                if !NoteNaming.title(from: text).utf8.elementsEqual(NoteNaming.title(from: baseline.text).utf8) {
                    do {
                        var names = Set(try FileManager.default.contentsOfDirectory(atPath: folder.path))
                        names.remove(url.lastPathComponent)
                        let name = NoteNaming.filename(for: NoteNaming.title(from: text), existing: names)
                        let destination = folder.appendingPathComponent(name)
                        if destination != url {
                            // moveItem refuses to overwrite a destination that appeared meanwhile.
                            try FileManager.default.moveItem(at: url, to: destination)
                            savedURL = destination
                        }
                    } catch {
                        // The content is already durable at the old name; do not report it as unsaved.
                        notice = "Text saved, but the filename could not be changed: \(error.localizedDescription)"
                    }
                }
                return SaveReceipt(snapshot: NoteSnapshot(url: savedURL, text: text), sequence: sequence, notice: notice)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileWriteUnknown) }
        return try result.get()
    }
}

/// A session serializes background autosaves and synchronous lifecycle flushes.
final class NoteSession {
    private let queue = DispatchQueue(label: "org.verbatim.save", qos: .userInitiated)
    private var snapshot: NoteSnapshot
    private var sequence = 0
    init(_ snapshot: NoteSnapshot) { self.snapshot = snapshot }

    private func performSave(_ text: String) throws -> SaveReceipt {
        sequence += 1
        let receipt = try NoteStorage.save(text, over: snapshot, sequence: sequence)
        snapshot = receipt.snapshot
        return receipt
    }

    func flush(_ text: String) throws -> SaveReceipt { try queue.sync { try performSave(text) } }

    func save(_ text: String, completion: @escaping (Result<SaveReceipt, Error>) -> Void) {
        queue.async { [self] in
            let result = Result { try performSave(text) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    func inspectDisk(completion: @escaping (Result<DiskState, Error>) -> Void) {
        queue.async { [self] in
            let result = Result {
                let text = FileManager.default.fileExists(atPath: snapshot.url.path) ? try AtomicFile.read(snapshot.url) : nil
                return DiskState(baseline: snapshot, diskText: text, sequence: sequence)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }
}
