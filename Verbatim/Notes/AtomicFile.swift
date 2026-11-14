import Foundation

enum AtomicFile {
    static func read(_ url: URL) throws -> String {
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
}
