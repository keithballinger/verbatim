import Foundation
import CoreServices

/// Directory-only DispatchSources miss some in-place writes to child files.
/// FSEvents with file events covers both in-place and atomic replacement saves.
final class FolderWatcher {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "org.verbatim.folder-events", qos: .utility)

    init(folder: URL, onChange: @escaping (Set<String>?) -> Void) throws {
        let handler = EventHandler(onChange)
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(handler).toOpaque(),
            retain: { pointer in
                guard let pointer else { return nil }
                _ = Unmanaged<EventHandler>.fromOpaque(pointer).retain()
                return UnsafeRawPointer(pointer)
            }, release: { pointer in
                if let pointer { Unmanaged<EventHandler>.fromOpaque(pointer).release() }
            }, copyDescription: nil)
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagUseCFTypes)
        guard let stream = FSEventStreamCreate(nil, { _, info, count, paths, flags, _ in
            guard let info else { return }
            let handler = Unmanaged<EventHandler>.fromOpaque(info).takeUnretainedValue()
            let fullScanFlags = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagRootChanged)
            if (0..<count).contains(where: { flags[$0] & fullScanFlags != 0 }) {
                handler.callback(nil)
            } else {
                let names = Unmanaged<NSArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
                handler.callback(Set(names.map { URL(fileURLWithPath: $0).lastPathComponent }))
            }
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
    let callback: (Set<String>?) -> Void
    init(_ callback: @escaping (Set<String>?) -> Void) { self.callback = callback }
}
