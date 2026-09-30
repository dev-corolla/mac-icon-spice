import AppKit
import Testing
@testable import IconSpice

@MainActor
@Suite(.serialized)
struct ApplicationMenuTests {
    @Test func fallbackHasFunctionalQuitAndTextEditingCommands() throws {
        let application = NSApplication.shared
        let previousMenu = application.mainMenu
        defer { application.mainMenu = previousMenu }
        application.mainMenu = nil
        let installer = ApplicationMenu(settingsAction: {})

        installer.install(in: application)

        let mainMenu = try #require(application.mainMenu)
        let appMenu = try #require(mainMenu.items.first?.submenu)
        let quit = try #require(appMenu.item(withTitle: "Quit Icon Spice"))
        #expect(quit.action == #selector(NSApplication.terminate(_:)))
        #expect(quit.target === application)
        #expect(quit.keyEquivalent == "q")
        #expect(quit.keyEquivalentModifierMask == [.command])
        #expect(quit.isEnabled && !quit.isHidden)

        let edit = try #require(mainMenu.item(withTitle: "Edit")?.submenu)
        for (title, action, key) in [
            ("Cut", #selector(NSText.cut(_:)), "x"),
            ("Copy", #selector(NSText.copy(_:)), "c"),
            ("Paste", #selector(NSText.paste(_:)), "v"),
            ("Select All", #selector(NSText.selectAll(_:)), "a"),
        ] {
            let item = try #require(edit.item(withTitle: title))
            #expect(item.action == action)
            #expect(item.target == nil, "Editing commands must use the current responder")
            #expect(item.keyEquivalent == key)
            #expect(item.keyEquivalentModifierMask == [.command])
        }
    }

    @Test func settingsMenuRunsSuppliedAction() throws {
        let application = NSApplication.shared
        let previousMenu = application.mainMenu
        defer { application.mainMenu = previousMenu }
        application.mainMenu = NSMenu(title: "Empty")
        var settingsOpened = false
        let installer = ApplicationMenu { settingsOpened = true }
        installer.install(in: application)
        let appMenu = try #require(application.mainMenu?.items.first?.submenu)
        let settings = try #require(appMenu.item(withTitle: "Settings…"))
        let action = try #require(settings.action)

        let dispatched = application.sendAction(action, to: settings.target, from: settings)

        #expect(dispatched)
        #expect(settingsOpened)
        #expect(settings.keyEquivalent == ",")
        #expect(settings.keyEquivalentModifierMask == [.command])
    }

    @Test func existingMenusAndCommandsSurviveRepeatedInstallation() throws {
        let application = NSApplication.shared
        let previousMenu = application.mainMenu
        defer { application.mainMenu = previousMenu }
        let mainMenu = NSMenu(title: "Existing Main Menu")
        let appMenu = NSMenu(title: "Icon Spice")
        let appItem = NSMenuItem(title: "Icon Spice", action: nil, keyEquivalent: "")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        let customCommand = NSMenuItem(title: "Existing Settings", action: nil, keyEquivalent: ",")
        appMenu.addItem(customCommand)
        let quit = NSMenuItem(title: "Quit Icon Spice", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenu.addItem(quit)
        let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        fileItem.submenu = NSMenu(title: "File")
        mainMenu.addItem(fileItem)
        application.mainMenu = mainMenu
        let installer = ApplicationMenu(settingsAction: {})

        installer.install(in: application)
        installer.install(in: application)

        #expect(application.mainMenu === mainMenu)
        #expect(mainMenu.items.count == 2)
        #expect(mainMenu.items[0] === appItem)
        #expect(mainMenu.items[1] === fileItem)
        #expect(appMenu.items.count == 2)
        #expect(appMenu.items[0] === customCommand)
        #expect(appMenu.items[1] === quit)
        #expect(quit.target === application)
    }

    @Test func existingNonApplicationMenusGetQuitWithoutBeingReplaced() throws {
        let application = NSApplication.shared
        let previousMenu = application.mainMenu
        defer { application.mainMenu = previousMenu }
        let mainMenu = NSMenu(title: "Existing Main Menu")
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = NSMenu(title: "Existing Edit")
        mainMenu.addItem(editItem)
        application.mainMenu = mainMenu
        let installer = ApplicationMenu(settingsAction: {})

        installer.install(in: application)

        #expect(application.mainMenu === mainMenu)
        #expect(mainMenu.items.count == 2)
        #expect(mainMenu.items[1] === editItem)
        let appMenu = try #require(mainMenu.items[0].submenu)
        let quit = try #require(appMenu.item(withTitle: "Quit Icon Spice"))
        #expect(quit.target === application)
        #expect(quit.action == #selector(NSApplication.terminate(_:)))
    }
}
