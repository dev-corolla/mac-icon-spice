import AppKit
import CryptoKit
import Foundation

/// Reads the bundle's original artwork, so an applied custom icon never becomes
/// the input of the next generation pass or an update's source hash.
@MainActor
public struct SourceIconLoader {
    public init() {}

    public func load(for app: InstalledApp, allowWorkspaceFallback: Bool = true) throws -> SourceIcon {
        guard let bundle = Bundle(url: app.url) else {
            throw IconError.sourceUnavailable("Could not read the app bundle at \(app.url.path).")
        }

        let iconNames = declaredIconNames(in: bundle)
        for name in iconNames {
            for candidate in resourceCandidates(named: name, bundle: bundle) {
                if let data = try? Data(contentsOf: candidate),
                   let normalized = try? IconImageCodec.normalizePNG(data) {
                    return source(from: normalized)
                }
            }
            // NSBundle also understands images stored in compiled asset catalogs.
            if let image = bundle.image(forResource: NSImage.Name(name)),
               let png = try? rasterize(image) { return source(from: png) }
        }

        if let resources = bundle.resourceURL,
           let urls = try? FileManager.default.contentsOfDirectory(at: resources, includingPropertiesForKeys: nil) {
            let iconFiles = urls.filter { $0.pathExtension.lowercased() == "icns" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            for url in iconFiles {
                if let data = try? Data(contentsOf: url),
                   let png = try? IconImageCodec.normalizePNG(data) { return source(from: png) }
            }
        }

        // Apps without declared resource artwork still get a usable preview.
        // A custom-icon fallback cannot be trusted as the original source.
        let customIcon = app.url.appendingPathComponent("Icon\r")
        guard allowWorkspaceFallback, !FileManager.default.fileExists(atPath: customIcon.path) else {
            throw IconError.sourceUnavailable("\(app.name) has a custom icon but no readable original artwork in its bundle.")
        }
        return source(from: try rasterize(NSWorkspace.shared.icon(forFile: app.url.path)))
    }

    private func declaredIconNames(in bundle: Bundle) -> [String] {
        // Bundle can cache Info.plist for the lifetime of a watcher process.
        // Read it afresh so updates that rename their icon resource are detected.
        let plistURL = bundle.bundleURL.appendingPathComponent("Contents/Info.plist")
        let freshInfo = (try? Data(contentsOf: plistURL)).flatMap {
            (try? PropertyListSerialization.propertyList(from: $0, options: [], format: nil)) as? [String: Any]
        }
        let info = freshInfo ?? bundle.infoDictionary ?? [:]
        var names = [info["CFBundleIconFile"] as? String, info["CFBundleIconName"] as? String].compactMap { $0 }
        if let icons = info["CFBundleIcons"] as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any] {
            if let name = primary["CFBundleIconName"] as? String { names.append(name) }
            if let files = primary["CFBundleIconFiles"] as? [String] { names.append(contentsOf: files) }
        }
        return names.filter { !$0.isEmpty }
    }

    private func resourceCandidates(named name: String, bundle: Bundle) -> [URL] {
        guard let resources = bundle.resourceURL else { return [] }
        let exact = resources.appendingPathComponent(name)
        return (name as NSString).pathExtension.isEmpty
            ? [exact.appendingPathExtension("icns"), exact.appendingPathExtension("png"), exact]
            : [exact]
    }

    private func rasterize(_ image: NSImage) throws -> Data {
        var proposed = CGRect(x: 0, y: 0, width: 1024, height: 1024)
        guard let cgImage = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
            throw IconError.invalidImage
        }
        return try IconImageCodec.pngData(from: IconImageCodec.resized(cgImage, size: 1024))
    }

    private func source(from png: Data) -> SourceIcon {
        // The normalized PNG has fixed dimensions and no input metadata.
        let digest = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
        return SourceIcon(pngData: png, hash: digest)
    }
}
