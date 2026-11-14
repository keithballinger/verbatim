import Foundation

enum LaunchMeasurement {
    private static var reported = false
    static func editorReady() {
        guard !reported, ProcessInfo.processInfo.arguments.contains("--measure-launch") else { return }
        reported = true
        fputs("VERBATIM_EDITOR_READY\n", stderr)
        fflush(stderr)
    }
}
