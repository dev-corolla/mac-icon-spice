# Upstream inspection and attribution

Icon Spice started as a fresh Swift package. We inspected
[Bengerthelorf/macIconChanger](https://github.com/Bengerthelorf/macIconChanger)
at commit `40ca9f47b94737ed1b3745390fdf2677ca35ccfb` on September 30, 2026.
Its exact MIT notice is retained in [ThirdParty/macIconChanger/LICENSE](../ThirdParty/macIconChanger/LICENSE).
The checked-out research copy is ignored at `.local/upstream`.

The build plan's description of upstream applying icons with one native call was
incomplete. The repository at the inspected commit implements the following:

| Area | Evidence at inspected commit | Icon Spice implementation |
| --- | --- | --- |
| Apply | `IconChanger/Services/IconManager.swift`, `applyIcon` (line 451), encodes a temporary PNG and calls `runHelperTool`; `runHelper` (line 1249) executes a privileged helper with `sudo -n`, with administrator authorization fallback. | A Swift `NSWorkspace.shared.setIcon` call with a decoded multi-resolution ICNS, falling back to PNG. No privileged helper is installed. |
| Underlying native call | `IconChanger/Resources/fileicon`, lines 207–218, uses Cocoa through an AppleScript Objective-C bridge and `NSWorkspace.setIcon`. The script explains that the Boolean may claim success and checks the resource fork afterward. | Native call made directly. Image validation precedes it; the Finder custom-icon flag is checked afterward. |
| Remove | `IconManager.removeIcon` (line 490) calls `runHelperRemove`, which invokes `helper.sh --remove` and `fileicon rm`. It also removes cache/configuration entries. | `setIcon(nil, ...)` restores a default icon. An existing custom icon is backed up before the first apply and restored from that PNG on revert. |
| Permission | `IconManager.swift`, line 2240 onward, dynamically loads private TCC preflight/request APIs. Its helper installation also configures privileged execution. | Public API only. Typed failures distinguish protected paths and observable POSIX permission errors. When Cocoa supplies no detailed error, the UI explains App Management access. There is no private TCC preflight or automatic privilege escalation. |
| Custom-icon detection | `IconManager.hasCustomIcon` (line 1036) reads `com.apple.FinderInfo` and tests bit `0x04` of byte 8. | The small FinderInfo detection routine is adapted to a typed URL API and explicit byte-count check. |
| Update restore | `BackgroundService.swift`, `checkCachedAppsForUpdates` (line 978), compares stored version/timestamps; `restoreUpdatedApps` reuses cached images and batches Dock refresh. Scheduling uses dispatch timers, not FSEvents. | FSEvents on the application roots, debounced after filesystem changes. The shared workflow reloads bundled artwork, regenerates changed algorithmic icons, and reuses saved AI/imported icons. |
| Persistence | `IconCache.swift` and CLI `loadCachedIcons` use per-app cache entries and shared preferences/configuration. | Application Support JSON with independent immutable asset directories, atomic mapping writes, and process-shared `flock` locks. The mapping is committed only after a successful apply. |
| Dock refresh | CLI `refreshDock` (line 316) and GUI Dock refresh code invoke `killall Dock`. | Runs `/usr/bin/killall -u <current user> Dock` directly as a process after a requested batch. |

We adapted the FinderInfo custom-icon detection and the apply/remove/cache/Dock
workflow ideas. The privileged helper, sudoers changes, private TCC interfaces,
remote icon service, and upstream GUI/CLI were not copied. The upstream bundles
Michael Klement's `fileicon` script; Icon Spice does not redistribute that script.

Swift 6 concurrency boundaries use value types and typed results. The mutable
store is an actor. Its JSON lock prevents lost mapping updates, and its separate
nonblocking mutation lease prevents the GUI and CLI from changing icons at the
same time. Callers must hold that lease through capture, preparation, apply,
commit, and any rollback. `IconWorkflow` provides that contract.

This inspection does not establish compatibility with every signed app or macOS
version. The automated native apply/remove test uses only a disposable app in the
temporary directory. App Management permission, signed installed apps, and Tahoe
icon appearance modes still need the manual checks described in the project docs.
