import AppKit
import MachO

let usage = """
Usage:
  verbatim                         Open Verbatim
  verbatim --import-notes [--folder PATH]
  verbatim --help

Copy accessible Apple Notes as UTF-8 .txt files. Originals are never modified.
Default destination: ~/Documents/Verbatim. Notes folders are flattened;
password-protected notes are skipped. Attachments and formatting are not exported.
macOS will request permission to automate Notes when you first import.
"""

func main() throws -> Int32 {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments == ["--help"] || arguments == ["-h"] { print(usage); return 0 }
    if arguments.isEmpty {
        var length: UInt32 = 0
        _NSGetExecutablePath(nil, &length)
        var path = [CChar](repeating: 0, count: Int(length))
        guard _NSGetExecutablePath(&path, &length) == 0 else { throw ImportError.arguments("Could not locate the Verbatim executable.") }
        let executable = URL(fileURLWithPath: String(cString: path)).resolvingSymlinksInPath()
        let directory = executable.deletingLastPathComponent()
        let appURL = directory.lastPathComponent == "Helpers"
            ? directory.deletingLastPathComponent().deletingLastPathComponent()
            : directory.appendingPathComponent("Verbatim.app")
        guard NSWorkspace.shared.open(appURL) else { throw ImportError.arguments("Could not open \(appURL.path). Build Verbatim.app first.") }
        return 0
    }
    guard arguments.first == "--import-notes" else { throw ImportError.arguments(usage) }
    let destination: URL
    if arguments.count == 1 {
        destination = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Verbatim", isDirectory: true)
    } else if arguments.count == 3, arguments[1] == "--folder", !arguments[2].isEmpty {
        destination = URL(fileURLWithPath: (arguments[2] as NSString).expandingTildeInPath, isDirectory: true).standardizedFileURL
    } else { throw ImportError.arguments(usage) }
    print("Importing Apple Notes to \(destination.path)…")
    let report = try NotesImporter.run(source: AppleNotesSource(), folder: destination) { fputs($0 + "\n", stderr) }
    print("Imported: \(report.imported); already present: \(report.unchanged); locked: \(report.locked); failed: \(report.failed).")
    return report.failed == 0 ? 0 : 1
}

do { exit(try main()) }
catch {
    fputs("verbatim: \(error.localizedDescription)\n", stderr)
    exit(1)
}
