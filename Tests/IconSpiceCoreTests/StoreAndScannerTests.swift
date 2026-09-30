import Foundation
import Testing
@testable import IconSpiceCore

private final class TemporaryDirectory: @unchecked Sendable {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("IconSpiceTests-\(UUID().uuidString)", isDirectory: true)
    init() throws { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
    deinit { try? FileManager.default.removeItem(at: url) }
}

private func makeApp(in directory: URL, name: String, identifier: String = "example.fixture") throws -> URL {
    let app = directory.appendingPathComponent("\(name).app", isDirectory: true)
    try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
    let plist: [String: String] = ["CFBundleIdentifier": identifier, "CFBundleDisplayName": name,
                                  "CFBundleVersion": "123", "CFBundleShortVersionString": "1.2.3", "CFBundlePackageType": "APPL"]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        .write(to: app.appendingPathComponent("Contents/Info.plist"))
    return app
}

private func savedIcon(hash: String = "source", hue: Double = 0.2) -> GeneratedIcon {
    GeneratedIcon(pngData: Data("png-\(hue)".utf8), icnsData: Data("icns-\(hue)".utf8), hue: hue, sourceHash: hash)
}

@Suite("Scanner and persistence")
struct StoreAndScannerTests {
    @Test("Scan skips embedded apps and retains separate installs of one bundle ID")
    func scannerSkipsHelpersAndKeepsDuplicateIDs() throws {
        let temporary = try TemporaryDirectory()
        let outer = try makeApp(in: temporary.url, name: "Zulu")
        _ = try makeApp(in: outer.appendingPathComponent("Contents/Helpers"), name: "Hidden", identifier: "example.helper")
        _ = try makeApp(in: temporary.url.appendingPathComponent("Utilities"), name: "Alpha")
        let invalid = temporary.url.appendingPathComponent("Broken.app")
        try FileManager.default.createDirectory(at: invalid, withIntermediateDirectories: true)
        let scanner = AppScanner()
        let apps = scanner.scan(roots: [temporary.url, temporary.url])
        #expect(apps.map(\.name) == ["Alpha", "Zulu"])
        #expect(apps.count == 2)
        #expect(apps.allSatisfy { $0.bundleID == BundleID("example.fixture") && $0.version == "1.2.3" && !$0.isProtected })
    }

    @Test("System protection follows symlinks and allows the writable Data volume")
    func protectedPaths() throws {
        let temporary = try TemporaryDirectory()
        let link = temporary.url.appendingPathComponent("Alias.app")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        #expect(AppScanner.isProtectedApp(at: link))
        #expect(AppScanner.isProtectedApp(at: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")))
        #expect(!AppScanner.isProtectedApp(at: URL(fileURLWithPath: "/System/Volumes/Data/Applications/Example.app")))
        #expect(!AppScanner.isProtectedApp(at: URL(fileURLWithPath: "/usr/local/Example.app")))
    }

    @Test("Prepare keeps the mapping unchanged, commit preserves the earliest custom backup")
    func prepareCommitAndOriginalBackup() async throws {
        let temporary = try TemporaryDirectory()
        let store = IconStore(rootURL: temporary.url)
        let app = InstalledApp(bundleID: BundleID("example.app"), name: "Example", url: URL(fileURLWithPath: "/Applications/Example.app"))
        let source = SourceIcon(pngData: Data("source-png".utf8), hash: "source")
        let original = Data("original-custom".utf8)
        let first = try await store.prepare(icon: savedIcon(), source: source, app: app, hueOverride: nil, originalCustomIcon: original)
        #expect(try await store.records().isEmpty)
        #expect(FileManager.default.fileExists(atPath: first.generatedIconURL.path))
        try await store.commit(first)
        let second = try await store.prepare(icon: savedIcon(hue: 0.7), source: source, app: app, hueOverride: 0.7, originalCustomIcon: Data("newer-custom".utf8))
        try await store.commit(second)
        let reloaded = IconStore(rootURL: temporary.url)
        let record = try #require(await reloaded.record(for: app))
        #expect(record.hue == 0.7)
        #expect(record.originalCustomIconURL == first.originalCustomIconURL)
        #expect(try Data(contentsOf: #require(record.originalCustomIconURL)) == original)
        #expect(try await reloaded.source(for: record).pngData == source.pngData)
        #expect(try await reloaded.generated(for: record).icnsData == savedIcon(hue: 0.7).icnsData)
        try await reloaded.remove(record: record)
        #expect(try await reloaded.records().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: first.generatedIconURL.deletingLastPathComponent().path))
        #expect(!FileManager.default.fileExists(atPath: second.generatedIconURL.deletingLastPathComponent().path))
    }

    @Test("An original default icon stays the baseline after repeated applies")
    func nilBackupStaysNil() async throws {
        let temporary = try TemporaryDirectory()
        let store = IconStore(rootURL: temporary.url)
        let app = InstalledApp(bundleID: BundleID("example.default"), name: "Default", url: URL(fileURLWithPath: "/Applications/Default.app"))
        let source = SourceIcon(pngData: Data("source".utf8), hash: "source")
        _ = try await store.save(icon: savedIcon(), source: source, app: app, hueOverride: nil, originalCustomIcon: nil)
        let next = try await store.prepare(icon: savedIcon(hue: 0.3), source: source, app: app, hueOverride: nil,
                                          originalCustomIcon: Data("our-applied-icon".utf8))
        try await store.commit(next)
        #expect(try await store.record(for: app)?.originalCustomIconURL == nil)
    }

