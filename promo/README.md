# Icon Spice launch video

A 32-second, caption-led presentation, designed to work with sound off in the X feed. Both compositions run at 30 fps: **LaunchSquare** (1080 × 1080) and **LaunchWide** (1920 × 1080). The warm paper, ink, purple, and peach palette keeps the presentation clean while the icons carry the color.

```sh
cd promo
npm ci
npm run dev
npm run lint
npm run render:square
npm run render:wide
npm run poster
```

Outputs go into ignored `out/`. MP4 exports use H.264 and yuv420p. The project pins its Remotion version in the lockfile.

## Story

| Time    | Scene                                                    |
| ------- | -------------------------------------------------------- |
| 0–5 s   | Original “grayscale graveyard” tweet and monochrome Dock |
| 5–9 s   | Icon Spice reveal with animated icons                    |
| 9–15 s  | Original artwork beside actual local previews            |
| 15–21 s | Native library, preview, apply, and restore              |
| 21–27 s | Optional AI prompt customization                         |
| 27–32 s | Open-source early build and repository URL               |

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

The AI scene illustrates the prompt field; it does not claim a live AI-generated result. The library screenshot shows real UI. App names and artwork belong to their respective owners. The presentation source is MIT; Remotion dependencies retain their own licenses.

See [launch copy](../docs/LAUNCH.md) for the quote-post text.
