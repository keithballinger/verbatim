import Foundation
import Darwin

enum AtomicFile {
    static func read(_ url: URL) throws -> String {
        try requireRegularFile(url)
        let data = try Data(contentsOf: url)
        return try decode(data)
    }

    static func decode(_ data: Data) throws -> String {
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        // Foundation consumes a UTF-8 BOM. Retain it in the editing buffer and
        // baseline so opening and editing an existing file preserves its bytes.
        return data.starts(with: [0xef, 0xbb, 0xbf]) ? String(decoding: data, as: UTF8.self) : text
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
            url.withUnsafeFileSystemRepresentation { destination in renamex_np(source!, destination!, UInt32(RENAME_EXCL)) }
        }
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
}
