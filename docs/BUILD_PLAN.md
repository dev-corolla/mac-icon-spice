# Mac Icon Colorizer — Build Plan

Sep 30, 2026 · @Luka Korolija

## Goal and scope

A native Swift app that recolors every installed app's icon into a consistent, vivid set, and keeps it that way after updates. Existing tools (macIconChanger, macOSicons.com) make you pick an icon per app by hand; ours generates one automatically.

**Decided:** a fresh project that borrows code from macIconChanger (MIT, so we keep its license notice and credit it), shipped as a menu bar app, open source. **Still open:** the minimum macOS version. Proposal: build and test on the current release first, then set the minimum after trying the spike on one older version.

**Added:** optional AI icon generation with the user's own API key (BYOK), built after the core works. The algorithmic generator stays the default.

**In scope for v1**

- Scan installed apps and show current vs. generated icon side by side.
- Generate a colored squircle icon per app from its existing artwork.
- Apply, revert one, revert all.
- Re-apply automatically after an app update wipes the custom icon.

**Out of scope for v1**

- Folder icons and Dock-only tweaks.
- System apps protected by SIP (cannot be changed).
- Distribution through the Mac App Store, since it needs App Management access and writes into other apps' bundles.

## What we borrow from macIconChanger

We reuse its solved plumbing (applying, restoring, permissions) and replace its manual picking with generation. [macIconChanger](https://github.com/Bengerthelorf/macIconChanger) is MIT-licensed Swift/SwiftUI with a GUI, a CLI, macOSicons.com integration and auto-restore, so forking or copying from it is allowed with the license notice kept.

| Area | Plan | Why |
| --- | --- | --- |
| Applying and restoring icons | Borrow | Already handles the fiddly part and edge cases |
| Permission flow (App Management / Full Disk Access) | Borrow | Same requirements for any icon changer |
| Auto-restore after updates | Borrow the idea, rewrite around our mapping store | Ours must re-generate, not just re-apply a picked file |
| CLI | Borrow | Lets us script and test without the UI |
| macOSicons.com integration | Keep as optional source | Fallback when generation looks wrong for an app |
| Per-app manual icon picker | Replace with generate-and-preview | This is the gap we are filling |

First step is to read the repo to choose which pieces to lift into our fresh project. I have not yet opened its source, so the table above is based on its README summary, not its code.

## Architecture

&#91;embedded content: architecture · 5 core modules, 2 entry points\]

The app and the CLI share one core library. Scanner feeds Generator, Generator feeds Applier, Applier records what it did in the store, and Watcher rescans when apps change.

All boundaries are structs and enums that conform to `Sendable`, with no `Any` or stringly-typed values, and the project builds with Swift 6 strict concurrency. Examples: `BundleID` as its own type, `ApplyResult` as an enum of cases, and `IconRecord` as a struct.

## Icon generation pipeline

Each app goes through the same four pure steps, so results are deterministic and easy to unit test.

1. **Load the source icon.** Read the app's icon via `NSWorkspace.icon(forFile:)` and rasterize it at 1024 px.
2. **Pick a color.** Find the dominant hue with Core Image (`CIAreaAverage` or a small k-means over non-transparent pixels). Ignore near-white, near-black and gray pixels so a black-and-white icon still yields a usable accent.
3. **Compose the background.** Draw a squircle (continuous corner radius) filled with a gradient built from that hue, lighter at the top.
4. **Place the glyph.** Composite the original artwork on top, or a tinted or recolored version of it when the source is monochrome. Export as PNG and `.icns`.

The hard case is monochrome icons like the ones in your screenshot: there is no hue to extract. For those the fallback is a stable hash of the bundle ID mapped to a hue, so the same app always gets the same color, plus a manual override in the UI.

The target look is your second screenshot: dark or saturated background, bright glyph, consistent shape and glow. We match its style, not its exact artwork.

**Optional AI generator (bring your own key)**

Both generators conform to one Swift protocol, `IconGenerating`, so the rest of the app cannot tell them apart. The AI version sends the app's source icon plus a fixed style prompt to an image API the user configures.

- **Key handling:** the user pastes their key in Settings; it is stored in the macOS Keychain only, never in the mapping store, logs or the exported icons.
- **Opt-in and preview:** AI runs only when the user starts it, shows which apps' icons will be sent to the provider first, and results are previewed before anything is applied.
- **Caching:** results are cached by bundle ID and source-icon hash, so re-applying after an app update costs nothing and the API is called again only when the app's artwork changes.
- **Consistency:** one pinned style prompt for every app, so the set looks uniform.
- **Failure handling:** rate limits, bad keys and unusable results return typed errors and fall back to the algorithmic icon for that app.

Which image provider to support first is undecided; the protocol keeps others easy to add.

## Apply, persist and re-apply

Applying is one API call; the work is remembering what we applied and noticing when it disappears.

- **Apply:** `NSWorkspace.shared.setIcon(_:forFile:options:)` with the generated image. Revert with `setIcon(nil, ...)`.
- **Mapping store:** a JSON file in Application Support keyed by bundle ID, holding the generated image path, the source icon's hash and the color used. The hash tells us when an app update changed its artwork and the icon needs regenerating, not just re-applying.
- **Watcher:** FSEvents on `/Applications` and `~/Applications`. On change, check whether the custom icon is still present; if not, re-apply from the store.
- **Dock refresh:** restart the Dock after a batch (`killall Dock`) so new icons show up.
- **Permissions:** first-run screen that explains and deep-links to System Settings for the access macOS requires.

Every apply and revert returns a typed result (success, permission denied, protected app, failed with reason), never a bare boolean.

## Milestones

Each step ends with something you can run, so we find problems early. No dates yet; we can size them once you pick a pace.

1. **Read the repo.** Clone macIconChanger, trace how it applies and restores icons, and list the pieces to lift into our fresh project.
2. **Spike the core.** A command-line tool that takes one bundle ID, generates a colored icon and applies it. Proves permissions and the visual result.
3. **Batch and preview.** Scan all apps, generate all icons, and show them in a SwiftUI window opened from the menu bar before anything is applied.
4. **Apply and revert.** Apply selected or all, revert one or all, with typed results and error display.
5. **Persistence.** Mapping store and the FSEvents watcher so icons survive app updates.
6. **AI generator (BYOK).** The `IconGenerating` protocol, a Keychain-backed key screen, one image provider, opt-in with preview, and caching. Comes after Persistence so the core is usable first.
7. **Polish.** Per-app color override, monochrome fallback tuning, first-run permission guide, launch at login.
8. **Package.** Signing and notarization, Homebrew cask, GitHub release.

## Risks and open questions

The biggest risk is that generated icons look worse than hand-made ones, which is a design problem more than a code problem.

| Risk | Fallback |
| --- | --- |
| Generated icons look muddy or off-brand for some apps | Per-app override, plus macOSicons.com as an alternate source |
| macOS Tahoe's Clear/Tinted icon styles override or fight custom icons | Test early in the spike; document which style must be set to Default |
| Custom icons are wiped by app updates or some apps' self-updaters | Watcher plus stored mapping re-applies them |
| Modifying app bundles can upset code signing on some apps | Test on a few signed and App Store apps in the spike |
| Permission prompts confuse first-time users | First-run guide with deep links |

**Questions for you**

- [ ] Fork macIconChanger, or start fresh and borrow code? - borrow code
- [ ] Which macOS versions must this support? idk
- [ ] Menu bar app, regular window app, or both? - menu bar
- [ ] Is this for personal use, or do you plan to release it? - i plan to opensource it
