import AppKit
import Foundation

/// Finds application bundles without descending into an app's embedded helpers.
public struct AppScanner: Sendable {
    public init() {}

    public static var defaultRoots: [URL] {
        [URL(fileURLWithPath: "/Applications", isDirectory: true),
         FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
         URL(fileURLWithPath: "/System/Applications", isDirectory: true)]
    }

    public func scan(roots: [URL]? = nil) -> [InstalledApp] {
        let manager = FileManager.default
        var apps: [String: InstalledApp] = [:]
        for root in roots ?? Self.defaultRoots {
            if root.pathExtension.lowercased() == "app" {
                if let app = readApp(at: root) { apps[app.id] = app }
                continue
            }
            guard let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                                       options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in enumerator {
                guard url.pathExtension.lowercased() == "app" else { continue }
                enumerator.skipDescendants()
                if let app = readApp(at: url) { apps[app.id] = app }
            }
        }
        return apps.values.sorted {
            let comparison = $0.name.localizedStandardCompare($1.name)
            return comparison == .orderedSame ? $0.url.path < $1.url.path : comparison == .orderedAscending
        }
    }

    @MainActor
    public func resolve(bundleID: BundleID) throws -> InstalledApp {
        if let app = scan().first(where: { $0.bundleID == bundleID }) { return app }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID.rawValue),
           let app = readApp(at: url), app.bundleID == bundleID { return app }
        throw IconError.appNotFound(bundleID.rawValue)
    }

    /// Checks the actual target, so a symlink cannot bypass the system-app guard.
    public static func isProtectedApp(at url: URL) -> Bool {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        func beneath(_ prefix: String) -> Bool { path == prefix || path.hasPrefix(prefix + "/") }
        // The writable Data volume lives beneath /System/Volumes on modern macOS.
        if beneath("/System/Volumes/Data") { return beneath("/System/Volumes/Data/System") }
        if beneath("/System") || beneath("/bin") || beneath("/sbin") { return true }
        return beneath("/usr") && !beneath("/usr/local")
    }

    public func readApp(at url: URL) -> InstalledApp? {
        let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
        guard canonical.pathExtension.lowercased() == "app",
              let data = try? Data(contentsOf: canonical.appendingPathComponent("Contents/Info.plist")),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let identifier = plist["CFBundleIdentifier"] as? String, !identifier.isEmpty else { return nil }
        let name = (plist["CFBundleDisplayName"] as? String) ?? (plist["CFBundleName"] as? String)
            ?? canonical.deletingPathExtension().lastPathComponent
        let version = (plist["CFBundleShortVersionString"] as? String) ?? (plist["CFBundleVersion"] as? String) ?? ""
        return InstalledApp(bundleID: BundleID(identifier), name: name, url: canonical,
                            version: version, isProtected: Self.isProtectedApp(at: canonical))
    }
}
