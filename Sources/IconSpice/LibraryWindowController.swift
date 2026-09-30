import AppKit

@MainActor
final class LibraryWindowController: NSWindowController, NSWindowDelegate {
    init(contentView: NSView, frameAutosaveName: String? = "IconSpiceLibraryWindow") {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Icon Spice"
        window.identifier = NSUserInterfaceItemIdentifier("library")
        window.contentMinSize = NSSize(width: 840, height: 560)
        window.isReleasedWhenClosed = false
        window.contentView = contentView
        if let frameAutosaveName {
            if !window.setFrameUsingName(frameAutosaveName) { window.center() }
            window.setFrameAutosaveName(frameAutosaveName)
        } else {
            window.center()
        }
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { return nil }

    func showLibrary() {
        guard let window else { return }
        NSApp.setActivationPolicy(.regular)
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
