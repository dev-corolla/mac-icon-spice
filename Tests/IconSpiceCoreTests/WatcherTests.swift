import Foundation
import Testing
@testable import IconSpiceCore

@MainActor
private final class WatcherCounter { var value = 0 }

@Suite("Application update watcher", .serialized)
@MainActor
struct WatcherTests {
    @Test("Filesystem changes are debounced and stop cancels delivery")
    func debounceAndStop() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("IconSpiceWatcher-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let counter = WatcherCounter()
        let watcher = ApplicationWatcher(roots: [directory]) { counter.value += 1 }
        watcher.start()
        defer { watcher.stop() }
        try Data("first".utf8).write(to: directory.appendingPathComponent("one"))
        try Data("second".utf8).write(to: directory.appendingPathComponent("two"))
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(7))
        while counter.value == 0 && clock.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
        #expect(counter.value == 1)
        watcher.stop()
        try Data("after-stop".utf8).write(to: directory.appendingPathComponent("three"))
        try await Task.sleep(for: .seconds(2.2))
        #expect(counter.value == 1)
    }

    @Test("An absent application root ignores sibling writes and notices creation")
    func missingRootFilter() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("IconSpiceWatcherParent-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let applicationRoot = directory.appendingPathComponent("Applications")
        let counter = WatcherCounter()
        let watcher = ApplicationWatcher(roots: [applicationRoot]) { counter.value += 1 }
        watcher.start()
        defer { watcher.stop() }
        try Data("unrelated".utf8).write(to: directory.appendingPathComponent("mapping.json"))
        try await Task.sleep(for: .seconds(2.5))
        #expect(counter.value == 0)
        try FileManager.default.createDirectory(at: applicationRoot, withIntermediateDirectories: true)
        try Data("changed".utf8).write(to: applicationRoot.appendingPathComponent("new-app"))
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(7))
        while counter.value == 0 && clock.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
        #expect(counter.value == 1)
    }
}
