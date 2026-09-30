import AppKit

/// Supplies the application menu for our AppKit library window when SwiftUI has
/// only created a menu bar extra. Existing SwiftUI commands stay in place.
@MainActor
final class ApplicationMenu: NSObject {
    private let settingsAction: @MainActor () -> Void

    init(settingsAction: @escaping @MainActor () -> Void) {
        self.settingsAction = settingsAction
        super.init()
    }

    func install(in application: NSApplication = .shared) {
        let mainMenu = application.mainMenu ?? NSMenu(title: "Main Menu")
        let needsFallback = mainMenu.items.isEmpty
        let applicationMenu = findApplicationMenu(in: mainMenu) ?? makeApplicationMenu(in: mainMenu, application: application)

        ensureQuit(in: applicationMenu, application: application)
        if needsFallback { addEditMenu(to: mainMenu) }
        if application.mainMenu !== mainMenu { application.mainMenu = mainMenu }
    }

    private func findApplicationMenu(in mainMenu: NSMenu) -> NSMenu? {
        let appActions = [
            #selector(NSApplication.terminate(_:)),
            #selector(NSApplication.hide(_:)),
            #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
        ]
        return mainMenu.items.compactMap(\.submenu).first { menu in
            menu.title == "Icon Spice" || menu.items.contains { item in
                item.action.map { appActions.contains($0) } == true
            }
        }
    }

    private func makeApplicationMenu(in mainMenu: NSMenu, application: NSApplication) -> NSMenu {
        let menu = NSMenu(title: "Icon Spice")
        let item = NSMenuItem(title: "Icon Spice", action: nil, keyEquivalent: "")
        item.submenu = menu
        mainMenu.insertItem(item, at: 0)

        add("About Icon Spice", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), target: application, to: menu)
        menu.addItem(.separator())
        add("Settings…", action: #selector(showSettings(_:)), target: self, key: ",", to: menu)
        menu.addItem(.separator())
        add("Hide Icon Spice", action: #selector(NSApplication.hide(_:)), target: application, key: "h", to: menu)
        add("Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), target: application,
            key: "h", modifiers: [.command, .option], to: menu)
        add("Show All", action: #selector(NSApplication.unhideAllApplications(_:)), target: application, to: menu)
        return menu
    }

    private func ensureQuit(in menu: NSMenu, application: NSApplication) {
        let action = #selector(NSApplication.terminate(_:))
        let item: NSMenuItem
        if let existing = menu.items.first(where: { $0.action == action || ($0.title == "Quit Icon Spice" && $0.keyEquivalent == "q") }) {
            item = existing
        } else {
            if !menu.items.isEmpty && menu.items.last?.isSeparatorItem == false { menu.addItem(.separator()) }
            item = NSMenuItem(title: "Quit Icon Spice", action: action, keyEquivalent: "q")
            menu.addItem(item)
        }
        item.action = action
        item.target = application
        item.keyEquivalent = "q"
        item.keyEquivalentModifierMask = [.command]
        item.isHidden = false
        item.isEnabled = true
    }

    private func addEditMenu(to mainMenu: NSMenu) {
        let menu = NSMenu(title: "Edit")
        let item = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        item.submenu = menu
        mainMenu.addItem(item)
        add("Cut", action: #selector(NSText.cut(_:)), key: "x", to: menu)
        add("Copy", action: #selector(NSText.copy(_:)), key: "c", to: menu)
        add("Paste", action: #selector(NSText.paste(_:)), key: "v", to: menu)
        add("Select All", action: #selector(NSText.selectAll(_:)), key: "a", to: menu)
    }

    private func add(_ title: String, action: Selector, target: AnyObject? = nil, key: String = "",
                     modifiers: NSEvent.ModifierFlags = [.command], to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target
        item.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        menu.addItem(item)
    }

    @objc private func showSettings(_ sender: Any?) { settingsAction() }
}
