# Contributing

Lodge is a native macOS app: Swift and SwiftUI, macOS 14 or later, Swift 5. The Xcode project has no third-party dependencies. `Lodge/` and `LodgeTests/` are folder-synced groups, so a `.swift` file you add there is part of the target.

Issues and pull requests are welcome. Bug reports and feature requests have templates. Please read the [user guide](docs/user-guide.md) before filing something the app already does. Security issues go through [SECURITY.md](SECURITY.md), not a public issue.

## Build and test

Open `Lodge.xcodeproj` and press Command-R. The project is set to Sign to Run Locally (ad-hoc signing, no development team). It is not sandboxed and the hardened runtime is off, so a local build can read `/Volumes` and write to a folder you pick.

From the command line:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Lodge.xcodeproj -scheme Lodge -configuration Debug \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Lodge.xcodeproj -scheme Lodge \
  -derivedDataPath build/DerivedData test
```

The first time the app reads a card, macOS asks for removable-volume access. Closing the window quits the app.

`LegacyMigration.swift` runs once on launch and copies the previous app’s Application Support files and settings into Lodge’s. It copies them. It does not move or change the originals. Anything Lodge already has is kept.

## Demo mode

Debug builds can show sample data without touching the real settings or the ledger. Formatting cannot run in demo mode.

```sh
open -n build/DerivedData/Build/Products/Debug/Lodge.app --args \
  -LodgeDemo YES -LodgeDemoState ready -LodgeDemoAppearance dark
```

| Flag | Values |
| --- | --- |
| `-LodgeDemoState` | `empty`, `ready`, `running`, `finished` |
| `-LodgeDemoAppearance` | `light`, `dark` |
| `-LodgeDemoSettingsTab` | `general`, `appearance`, `presets`, `destinations`, `naming`, `files`, `cameras` |
| `-LodgeDemoTheme` | `default`, `aurora`, `ocean`, `twilight`, `ember`, `forest` |
| `-LodgeDemoLayout` | `grid` (and `-LodgeDemoListThumbnails YES` for list thumbnails) |
| `-LodgeDemoScope` | `skipped`, `offloaded` |
| `-LodgeDemoQuickLook` | a sample file name, such as `C0008.MP4` |
| `-LodgeDemoWindowSize` | `1060x700`, centred on the sharpest screen |
| `-LodgeDemoShowFormatAlert` | `YES` |
| `-LodgeDemoPlainTheme` | `YES`, the solid colours used with Increase Contrast |
| `-LodgeDemoQuickDump` | `YES` |
| `-LodgeDemoFolderTemplate` | a folder template, such as `{project}_{date}/{camera}/{type}` |
| `-LodgeDemoExpandTree` | `YES` to open every folder, or `files` to open the file lists too |

Demo windows are drawn as if they were active, so a screenshot taken with the app in the background still shows the accent on switches and segments. The sample card has Sony XML sidecars, RAW photos, WAVs, two short clips, a few missing copies, and a few cameras. Thumbnails are drawn placeholders. Views also have `#Preview`s for the Xcode canvas. Screenshots checked into the repo live in `Design/screenshots/`, and the ones used on the site are copied to `docs/assets/screenshots/`.

## Icon and design files

The icon on the website and in the README is `docs/assets/app-icon/` (`icon_16x16.png` through `icon_1024.png`, plus `Contents.json`). The icon the built app uses is `Lodge/Assets.xcassets/AppIcon.appiconset`. Those are separate.

What lives under `Design/`, including earlier icon drafts and the steps for replacing the in-app set, is in [Design/README.md](Design/README.md). The small sizes are drawn for the menu bar and Finder. Generate a real set rather than scaling one PNG.

## Themes

Palettes live in `Theme.swift`. Each theme is tuned separately for Light and Dark, and button text stays readable. `LodgeTests/ThemeTests.swift` checks that every theme defines its tokens. The asset catalog’s `AccentColor` is system blue. AppKit uses it when the system accent is Multicolor, and as the fallback outside SwiftUI. A saved theme named Comet or Graphite opens as Default. With Increase Contrast or Reduce Transparency, every theme uses solid colours.

## Code map

