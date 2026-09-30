import AppKit
import Foundation
import Testing
@testable import IconSpiceCore

@MainActor
private final class WorkflowFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("IconSpiceWorkflow-\(UUID().uuidString)")
    var appURL: URL { root.appendingPathComponent("Fixture.app") }
    let app: InstalledApp
    let store: IconStore

    init() throws {
        app = InstalledApp(bundleID: BundleID("example.workflow.fixture"), name: "Fixture",
                           url: root.appendingPathComponent("Fixture.app"))
        store = IconStore(rootURL: root.appendingPathComponent("store"))
        try FileManager.default.createDirectory(at: appURL.appendingPathComponent("Contents/Resources"), withIntermediateDirectories: true)
        try writeIdentity(app.bundleID.rawValue)
        let context = try IconImageCodec.bitmapContext(size: 64)
        context.setFillColor(CGColor(red: 0.1, green: 0.7, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        let png = try IconImageCodec.pngData(from: #require(context.makeImage()))
        try IconImageCodec.icnsData(fromPNG: png).write(to: appURL.appendingPathComponent("Contents/Resources/AppIcon.icns"))
    }

    func writeIdentity(_ identifier: String, iconName: String = "AppIcon") throws {
        let plist = ["CFBundleIdentifier": identifier, "CFBundleName": "Fixture",
                     "CFBundlePackageType": "APPL", "CFBundleIconFile": iconName]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: appURL.appendingPathComponent("Contents/Info.plist"), options: .atomic)
    }

    func replaceBundledArtwork() throws {
        let context = try IconImageCodec.bitmapContext(size: 64)
        context.setFillColor(CGColor(red: 0.95, green: 0.2, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        let png = try IconImageCodec.pngData(from: #require(context.makeImage()))
        try IconImageCodec.icnsData(fromPNG: png)
            .write(to: appURL.appendingPathComponent("Contents/Resources/UpdatedIcon.icns"), options: .atomic)
        try writeIdentity(app.bundleID.rawValue, iconName: "UpdatedIcon")
    }

    isolated deinit { try? FileManager.default.removeItem(at: root) }
}

@Suite("Shared icon workflow", .serialized)
@MainActor
struct WorkflowTests {
    @Test("Apply, regenerate, and revert retain the default baseline without resurrecting it")
    func applyRevertAndReapply() async throws {
        let fixture = try WorkflowFixture()
        let workflow = IconWorkflow(store: fixture.store)
        let applier = IconApplier()
        let (source, icon) = try await workflow.generate(for: fixture.app)
        #expect(await workflow.apply(icon, source: source, to: fixture.app) == .success)
        #expect(applier.hasCustomIcon(at: fixture.appURL))
        #expect(try await fixture.store.records().count == 1)
        let next = try await workflow.generate(for: fixture.app, hueOverride: 0.8)
        #expect(next.0.hash == source.hash)
        #expect(await workflow.apply(next.1, source: next.0, to: fixture.app, hueOverride: 0.8) == .success)
        #expect(try await fixture.store.record(for: fixture.app)?.originalCustomIconURL == nil)
        #expect(await workflow.revert(fixture.app) == .success)
        #expect(!applier.hasCustomIcon(at: fixture.appURL))
        #expect(await workflow.reapplyTracked().isEmpty)
        #expect(try await fixture.store.records().isEmpty)
    }

    @Test("The first existing custom icon remains the restore point")
    func preservesExistingCustomIcon() async throws {
        let fixture = try WorkflowFixture()
        let workflow = IconWorkflow(store: fixture.store)
        let applier = IconApplier()
        let original = try await workflow.generate(for: fixture.app, hueOverride: 0.3)
        #expect(applier.apply(original.1, to: fixture.app) == .success)
        let originalPNG = try applier.currentIconPNG(for: fixture.app)
        let generated = try await workflow.generate(for: fixture.app, hueOverride: 0.8)
        #expect(await workflow.apply(generated.1, source: generated.0, to: fixture.app) == .success)
        let first = try #require(await fixture.store.record(for: fixture.app))
        let backup = try #require(first.originalCustomIconURL)
        #expect(try Data(contentsOf: backup) == originalPNG)
        #expect(await workflow.apply(original.1, source: original.0, to: fixture.app) == .success)
        #expect(try await fixture.store.record(for: fixture.app)?.originalCustomIconURL == backup)
        #expect(await workflow.revert(fixture.app) == .success)
        #expect(applier.hasCustomIcon(at: fixture.appURL))
        #expect(try await fixture.store.records().isEmpty)
    }

    @Test("Updates reapply cached artwork, regenerate changed resources, and preserve the first custom backup")
    func updateRecovery() async throws {
        let fixture = try WorkflowFixture()
        let workflow = IconWorkflow(store: fixture.store)
        let applier = IconApplier()
        let baseline = try await workflow.generate(for: fixture.app, hueOverride: 0.2)
        #expect(applier.apply(baseline.1, to: fixture.app) == .success)
        let baselinePNG = try applier.currentIconPNG(for: fixture.app)
        let initial = try await workflow.generate(for: fixture.app, hueOverride: 0.8)
        #expect(await workflow.apply(initial.1, source: initial.0, to: fixture.app, hueOverride: 0.8) == .success)
        let firstRecord = try #require(await fixture.store.record(for: fixture.app))
        let originalBackup = try #require(firstRecord.originalCustomIconURL)
        #expect(try Data(contentsOf: originalBackup) == baselinePNG)

        // An updater can replace the bundle while leaving the original artwork unchanged.
        #expect(applier.revert(fixture.app) == .success)
        #expect(!applier.hasCustomIcon(at: fixture.appURL))
        let reapplied = await workflow.reapplyTracked()
        #expect(reapplied.count == 1)
        #expect(reapplied.first?.action == .reapplied)
        #expect(reapplied.first?.result == .success)
        #expect(applier.hasCustomIcon(at: fixture.appURL))
        let cachedRecord = try #require(await fixture.store.record(for: fixture.app))
        #expect(cachedRecord.sourceHash == firstRecord.sourceHash)
        #expect(cachedRecord.originalCustomIconURL == originalBackup)
        #expect(try await fixture.store.generated(for: cachedRecord).pngData == initial.1.pngData)

        // Changing both the resource and declaration catches stale NSBundle metadata.
        try fixture.replaceBundledArtwork()
        let regenerated = await workflow.reapplyTracked()
        #expect(regenerated.count == 1)
        #expect(regenerated.first?.action == .regenerated)
        #expect(regenerated.first?.result == .success)
        let updatedRecord = try #require(await fixture.store.record(for: fixture.app))
        #expect(updatedRecord.sourceHash != firstRecord.sourceHash)
        #expect(updatedRecord.sourceHash == (try await workflow.source(for: fixture.app)).hash)
        #expect(updatedRecord.hueOverride == 0.8)
        #expect(updatedRecord.originalCustomIconURL == originalBackup)
        #expect(try Data(contentsOf: originalBackup) == baselinePNG)
        #expect(try await fixture.store.generated(for: updatedRecord).pngData != initial.1.pngData)
        #expect(applier.hasCustomIcon(at: fixture.appURL))
        #expect(await workflow.revert(fixture.app) == .success)
        #expect(applier.hasCustomIcon(at: fixture.appURL))
        #expect(try await fixture.store.records().isEmpty)
    }

    @Test("A refused apply discards staged files and creates no mapping")
    func applyFailureDoesNotPersist() async throws {
        let fixture = try WorkflowFixture()
        let workflow = IconWorkflow(store: fixture.store)
        let source = try await workflow.source(for: fixture.app)
        let invalid = GeneratedIcon(pngData: Data(), icnsData: Data(), hue: 0.4, sourceHash: source.hash)
        #expect(!(await workflow.apply(invalid, source: source, to: fixture.app)).succeeded)
        #expect(try await fixture.store.records().isEmpty)
        let assets = fixture.store.rootURL.appendingPathComponent("assets")
        #expect(try FileManager.default.contentsOfDirectory(atPath: assets.path).isEmpty)
        #expect(!IconApplier().hasCustomIcon(at: fixture.appURL))
    }

    @Test("A changed bundle identity refuses restoration and keeps the original record")
    func changedIdentity() async throws {
        let fixture = try WorkflowFixture()
        let workflow = IconWorkflow(store: fixture.store)
        let (source, icon) = try await workflow.generate(for: fixture.app)
        #expect(await workflow.apply(icon, source: source, to: fixture.app) == .success)
        let record = try #require(await fixture.store.record(for: fixture.app))
        try fixture.writeIdentity("example.other.app")
        #expect(!(await workflow.revert(fixture.app)).succeeded)
        let replacement = try #require(AppScanner().readApp(at: fixture.appURL))
        await #expect(throws: IconError.self) { try await workflow.source(for: replacement) }
        #expect(!(await workflow.apply(icon, source: source, to: replacement)).succeeded)
        #expect(try await fixture.store.record(for: fixture.app) == record)
        let reapply = await workflow.reapplyTracked()
        #expect(reapply.count == 1)
        #expect(reapply.first?.result.succeeded == false)
    }

    @Test("Protected applications are rejected without creating a restore record")
    func protectedTarget() async throws {
        let fixture = try WorkflowFixture()
        let workflow = IconWorkflow(store: fixture.store)
        let app = InstalledApp(bundleID: BundleID("com.apple.finder"), name: "Finder",
                               url: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))
        let invalid = GeneratedIcon(pngData: Data(), icnsData: Data(), hue: 0, sourceHash: "protected")
        #expect(await workflow.apply(invalid, source: SourceIcon(pngData: Data(), hash: "protected"), to: app) == .protectedApp)
        #expect(try await fixture.store.records().isEmpty)
    }
}
