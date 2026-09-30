// Native, read-only UI preview for visual review. No icon changes or AI requests.
import AppKit
import SwiftUI

@MainActor
final class PreviewRenderer: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            let model = AppModel()
            await model.scan()
            let names = ["ChatGPT", "Cursor", "Figma", "Slack", "Spotify", "Firefox", "Obsidian", "iTerm"]
            let sample = model.entries.filter { names.contains($0.app.name) && !$0.app.isProtected }
            model.entries = sample.isEmpty ? Array(model.entries.filter { !$0.app.isProtected }.prefix(9)) : sample
            model.generatePreviews()
            while model.isBusy { try? await Task.sleep(for: .milliseconds(100)) }
            model.selected = Set(model.entries.prefix(3).map(\.id))
            let host = NSHostingView(rootView: LibraryView(model: model))
            host.frame = NSRect(x: 0, y: 0, width: 1120, height: 760)
            let window = NSWindow(contentRect: host.frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.contentView = host
            window.title = "Icon Spice — read-only preview"
            window.center()
            self.window = window
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            try? await Task.sleep(for: .milliseconds(700))
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                fputs("Could not capture the native preview.\n", stderr)
                NSApp.terminate(nil)
                return
            }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let destination = URL(fileURLWithPath: CommandLine.arguments[1])
            do {
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try bitmap.representation(using: .png, properties: [:])!.write(to: destination)
                print("Rendered \(model.entries.count) app previews to \(destination.path)")
            } catch { print(error.localizedDescription) }
            NSApp.terminate(nil)
        }
    }
}

@main
struct RenderPreview {
    @MainActor static func main() {
        guard CommandLine.arguments.count == 2 else { print("Usage: render-preview OUTPUT.png"); return }
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let renderer = PreviewRenderer()
        application.delegate = renderer
        application.run()
        withExtendedLifetime(renderer) { }
    }
}
