import AppKit
import CoreGraphics
import Foundation
import Darwin

func visibleWindows(for pids: Set<pid_t>) -> [[String: Any]] {
    (CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? [])
    .filter { window in
        guard let pid = window[kCGWindowOwnerPID as String] as? Int32 else { return false }
        return pids.contains(pid)
    }
}
func isLibrary(_ window: [String: Any]) -> Bool {
    let bounds = window[kCGWindowBounds as String] as? [String: NSNumber] ?? [:]
    let width = bounds["Width"]?.doubleValue ?? 0
    let height = bounds["Height"]?.doubleValue ?? 0
    let layer = window[kCGWindowLayer as String] as? Int ?? -1
    return layer == 0 && width >= 700 && height >= 400
}
var applications: [NSRunningApplication] = []
var windows: [[String: Any]] = []
var library: [[String: Any]] = []
let deadline = Date().addingTimeInterval(5)
repeat {
    applications = NSRunningApplication.runningApplications(withBundleIdentifier: "com.lukakorolija.IconSpice")
    windows = visibleWindows(for: Set(applications.map(\.processIdentifier)))
    library = windows.filter(isLibrary)
    if !library.isEmpty { break }
    Thread.sleep(forTimeInterval: 0.1)
} while Date() < deadline
print("Icon Spice processes: \(applications.count), visible library windows: \(library.count)")
let hasDockPresence = applications.contains { $0.activationPolicy == .regular }
print("Dock and application menu enabled: \(hasDockPresence)")
for window in windows {
    let bounds = window[kCGWindowBounds as String] as? [String: NSNumber] ?? [:]
    print("layer=\(window[kCGWindowLayer as String] ?? "?") size=\(bounds["Width"]?.intValue ?? 0)x\(bounds["Height"]?.intValue ?? 0)")
}
if library.isEmpty { print("FAIL: Opening the app did not show its library."); exit(1) }
if !hasDockPresence { print("FAIL: The open library has no Dock presence or application menu."); exit(1) }
print("PASS: The library is visible.")
