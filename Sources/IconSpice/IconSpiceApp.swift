import AppKit
import CoreServices
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private lazy var applicationMenu = ApplicationMenu { [weak self] in
        self?.showLibrary()
        AppModel.shared.showingSettings = true
    }
    private lazy var libraryWindowController = LibraryWindowController(
        contentView: NSHostingView(rootView: LibraryView(model: .shared))
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        let launchedAtLogin = NSAppleEventManager.shared().currentAppleEvent?
            .paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        NSApp.setActivationPolicy(.accessory)
        if !launchedAtLogin { showLibrary() }
        Task { await AppModel.shared.start() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showLibrary()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDidBecomeActive(_ notification: Notification) {
        applicationMenu.install()
    }

    func showLibrary() {
        applicationMenu.install()
        libraryWindowController.showLibrary()
    }
}

@main
struct IconSpiceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            SpiceMenu(model: model, openLibrary: delegate.showLibrary)
        } label: {
            Image(nsImage: PepperArtwork.menuIcon)
                .accessibilityLabel("Icon Spice")
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .undoRedo) {
                Button("Revert last applied batch") { model.undoLastApply() }
                    .keyboardShortcut("z").disabled(!model.canUndo)
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { delegate.showLibrary(); model.showingSettings = true }
                    .keyboardShortcut(",")
            }
        }
    }
}

private struct SpiceMenu: View {
    @Bindable var model: AppModel
    let openLibrary: () -> Void
    var body: some View {
        Button("Open Icon Spice") { openLibrary() }
            .keyboardShortcut("o")
        Text("\(model.trackedCount) icons spiced")
        if model.isBusy { Text(model.progressText) }
        Divider()
        Toggle("Keep icons after updates", isOn: $model.autoRestore)
        Button("Rescan apps") { openLibrary(); Task { await model.scan() } }
            .disabled(model.isBusy)
        Button("Refresh Dock") { model.refreshDock() }.disabled(model.isBusy)
        Divider()
        Button("Settings…") { openLibrary(); model.showingSettings = true }
        Button("Quit Icon Spice") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
