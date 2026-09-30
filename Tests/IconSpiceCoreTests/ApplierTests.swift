import AppKit
import Foundation
import Testing
@testable import IconSpiceCore

@Suite("Custom icon application", .serialized)
@MainActor
struct ApplierTests {
    @Test("A disposable app supports apply and removal")
    func temporaryAppRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("IconSpiceApplier-\(UUID().uuidString)")
        let appURL = root.appendingPathComponent("Fixture.app")
        try FileManager.default.createDirectory(at: appURL.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let plist = ["CFBundleIdentifier": "example.iconspice.fixture", "CFBundleName": "Fixture", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: appURL.appendingPathComponent("Contents/Info.plist"))
        let context = try IconImageCodec.bitmapContext(size: 64)
        context.setFillColor(CGColor(red: 0.8, green: 0.2, blue: 0.3, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        let png = try IconImageCodec.pngData(from: #require(context.makeImage()))
        let icon = GeneratedIcon(pngData: png, icnsData: try IconImageCodec.icnsData(fromPNG: png), hue: 0.1, sourceHash: "fixture")
        let app = InstalledApp(bundleID: BundleID("example.iconspice.fixture"), name: "Fixture", url: appURL)
        let applier = IconApplier()
        #expect(!applier.hasCustomIcon(at: appURL))
        #expect(applier.apply(icon, to: app) == .success)
        #expect(applier.hasCustomIcon(at: appURL))
        #expect(!(try applier.currentIconPNG(for: app)).isEmpty)
        #expect(applier.revert(app) == .success)
        #expect(!applier.hasCustomIcon(at: appURL))
    }

    @Test("Protected paths and invalid images are rejected before writing")
    func invalidAndProtectedIcons() throws {
        let applier = IconApplier()
        let invalid = GeneratedIcon(pngData: Data(), icnsData: Data(), hue: 0, sourceHash: "invalid")
        let system = InstalledApp(bundleID: BundleID("com.apple.finder"), name: "Finder",
                                  url: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"), isProtected: false)
        #expect(applier.apply(invalid, to: system) == .protectedApp)
        #expect(applier.revert(system) == .protectedApp)
        let missing = InstalledApp(bundleID: BundleID("example.missing"), name: "Missing",
                                   url: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).app"))
        #expect(!applier.apply(invalid, to: missing).succeeded)
    }
}
