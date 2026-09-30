import Darwin
import Foundation

/// Serializes icon mutations across the GUI and CLI. Release after commit or rollback.
public final class IconMutationLease: @unchecked Sendable {
    private let lock = NSLock()
    private var descriptor: Int32

    fileprivate init(descriptor: Int32) { self.descriptor = descriptor }

    public func release() {
        lock.lock()
        defer { lock.unlock() }
        if descriptor >= 0 {
            _ = flock(descriptor, LOCK_UN)
            _ = close(descriptor)
            descriptor = -1
        }
    }

    deinit { release() }
}

/// An atomic, process-shared mapping store. Assets are written before the app changes;
/// the mapping becomes visible only after the caller confirms a successful apply.
public actor IconStore {
    public nonisolated let rootURL: URL

    public init(rootURL: URL? = nil) {
        self.rootURL = (rootURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/IconSpice", isDirectory: true))
            .standardizedFileURL.resolvingSymlinksInPath()
    }

    public func acquireMutationLock() throws -> IconMutationLease {
        try ensureDirectory()
        let descriptor = try openLock(named: "mutation.lock")
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            _ = close(descriptor)
            if code == EWOULDBLOCK || code == EAGAIN {
                throw IconError.fileOperation("Another Icon Spice process is changing icons. Try again when it finishes.")
            }
            throw posixError("Could not lock icon changes", code: code)
        }
        return IconMutationLease(descriptor: descriptor)
    }

    public func records() throws -> [IconRecord] {
        try withMappingLock { try loadMapping().values.sorted { $0.appName.localizedStandardCompare($1.appName) == .orderedAscending } }
    }

    public func record(for app: InstalledApp) throws -> IconRecord? {
        try withMappingLock { try loadMapping()[key(for: app.url)] }
    }

    public func prepare(icon: GeneratedIcon, source: SourceIcon, app: InstalledApp,
                        hueOverride: Double?, originalCustomIcon: Data?) throws -> IconRecord {
        try withMappingLock {
            guard icon.sourceHash == source.hash, icon.hue.isFinite, hueOverride?.isFinite != false else {
                throw IconError.invalidArgument("The generated icon and source metadata do not match.")
            }
            let previous = try loadMapping()[key(for: app.url)]
            if let previous, previous.bundleID != app.bundleID {
                throw IconError.fileOperation("The app at this path has a different identity from its restore record. The record has been kept unchanged.")
            }
            if let original = previous?.originalCustomIconURL {
                try validateAssetPath(original)
                guard FileManager.default.fileExists(atPath: original.path) else {
                    throw IconError.fileOperation("The original custom icon backup is missing. Restore that backup before applying another icon.")
                }
            }
            let directory = rootURL.appendingPathComponent("assets/\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            do {
                let generatedURL = directory.appendingPathComponent("generated.icns")
                let sourceURL = directory.appendingPathComponent("source.png")
                try icon.icnsData.write(to: generatedURL, options: .atomic)
                try icon.pngData.write(to: directory.appendingPathComponent("generated.png"), options: .atomic)
                try source.pngData.write(to: sourceURL, options: .atomic)
                let backupURL: URL?
                if let previous {
                    // nil also matters: the app had no custom icon before its first apply.
                    backupURL = previous.originalCustomIconURL
                } else if let originalCustomIcon {
                    let url = directory.appendingPathComponent("original.png")
                    try originalCustomIcon.write(to: url, options: .atomic)
                    backupURL = url
                } else { backupURL = nil }
                return IconRecord(bundleID: app.bundleID, appURL: app.url.standardizedFileURL.resolvingSymlinksInPath(),
                                  appName: app.name, generatedIconURL: generatedURL, sourceIconURL: sourceURL,
                                  originalCustomIconURL: backupURL, sourceHash: source.hash,
                                  hue: icon.hue, hueOverride: hueOverride, generator: icon.kind)
            } catch {
                try? FileManager.default.removeItem(at: directory)
                throw error
            }
        }
    }

    public func commit(_ record: IconRecord) throws {
        try withMappingLock {
            var mapping = try loadMapping()
            let key = key(for: record.appURL)
            let previous = mapping[key]
            if let previous, previous.bundleID != record.bundleID {
                throw IconError.fileOperation("The app at this path has a different identity from its restore record. The record has been kept unchanged.")
            }
            try validateAssets(record)
            let committed: IconRecord
            if let previous {
                // Re-read while locked, retaining the first backup even across processes.
                committed = IconRecord(bundleID: record.bundleID, appURL: record.appURL, appName: record.appName,
                                       generatedIconURL: record.generatedIconURL, sourceIconURL: record.sourceIconURL,
                                       originalCustomIconURL: previous.originalCustomIconURL, sourceHash: record.sourceHash,
                                       hue: record.hue, hueOverride: record.hueOverride,
                                       generator: record.generator, appliedAt: record.appliedAt)
            } else { committed = record }
            mapping[key] = committed
            try writeMapping(mapping)
            if let previous { try? removeUnreferencedDirectory(for: previous, mapping: mapping) }
        }
    }

    /// Convenience for callers that are persisting an already-applied icon.
    public func save(icon: GeneratedIcon, source: SourceIcon, app: InstalledApp,
                     hueOverride: Double?, originalCustomIcon: Data?) throws -> IconRecord {
        let record = try prepare(icon: icon, source: source, app: app,
                                 hueOverride: hueOverride, originalCustomIcon: originalCustomIcon)
        do { try commit(record); return record }
        catch { try? discardPrepared(record); throw error }
    }

    public func discardPrepared(_ record: IconRecord) throws {
        try withMappingLock {
            try removeUnreferencedDirectory(for: record, mapping: loadMapping())
        }
    }

    public func remove(record: IconRecord) throws {
        try withMappingLock {
            var mapping = try loadMapping()
            let key = key(for: record.appURL)
            guard let current = mapping[key] else { return }
            guard current == record else {
                throw IconError.fileOperation("This app's saved icon changed in another process. Reload and try again.")
            }
            mapping.removeValue(forKey: key)
            try writeMapping(mapping)
            try? removeUnreferencedDirectory(for: record, mapping: mapping)
            if let backup = record.originalCustomIconURL {
                try? removeDirectoryIfUnreferenced(backup.deletingLastPathComponent(), mapping: mapping)
            }
        }
    }

    public func source(for record: IconRecord) throws -> SourceIcon {
        try validateAssetPath(record.sourceIconURL)
        return SourceIcon(pngData: try Data(contentsOf: record.sourceIconURL), hash: record.sourceHash)
    }

    public func generated(for record: IconRecord) throws -> GeneratedIcon {
        try validateAssetPath(record.generatedIconURL)
        let pngURL = record.generatedIconURL.deletingLastPathComponent().appendingPathComponent("generated.png")
        try validateAssetPath(pngURL)
        return GeneratedIcon(pngData: try Data(contentsOf: pngURL), icnsData: try Data(contentsOf: record.generatedIconURL),
                             hue: record.hue, sourceHash: record.sourceHash, kind: record.generator)
    }

    private struct Mapping: Codable {
        let schemaVersion: Int
        let records: [String: IconRecord]
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
    }

    private func key(for url: URL) -> String { url.standardizedFileURL.resolvingSymlinksInPath().path }

    private func loadMapping() throws -> [String: IconRecord] {
        let url = rootURL.appendingPathComponent("mapping.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        do {
            let mapping = try JSONDecoder().decode(Mapping.self, from: Data(contentsOf: url))
            guard mapping.schemaVersion == 1 else {
                throw IconError.fileOperation("The icon mapping uses an unsupported format. Its contents have been kept.")
            }
            return mapping.records
        } catch {
            throw IconError.fileOperation("Could not read the icon mapping. Its contents have been kept: \(error.localizedDescription)")
        }
    }

    private func writeMapping(_ records: [String: IconRecord]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Mapping(schemaVersion: 1, records: records))
        try data.write(to: rootURL.appendingPathComponent("mapping.json"), options: .atomic)
    }

    private func openLock(named name: String) throws -> Int32 {
        let descriptor = rootURL.appendingPathComponent(name).path.withCString {
            open($0, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        }
        guard descriptor >= 0 else { throw posixError("Could not open the icon store lock", code: errno) }
        return descriptor
    }

    private func withMappingLock<T>(_ operation: () throws -> T) throws -> T {
        try ensureDirectory()
        let descriptor = try openLock(named: "mapping.lock")
        defer { _ = close(descriptor) }
        while flock(descriptor, LOCK_EX) != 0 {
            if errno == EINTR { continue }
            throw posixError("Could not lock the icon mapping", code: errno)
        }
        defer { _ = flock(descriptor, LOCK_UN) }
        return try operation()
    }

    private func validateAssetPath(_ url: URL) throws {
        let assets = rootURL.appendingPathComponent("assets", isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
        let target = url.standardizedFileURL.resolvingSymlinksInPath()
        guard target.path.hasPrefix(assets.path + "/") else {
            throw IconError.fileOperation("The saved icon path is outside the Icon Spice asset store.")
        }
    }

    private func validateAssets(_ record: IconRecord) throws {
        let previewURL = record.generatedIconURL.deletingLastPathComponent().appendingPathComponent("generated.png")
        for url in [record.generatedIconURL, previewURL, record.sourceIconURL] + [record.originalCustomIconURL].compactMap({ $0 }) {
            try validateAssetPath(url)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw IconError.fileOperation("A saved icon asset is missing: \(url.lastPathComponent).")
            }
        }
    }

    private func removeUnreferencedDirectory(for record: IconRecord, mapping: [String: IconRecord]) throws {
        try removeDirectoryIfUnreferenced(record.generatedIconURL.deletingLastPathComponent(), mapping: mapping)
    }

    private func removeDirectoryIfUnreferenced(_ directory: URL, mapping: [String: IconRecord]) throws {
        try validateAssetPath(directory)
        let resolved = directory.standardizedFileURL.resolvingSymlinksInPath()
        let referenced = mapping.values.contains { record in
            ([record.generatedIconURL, record.sourceIconURL] + [record.originalCustomIconURL].compactMap({ $0 }))
                .contains { $0.standardizedFileURL.resolvingSymlinksInPath().deletingLastPathComponent() == resolved }
        }
        if !referenced && FileManager.default.fileExists(atPath: resolved.path) {
            try FileManager.default.removeItem(at: resolved)
        }
    }

    private func posixError(_ operation: String, code: Int32) -> IconError {
        .fileOperation("\(operation): \(String(cString: strerror(code)))")
    }
}
