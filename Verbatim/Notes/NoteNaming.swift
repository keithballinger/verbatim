import Foundation

enum NoteNaming {
    static func title(from text: String) -> String {
        let content = text.hasPrefix("\u{feff}") ? text.dropFirst() : text[...]
        let line = String(content.prefix(while: { !$0.isNewline }))
        // U+FFFC is the placeholder Apple Notes leaves where an attachment was; alone it renders as nothing.
        let blank = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\u{fffc}"))
        return line.trimmingCharacters(in: blank).isEmpty ? "Untitled" : line
    }

    static func stem(for title: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|")
        var result = String(String.UnicodeScalarView(title.unicodeScalars.map {
            forbidden.contains($0) || CharacterSet.controlCharacters.contains($0) ? UnicodeScalar(45)! : $0
        }))
        result = result.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        // Leave room for collision suffixes and .txt under the filesystem's byte limit.
        while result.utf8.count > 180 { result.removeLast() }
        return result.isEmpty ? "Untitled" : result
    }

    static func key(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    static func filename(for title: String, existing: Set<String>) -> String {
        let occupied = Set(existing.map(key))
        let base = stem(for: title)
        var candidate = base + ".txt"
        var suffix = 2
        while occupied.contains(key(candidate)) {
            candidate = "\(base) \(suffix).txt"
            suffix += 1
        }
        return candidate
    }
}
