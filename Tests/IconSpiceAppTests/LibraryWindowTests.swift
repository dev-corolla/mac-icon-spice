import AppKit
import Testing
@testable import IconSpice

@MainActor
@Suite(.serialized)
struct LibraryWindowTests {
    private func makeController() -> LibraryWindowController {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        return LibraryWindowController(contentView: NSView(), frameAutosaveName: nil)
    }

    private func waitUntil(_ condition: () -> Bool) async throws -> Bool {
        for _ in 0..<100 {
            if condition() { return true }
            try await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    @Test func showPresentsLibrary() throws {
        let controller = makeController()
        let window = try #require(controller.window)
        defer { window.close() }

        controller.showLibrary()

        #expect(window.isVisible)
        #expect(window.title == "Icon Spice")
        #expect(NSApp.activationPolicy() == .regular)
    }

    @Test func closingAndReopeningReusesLibrary() throws {
        let controller = makeController()
        let window = try #require(controller.window)
        defer { window.close() }
        controller.showLibrary()

        window.performClose(nil)
        #expect(!window.isVisible)
        #expect(controller.window === window)
        #expect(NSApp.activationPolicy() == .accessory)

        controller.showLibrary()

        #expect(window.isVisible)
        #expect(controller.window === window)
        #expect(NSApp.activationPolicy() == .regular)
    }

    @Test func reopeningRestoresMinimizedLibrary() async throws {
        let controller = makeController()
        let window = try #require(controller.window)
        defer { window.close() }
        window.animationBehavior = .none
        controller.showLibrary()

        window.miniaturize(nil)
        let minimized = try await waitUntil { window.isMiniaturized }
        try #require(minimized, "The library must finish minimizing before testing restoration")
        #expect(NSApp.activationPolicy() == .regular)

        controller.showLibrary()

        let restored = try await waitUntil { !window.isMiniaturized && window.isVisible }
        #expect(restored, "Showing the library must restore its minimized window")
        #expect(NSApp.activationPolicy() == .regular)
    }

    @Test func closingLastWindowKeepsMenuBarAppRunning() {
        #expect(!AppDelegate().applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
    }
}
