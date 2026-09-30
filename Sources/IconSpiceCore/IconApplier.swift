import AppKit
import Darwin
import Foundation

/// Uses the public macOS custom-icon API; it does not alter bundled artwork.
@MainActor
public final class IconApplier {
    public init() {}

    public func apply(_ icon: GeneratedIcon, to app: InstalledApp) -> ApplyResult {
        guard let failure = targetFailure(app) else {
            guard let image = NSImage(data: icon.icnsData) ?? NSImage(data: icon.pngData), image.isValid else {
                return .failed(IconError.invalidImage.localizedDescription)
            }
            return set(image, for: app)
        }
        return failure
    }

    public func revert(_ app: InstalledApp, originalCustomIconURL: URL? = nil) -> ApplyResult {
        if let failure = targetFailure(app) { return failure }
        if let originalCustomIconURL {
            do {
                let data = try Data(contentsOf: originalCustomIconURL)
                guard let image = NSImage(data: data), image.isValid else {
                    return .failed("The original custom icon backup is invalid. It has been kept for recovery.")
                }
                return set(image, for: app)
            } catch { return .failed("Could not read the original custom icon backup: \(error.localizedDescription)") }
        }
        return set(nil, for: app)
    }

    /// Finder's big-endian flag field begins at byte 8; 0x0400 is kHasCustomIcon.
    public func hasCustomIcon(at url: URL) -> Bool {
        var finderInfo = [UInt8](repeating: 0, count: 32)
        let count = url.path.withCString { path in
            finderInfo.withUnsafeMutableBytes { bytes in
                getxattr(path, "com.apple.FinderInfo", bytes.baseAddress, bytes.count, 0, 0)
            }
        }
        return count >= 10 && finderInfo[8] & 0x04 != 0
    }

    public func currentIconPNG(for app: InstalledApp) throws -> Data {
        guard FileManager.default.fileExists(atPath: app.url.path) else {
            throw IconError.appNotFound(app.bundleID.rawValue)
        }
        let image = NSWorkspace.shared.icon(forFile: app.url.path)
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw IconError.invalidImage }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024), from: .zero,
                   operation: .copy, fraction: 1, respectFlipped: false,
                   hints: [.interpolation: NSImageInterpolation.high])
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw IconError.invalidImage }
        return data
    }

    public func refreshDock() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["-u", NSUserName(), "Dock"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        // killall returns 1 when Dock is not running, which needs no refresh.
        if process.terminationStatus > 1 {
            throw IconError.fileOperation("Dock refresh failed (exit \(process.terminationStatus)).")
        }
    }

    private func targetFailure(_ app: InstalledApp) -> ApplyResult? {
        if app.isProtected || AppScanner.isProtectedApp(at: app.url) { return .protectedApp }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: app.url.path, isDirectory: &isDirectory),
              isDirectory.boolValue, app.url.pathExtension.lowercased() == "app" else {
            return .failed("The application is no longer present at \(app.url.path).")
        }
        return nil
    }

    private func set(_ image: NSImage?, for app: InstalledApp) -> ApplyResult {
        errno = 0
        let succeeded = NSWorkspace.shared.setIcon(image, forFile: app.url.path, options: [])
        let failureCode = errno
        if succeeded {
            // setIcon's Boolean alone can report success without installing an icon.
            if image != nil && !hasCustomIcon(at: app.url) {
                return .failed("macOS did not install the custom icon. Check App Management access and try again.")
            }
            if image == nil && hasCustomIcon(at: app.url) {
                return .failed("macOS did not remove the custom icon. Check App Management access and try again.")
            }
            return .success
        }
        if failureCode == EACCES || failureCode == EPERM || !FileManager.default.isWritableFile(atPath: app.url.path) {
            return .permissionDenied
        }
        // NSWorkspace exposes no public TCC preflight API or detailed error.
        return .failed("macOS refused the icon change. Check App Management access, then try again.")
    }
}
