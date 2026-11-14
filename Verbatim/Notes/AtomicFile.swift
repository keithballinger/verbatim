import Foundation
import Darwin

enum AtomicFile {
    static func read(_ url: URL) throws -> String {
        try requireRegularFile(url)
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return text
    }

    static func write(_ text: String, to url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw CocoaError(.fileWriteInvalidFileName) }
        }
        try Data(text.utf8).write(to: url, options: .atomic)
    }

    static func requireRegularFile(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
    }

    /// Publish a fully written new file without ever replacing another file.
    static func create(_ text: String, at url: URL) throws {
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".verbatim-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try Data(text.utf8).write(to: temporary, options: .withoutOverwriting)
        let handle = try FileHandle(forWritingTo: temporary)
        try handle.synchronize()
        try handle.close()
        let result = temporary.withUnsafeFileSystemRepresentation { source in
            url.withUnsafeFileSystemRepresentation { destination in link(source!, destination!) }
        }
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
}
