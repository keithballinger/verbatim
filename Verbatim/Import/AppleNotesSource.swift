import Foundation
import Carbon

enum AppleNoteContent {
    case text(String)
    case locked
}

protocol AppleNotesReading {
    func identifiers() throws -> [String]
    func read(identifier: String) throws -> AppleNoteContent
}

/// Used exclusively by the CLI. Constructing this object never reads the user's library.
final class AppleNotesSource: AppleNotesReading {
    static let scriptSource = """
    on listIDs()
        tell application id "com.apple.Notes"
            return id of every note
        end tell
    end listIDs

    on readNote(noteID)
        tell application id "com.apple.Notes"
            set sourceNote to note id noteID
            if password protected of sourceNote then return {true, ""}
            return {false, plaintext of sourceNote}
        end tell
    end readNote
    """

    private let script: NSAppleScript
    init() throws {
        guard let script = NSAppleScript(source: Self.scriptSource) else { throw ImportError.script("Could not create Apple Notes reader.") }
        var error: NSDictionary?
        guard script.compileAndReturnError(&error) else {
            throw ImportError.script(error?[NSAppleScript.errorMessage] as? String ?? "Could not compile Apple Notes reader.")
        }
        self.script = script
    }

    func identifiers() throws -> [String] {
        let result = try call("listids", arguments: [])
        guard result.descriptorType == typeAEList else { throw ImportError.script("Notes returned an unexpected note list.") }
        return try (0..<result.numberOfItems).map { index in
            guard let id = result.atIndex(index + 1)?.stringValue else { throw ImportError.script("Notes returned an invalid identifier.") }
            return id
        }
    }

    func read(identifier: String) throws -> AppleNoteContent {
        let result = try call("readnote", arguments: [identifier])
        guard result.numberOfItems == 2, let protected = result.atIndex(1), let content = result.atIndex(2) else {
            throw ImportError.script("Notes returned unexpected note content.")
        }
        if protected.booleanValue { return .locked }
        guard let text = content.stringValue else { throw ImportError.script("Notes did not return plain text.") }
        return .text(text)
    }

    private func call(_ handler: String, arguments: [String]) throws -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kASAppleScriptSuite), eventID: AEEventID(kASSubroutineEvent),
            targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(NSAppleEventDescriptor(string: handler), forKeyword: AEKeyword(keyASSubroutineName))
        let params = NSAppleEventDescriptor.list()
        for (index, value) in arguments.enumerated() { params.insert(NSAppleEventDescriptor(string: value), at: index + 1) }
        event.setParam(params, forKeyword: AEKeyword(keyDirectObject))
        var error: NSDictionary?
        let result = script.executeAppleEvent(event, error: &error)
        if let error {
            let number = error[NSAppleScript.errorNumber] as? Int
            let message = error[NSAppleScript.errorMessage] as? String ?? "Apple Notes automation failed."
            if number == -1743 {
                throw ImportError.script("Apple Notes access was denied. Allow this terminal/tool in System Settings → Privacy & Security → Automation, then retry.")
            }
            throw ImportError.script(message)
        }
        return result
    }
}

enum ImportError: LocalizedError {
    case script(String)
    case arguments(String)
    var errorDescription: String? {
        switch self { case .script(let message), .arguments(let message): return message }
    }
}
