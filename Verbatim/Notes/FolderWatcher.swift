import Foundation
import CoreServices

/// Directory-only DispatchSources miss some in-place writes to child files.
/// FSEvents with file events covers both in-place and atomic replacement saves.
final class FolderWatcher {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "org.verbatim.folder-events", qos: .utility)

    init(folder: URL, onChange: @escaping () -> Void) throws {
        let handler = EventHandler(onChange)
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(handler).toOpaque(),
            retain: { pointer in
                guard let pointer else { return nil }
                _ = Unmanaged<EventHandler>.fromOpaque(pointer).retain()
                return UnsafeRawPointer(pointer)
            }, release: { pointer in
                if let pointer { Unmanaged<EventHandler>.fromOpaque(pointer).release() }
            }, copyDescription: nil)
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot)
        guard let stream = FSEventStreamCreate(nil, { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<EventHandler>.fromOpaque(info).takeUnretainedValue().callback()
        }, &context, [folder.path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.2, flags) else {
            throw CocoaError(.fileReadUnknown)
        }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
            throw CocoaError(.fileReadUnknown)
        }
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}

private final class EventHandler {
    let callback: () -> Void
    init(_ callback: @escaping () -> Void) { self.callback = callback }
}
