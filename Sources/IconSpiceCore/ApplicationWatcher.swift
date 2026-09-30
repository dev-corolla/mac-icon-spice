import CoreServices
import Foundation

/// Watches app roots with a quiet period to let an updater finish replacing bundles.
@MainActor
public final class ApplicationWatcher {
    private let roots: [URL]
    private let onChange: @MainActor @Sendable () -> Void
    private var stream: FSEventStreamRef?
    private var debounceTask: Task<Void, Never>?

    public init(roots: [URL]? = nil, onChange: @escaping @MainActor @Sendable () -> Void) {
        self.roots = roots ?? AppScanner.defaultRoots
        self.onChange = onChange
    }

    public func start() {
        guard stream == nil else { return }
        // Watching the nearest existing parent also notices a later ~/Applications creation.
        let paths = Array(Set(roots.map { root in
            var existing = root.standardizedFileURL
            while !FileManager.default.fileExists(atPath: existing.path), existing.path != "/" {
                existing.deleteLastPathComponent()
            }
            return existing.path
        }))
        guard !paths.isEmpty else { return }
        var context = FSEventStreamContext(version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, pointer, count, paths, flags, _ in
            guard let pointer else { return }
            // Delivery is explicitly scheduled on the main queue below.
            MainActor.assumeIsolated {
                Unmanaged<ApplicationWatcher>.fromOpaque(pointer).takeUnretainedValue()
                    .receiveEvents(count: count, paths: paths, flags: flags)
            }
        }
        guard let created = FSEventStreamCreate(nil, callback, &context, paths as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.5,
                                               FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot))
        else { return }
        FSEventStreamSetDispatchQueue(created, DispatchQueue.main)
        guard FSEventStreamStart(created) else {
            FSEventStreamInvalidate(created)
            FSEventStreamRelease(created)
            return
        }
        stream = created
    }

    public func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }

    private func receiveEvents(count: Int, paths: UnsafeMutableRawPointer,
                               flags: UnsafePointer<FSEventStreamEventFlags>) {
        let eventPaths = paths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
        let forceRescan = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs
            | kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped
            | kFSEventStreamEventFlagEventIdsWrapped | kFSEventStreamEventFlagRootChanged)
        let rootCreation = FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated
            | kFSEventStreamEventFlagItemRenamed)
        let configuredRoots = roots.map { $0.standardizedFileURL.resolvingSymlinksInPath().path }
        for index in 0..<count {
            if flags[index] & forceRescan != 0 { scheduleChange(); return }
            let path = URL(fileURLWithPath: String(cString: eventPaths[index]))
                .standardizedFileURL.resolvingSymlinksInPath().path
            let relevant = configuredRoots.contains { root in
                path == root || path.hasPrefix(root + "/")
                    || (flags[index] & rootCreation != 0 && root.hasPrefix(path + "/")
                        && FileManager.default.fileExists(atPath: root))
            }
            if relevant { scheduleChange(); return }
        }
    }

    private func scheduleChange() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(1.5)) }
            catch { return }
            guard let self, !Task.isCancelled else { return }
            self.onChange()
        }
    }

    isolated deinit {
        debounceTask?.cancel()
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}