    @Test("A missing original backup prevents staging another apply")
    func missingBackupPreflight() async throws {
        let temporary = try TemporaryDirectory()
        let store = IconStore(rootURL: temporary.url)
        let app = InstalledApp(bundleID: BundleID("example.backup"), name: "Backup", url: URL(fileURLWithPath: "/Applications/Backup.app"))
        let source = SourceIcon(pngData: Data("source".utf8), hash: "source")
        let record = try await store.save(icon: savedIcon(), source: source, app: app, hueOverride: nil,
                                         originalCustomIcon: Data("custom".utf8))
        try FileManager.default.removeItem(at: #require(record.originalCustomIconURL))
        await #expect(throws: IconError.self) {
            try await store.prepare(icon: savedIcon(hue: 0.6), source: source, app: app, hueOverride: nil, originalCustomIcon: nil)
        }
        #expect(try await store.record(for: app) == record)
        #expect(try FileManager.default.contentsOfDirectory(atPath: temporary.url.appendingPathComponent("assets").path).count == 1)
    }

    @Test("A replacement bundle ID cannot inherit the old path's restore record")
    func changedIdentityCannotPrepareOrCommit() async throws {
        let temporary = try TemporaryDirectory()
        let store = IconStore(rootURL: temporary.url)
        let app = InstalledApp(bundleID: BundleID("example.original"), name: "Original", url: URL(fileURLWithPath: "/Applications/Shared.app"))
        let source = SourceIcon(pngData: Data("source".utf8), hash: "source")
        let record = try await store.save(icon: savedIcon(), source: source, app: app, hueOverride: nil,
                                         originalCustomIcon: Data("original-custom".utf8))
        let replacement = InstalledApp(bundleID: BundleID("example.replacement"), name: "Replacement", url: app.url)
        await #expect(throws: IconError.self) {
            try await store.prepare(icon: savedIcon(hue: 0.6), source: source, app: replacement, hueOverride: nil,
                                    originalCustomIcon: Data("replacement-custom".utf8))
        }
        let mismatched = IconRecord(bundleID: replacement.bundleID, appURL: app.url, appName: replacement.name,
                                    generatedIconURL: record.generatedIconURL, sourceIconURL: record.sourceIconURL,
                                    originalCustomIconURL: record.originalCustomIconURL, sourceHash: record.sourceHash,
                                    hue: record.hue, hueOverride: record.hueOverride, generator: record.generator)
        await #expect(throws: IconError.self) { try await store.commit(mismatched) }
        #expect(try await store.record(for: app) == record)
        #expect(try FileManager.default.contentsOfDirectory(atPath: temporary.url.appendingPathComponent("assets").path).count == 1)
    }

    @Test("Discard only removes unused staged assets")
    func discardPreparedAssets() async throws {
        let temporary = try TemporaryDirectory()
        let store = IconStore(rootURL: temporary.url)
        let app = InstalledApp(bundleID: BundleID("example.stage"), name: "Stage", url: URL(fileURLWithPath: "/Applications/Stage.app"))
        let source = SourceIcon(pngData: Data("source".utf8), hash: "source")
        let first = try await store.save(icon: savedIcon(), source: source, app: app, hueOverride: nil,
                                        originalCustomIcon: Data("first-backup".utf8))
        let stage = try await store.prepare(icon: savedIcon(hue: 0.8), source: source, app: app, hueOverride: nil, originalCustomIcon: nil)
        try await store.discardPrepared(stage)
        #expect(!FileManager.default.fileExists(atPath: stage.generatedIconURL.path))
        let originalURL = try #require(first.originalCustomIconURL)
        #expect(FileManager.default.fileExists(atPath: originalURL.path))
        try await store.discardPrepared(first)
        #expect(FileManager.default.fileExists(atPath: first.generatedIconURL.path))
        #expect(try await store.record(for: app) == first)
    }

    @Test("Separate store instances do not lose each other's map updates")
    func concurrentStoreInstances() async throws {
        let temporary = try TemporaryDirectory()
        let source = SourceIcon(pngData: Data("source".utf8), hash: "source")
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<16 {
                group.addTask {
                    let store = IconStore(rootURL: temporary.url)
                    let app = InstalledApp(bundleID: BundleID("example.concurrent.\(index)"), name: "App \(index)",
                                           url: URL(fileURLWithPath: "/Applications/App \(index).app"))
                    _ = try await store.save(icon: savedIcon(), source: source, app: app, hueOverride: nil, originalCustomIcon: nil)
                }
            }
            try await group.waitForAll()
        }
        #expect(try await IconStore(rootURL: temporary.url).records().count == 16)
    }

    @Test("Mutation locks prevent simultaneous apply and release idempotently")
    func mutationLock() async throws {
        let temporary = try TemporaryDirectory()
        let first = IconStore(rootURL: temporary.url)
        let second = IconStore(rootURL: temporary.url)
        let lease = try await first.acquireMutationLock()
        await #expect(throws: IconError.self) { try await second.acquireMutationLock() }
        lease.release()
        lease.release()
        let next = try await second.acquireMutationLock()
        next.release()
    }

    @Test("A corrupt mapping remains intact and is never replaced with an empty store")
    func corruptMappingIsPreserved() async throws {
        let temporary = try TemporaryDirectory()
        let corrupt = Data("{broken mapping".utf8)
        let mappingURL = temporary.url.appendingPathComponent("mapping.json")
        try corrupt.write(to: mappingURL)
        let store = IconStore(rootURL: temporary.url)
        await #expect(throws: IconError.self) { try await store.records() }
        #expect(try Data(contentsOf: mappingURL) == corrupt)
    }
}
