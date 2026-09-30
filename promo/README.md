# Icon Spice launch video

A 15-second, caption-led presentation, designed to work with sound off in the X feed. Both compositions run at 30 fps: **LaunchSquare** (1080 × 1080) and **LaunchWide** (1920 × 1080). The pepper app icon and warm paper, ink, purple, and peach palette keep the presentation clean while the icons carry the color.

```sh
cd promo
npm ci
npm run dev
npm run lint
npm run render:square
npm run render:wide
npm run poster
```

Outputs go into ignored `out/`. MP4 exports use H.264 with 4:2:0 chroma. The project pins its Remotion version in the lockfile.

## Story

| Time    | Scene                                                    |
| ------- | -------------------------------------------------------- |
| 0–3 s   | Original “grayscale graveyard” tweet and monochrome Dock |
| 3–8 s   | Original artwork beside actual local previews            |
| 8–12 s  | Native library, preview, apply, and restore              |
| 12–15 s | Pepper icon, open-source early build, and repository URL |

The original 32-second story remains available as `LaunchFullSquare` and `LaunchFullWide`, including the app reveal and optional AI prompt scene. The default render scripts export `icon-spice-launch-square-15s.mp4` and `icon-spice-launch-wide-15s.mp4`.

## Assets

The reference screenshot was supplied by the tweet’s author. The opening crops only the original post, from https://x.com/corolladev/status/2104495438959145176. Grok’s artwork further down that screenshot is not shown as Icon Spice output.

`public/icons/` contains original bundled artwork and genuine previews exported by `IconSpiceCore` from installed apps. To refresh them on a Mac with the six demo apps installed:

```sh
./scripts/export-promo-assets.sh
```

Run that command from the repository root. It only reads app artwork and writes PNGs; it does not apply icons, call AI, or change settings. To refresh the read-only native library screenshot:

```sh
./scripts/render-preview.sh promo/public/library.png
```

The full-length video’s AI scene illustrates the prompt field; it does not claim a live AI-generated result. The library screenshot shows real UI. App names and artwork belong to their respective owners. The presentation source is MIT; Remotion dependencies retain their own licenses.

The app icon is vector artwork in `Sources/IconSpice/PepperArtwork.swift`, also used for the sidebar and monochrome menu-bar template. After building the app, refresh the presentation’s icon with:

```sh
sips -s format png "dist/Icon Spice.app/Contents/Resources/AppIcon.icns" --out promo/public/app-icon.png
```

See [launch copy](../docs/LAUNCH.md) for the quote-post text.