| File | What it holds |
| --- | --- |
| `LodgeApp.swift` | App entry, main window, Settings scene, first-launch migration |
| `AppModel.swift` | Settings, cameras, destinations, presets, the card watcher, the ledger, eject, format, the finish sound |
| `Theme.swift` | Default and the colour themes, the window wash, solid fallbacks |
| `ContentView.swift` | Card, Media, Destination, toolbar |
| `FunnelComponents.swift` | Stage panel, step badge, arrows, count pills |
| `Motion.swift` | Drawn checkmark, count-up numbers, hover lift, card glow pieces, drop haptics, the progress shimmer |
| `CardStageView.swift` | Card column, the insert glow |
| `ClipsStageView.swift` | Media column: counts, project, camera, list or grid, re-offload, short clips, quick dump |
| `MediaGridViews.swift` | Grid tiles, status badges, the progress ring |
| `MediaPreview.swift` | Selection, Quick Look, sidecar folding |
| `Thumbnails.swift` | Quick Look thumbnails |
| `DestinationStageView.swift` | Favorites, free space, folder drops |
| `FolderTreeView.swift` | The Layout tree, drag-and-drop levels, side-by-side tokens |
| `FolderTree.swift` | The planned folders, and the folders already on disk |
| `InlineLevel.swift` | Tokens placed side by side in one folder level |
| `FormatViews.swift` | Format confirmation, the Ready to format badge |
| `OffloadBar.swift` | Offload button, progress, completion |
| `RecentOffloadsView.swift` | Recent Offloads |
| `SettingsView.swift` | Settings window and the General tab |
| `NamingSettingsView.swift` | Naming tab, the Examples menu, token chips |
| `CamerasSettingsView.swift` | Cameras tab |
| `DestinationsSettingsView.swift` | Destinations tab |
| `NamingTemplate.swift` | Tokens, validation, Examples, rendering |
| `FileRules.swift` | Proxy and sidecar extensions, the ignore list |
| `QuickDump.swift` | Removes `{project}` from the templates |
| `OffloadPreset.swift` | Saved setups |
| `PresetViews.swift` | Preset menu at the top right of the window, Settings > Presets and Files, the short-clip slider |
| `OffloadPlanner.swift` | Final paths, sequence numbers, sidecar matching |
| `MediaCategory.swift` | Video, photo, audio, other |
| `CameraStore.swift` | Cameras and per-card memory |
| `DestinationStore.swift` | Favorites |
| `CardFormatter.swift` | Ready-to-format checks and `diskutil eraseVolume` |
| `FlowLogic.swift` | Why Offload is disabled, sizes, the card line, the finish sound rule |
| `DemoData.swift` | Sample data for previews and demo mode |
| `OffloadSession.swift` | One card’s offload |
| `VolumeWatcher.swift` | Cards inserted and removed |
| `ClipScanner.swift` | Files on a card, system junk |
| `Renamer.swift` | Project-name cleanup and dates |
| `Copier.swift` | Copy, SHA-256, the `.lodge-partial` file |
| `Ledger.swift` | The JSON record of verified copies |
| `LegacyMigration.swift` | First launch: copy the previous app’s data and settings |
| `CardInventory.swift` | New, offloaded, missing, ignored |
| `ReoffloadAlert.swift` | Re-offload everything, and forget history |
| `ShortClips.swift` | The short-clip rule |
| `Settings.swift` | Preferences |

## Docs

User-facing pages live in `README.md` and `docs/`. The site is `docs/index.html`, ready for GitHub Pages from the `/docs` folder on `main`. `docs/.nojekyll` keeps Pages from running Jekyll.

The README hero is a `<picture>` pointing at `docs/assets/lodge-header-dark.png` and `docs/assets/lodge-header-light.png` (1600×500). The art already includes the Lodge wordmark and “Home base for your media.”, so the README does not repeat that line under the picture. The landing page uses the dark banner, then the headline “From card to calm.” Open Graph uses `docs/assets/lodge-social-preview.png` (1280×640); `lodge-social-preview-light.png` is the light companion. The site icon is `docs/assets/app-icon/`. `docs/assets/favicon.ico`, `favicon.png`, and `apple-touch-icon.png` are resized from `icon_1024.png`. Replace those files in place when a new set arrives. The short description in the README intro and the page meta is “Lodge gets your footage off camera cards safely, checked and neatly named.”

## License

MIT. See [LICENSE](LICENSE). By contributing, you agree that your contributions are licensed the same way.
