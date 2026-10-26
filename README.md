# SnapDrop

A small native macOS app (SwiftUI) that offloads camera SD cards — video, photos, audio
and sidecar files — safely, verified, and named the way you want.

![SnapDrop ready to offload a card](Design/screenshots/ready-light.png)

## What it does

1. **Notices when you insert a card.** Any removable drive mounted under `/Volumes`
   that has media on it (cards already inserted at launch count too).
2. **Finds everything worth keeping** anywhere on the card: video, photos, audio and
   other files such as Sony's `C0001M01.XML` metadata (see [File types](#file-types)).
   System junk is never copied.
3. **Names files from a template** you set in Settings → Naming, e.g.
   `{project}/{date}/{camera}` + `{date}_{project}_{camera}_{seq}`. You fill in the
   project, shoot and camera in the main window; a live preview shows exactly what every
   file will be called before anything is copied, and the copy uses exactly those names.
4. **Copies only new files**, with the default layout:

   ```
   Destination/
     2026-10-25/
       BeachShoot/
         2026-10-25_BeachShoot_0001.mp4
         2026-10-25_BeachShoot_0001M01.xml    ← sidecar keeps its clip's name
         2026-10-25_BeachShoot_0002.arw
   ```

   - The date is the file's creation date (or modification date if there's none).
   - Numbers continue after the highest one already in that folder, so a second card
     from the same shoot picks up where the first left off. Nothing is ever overwritten.
   - Extensions are lowercased.
5. **Verifies every copy** with SHA-256. Each file is first copied to
   `<name>.snapdrop-partial`, the copy is re-read from disk and hashed, and only when it
   matches the source is it renamed to its final name. A mismatch deletes the partial
   file and is reported as a failure.
6. **Remembers what it copied** in a ledger at
   `~/Library/Application Support/SnapDrop/ledger.json`, so inserting the same card
   again only copies files that are new. A file is identified by the card's volume UUID
   (or name) + its path on the card + size + modification time.

SnapDrop **never changes or deletes anything on the card.**

## The window

The main window reads left to right, like a funnel:

**① Card → ② Media → ③ Destination**, with the offload bar along the bottom.

- **Card** — the inserted cards. Pick one if more than one is mounted.
- **Media** — chips like *18 video · 9 photo · 3 audio · 19 other* and how many files
  were already offloaded; the **Project**, **Shoot** and **Camera** fields (only the ones
  your template uses are required); and the live name preview, with an
  *All / Video / Photo / Audio / Other* filter. Sidecars are shown indented under their clip.
- **Destination** — the folder, its free space, and the folder layout files will land in.
- **Offload bar** — the big **Offload N Files** button. When it's disabled it tells you
  why ("Enter a project name", "Choose a camera", "Not enough space…"). While copying it
  shows the current file, *X of N*, bytes copied, time left and a *Verifying* state, plus
  **Cancel**; the preview highlights the file being copied and ticks off each verified
  one. When it's done: **Show in Finder**, **Eject Card** and **Done**, and a "Glass"
  sound plays if everything copied and verified.

When you insert a card SnapDrop fills in the funnel and brings its window to the front —
no pop-up sheet. The clock button in the toolbar shows **Recent Offloads**.
Animations follow System Settings → Accessibility → Display → **Reduce motion**.

| Ready | Copying | Finished (Dark Mode) |
| --- | --- | --- |
| ![](Design/screenshots/ready-light.png) | ![](Design/screenshots/running-light.png) | ![](Design/screenshots/finished-dark.png) |

## Settings (⌘,)

**General** — destination folder; which [file types](#file-types) to offload (all on by
default); *Eject card after offload* (off by default, and only when every file copied and
verified); *Play a sound when an offload finishes* (on by default).

**Naming** — a folder template and a file template, presets, and a live example.
Click a token chip to insert it where you were typing. Mistakes (an unclosed `{`, an
unknown token, `{seq}` twice, a name starting with `.`) are explained right under the field
and the Offload button stays off until they're fixed. **Reset to Default** brings back
`{date}/{shoot}` + `{date}_{shoot}_{seq}`.

| Token | Becomes |
| --- | --- |
| `{project}` | Project name from the main window (recent projects are one click away) |
| `{shoot}` | Shoot name ("Beach Shoot" → `BeachShoot`) |
| `{camera}` | The chosen camera's short code, or its name if it has no code |
| `{date}` | Capture date, `2026-10-25` |
| `{year}` `{month}` `{day}` | `2026`, `10`, `25` |
| `{time}` | Capture time, `143005` |
| `{type}` | `Video`, `Photo`, `Audio` or `Other` |
| `{card}` | The card's volume name |
| `{original}` | The original file name without extension, `C0001` |
| `{seq}` | Sequence number, `0001`; `{seq:3}` gives `001` |
| `{ext}` | File extension, `mp4` (the real extension is always added at the end) |

Use `/` in the folder template for subfolders. Presets: *Date / Shoot* (default),
*Project / Date / Camera*, *Project / Type / Date*, *Year / Month / Day*,
*Date / Shoot, Original Names*, and *Flat*. Without `{seq}` or `{original}`, files that
would end up with the same name get `_2`, `_3`… instead of overwriting.

**Cameras** — your list of cameras, each with a name ("Sony FX3") and an optional short
code ("A") used by `{camera}`. Add, rename, reorder (drag) and delete. In the main window
pick one from the **Camera** menu; SnapDrop remembers which camera you used with each card
and picks it again next time. *Edit Cameras…* in that menu jumps straight here.

| Naming | Cameras |
| --- | --- |
| ![](Design/screenshots/settings-naming.png) | ![](Design/screenshots/settings-cameras.png) |

## File types

The type comes from the file extension (upper or lower case).

| Type | Extensions |
| --- | --- |
| Video | `mp4 mov mxf braw r3d crm mts m2ts avi mkv insv lrv 360` |
| Photo | `jpg jpeg heic heif png tif tiff dng arw cr2 cr3 nef raf orf rw2 srw pef gpr insp` |
| Audio | `wav mp3 aac m4a bwf` |
| Other | everything else (`xml`, `lrf`, `thm`, …) |

- **Sidecars** keep their clip's new name: an audio or other file next to a video or photo
  with the same name (`GX010001.WAV` → `…_0001.wav`), or Sony's `C0001M01.XML` style
  (`…_0001M01.xml`). They don't use up a sequence number.
- **Never copied:** anything starting with `.` (`.DS_Store`, `._C0001.MP4`,
  `.Spotlight-V100`, `.fseventsd`, `.Trashes`, `.TemporaryItems`…), `System Volume
  Information`, `$RECYCLE.BIN`, `Thumbs.db`, `desktop.ini`. Empty (zero-byte) files that
  aren't hidden are copied.

## Run it

1. Open `SnapDrop.xcodeproj` in Xcode (double-click it).
2. Press **⌘R**.
3. First run: click **Choose Folder…** in the *Destination* panel (or in Settings, ⌘,) and
   pick the folder for your footage. It's remembered from then on.
4. Insert a card, fill in the shoot name (and project/camera if your template uses them),
   and click **Offload N Files**.

The project builds without an Apple developer account ("Sign to Run Locally" /
ad-hoc signing). The app is not sandboxed so it can read `/Volumes` and write to any
folder you pick.

### First-launch notes

- macOS may ask *"SnapDrop would like to access files on a removable volume"* the first
  time it reads a card. Click **Allow**. (If you clicked Don't Allow, turn it back on in
  System Settings → Privacy & Security → Files and Folders.)
- If you copy the built `SnapDrop.app` somewhere and open it outside Xcode, Gatekeeper may
  block it because it isn't notarized. Right-click the app → **Open** → **Open**
  (or System Settings → Privacy & Security → *Open Anyway*).
- Closing the window quits SnapDrop. Keep it open while you work so it can catch cards.

## Build from the command line

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project SnapDrop.xcodeproj -scheme SnapDrop -configuration Debug \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build

# unit tests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project SnapDrop.xcodeproj -scheme SnapDrop \
  -derivedDataPath build/DerivedData test
```

### Demo mode (Debug builds only)

To see the UI without a card, launch the Debug build with sample data. It never touches
your real settings or ledger:

```sh
open -n build/DerivedData/Build/Products/Debug/SnapDrop.app --args \
  -SnapDropDemo YES -SnapDropDemoState ready -SnapDropDemoAppearance dark
```

States: `empty`, `ready`, `running`, `finished`. Appearance: `light` or `dark`.
Add `-SnapDropDemoSettingsTab general|naming|cameras` to open Settings on that tab.
The sample card has clips with Sony XML sidecars, RAW photos, WAVs and a few cameras.
Every view also has `#Preview`s you can open in Xcode's canvas.

## Code tour

| File | What's in it |
| --- | --- |
| `SnapDropApp.swift` | App entry point: main window and Settings scene |
| `AppModel.swift` | Ties settings, cameras, card watcher, ledger and the current offload together; eject, sound |
| `ContentView.swift` | Main window: the Card → Media → Destination funnel and toolbar |
| `FunnelComponents.swift` | Shared pieces: stage panel, step badge, arrows, count pills |
| `Motion.swift` | Animated pieces: arrow stream, shimmering progress bar, completion burst, row reveal |
| `CardStageView.swift` | ① Card panel |
| `ClipsStageView.swift` | ② Media panel: counts, project/shoot/camera, filterable name preview |
| `DestinationStageView.swift` | ③ Destination panel: folder, free space, layout |
| `OffloadBar.swift` | Bottom bar: Offload button, progress/ETA/Cancel, completion actions |
| `RecentOffloadsView.swift` | Recent Offloads popover |
| `SettingsView.swift` | Settings window (⌘,): tabs and the General tab |
| `NamingSettingsView.swift` | Naming tab: template editors, presets, token chips, example |
| `CamerasSettingsView.swift` | Cameras tab |
| `NamingTemplate.swift` | Template tokens, parsing/validation, presets, rendering |
| `OffloadPlanner.swift` | Turns files + templates into final paths; sequence numbers; sidecar matching |
| `MediaCategory.swift` | Video / Photo / Audio / Other by extension |
| `CameraStore.swift` | The camera list and per-card camera memory (`cameras.json`) |
| `FlowLogic.swift` | Pure logic for the UI: "why is Offload disabled", ETA and byte text, success feedback |
| `DemoData.swift` | Sample data for previews and demo mode (Debug only) |
| `OffloadSession.swift` | State for one card's offload; runs the copy in the background |
| `VolumeWatcher.swift` | Detects cards being inserted/removed |
| `ClipScanner.swift` | Finds media on a card, skipping system junk |
| `Renamer.swift` | Shoot-name cleanup and date formatting |
| `Copier.swift` | Copy + SHA-256 verify of one file, and the whole-card offload loop |
| `Ledger.swift` | The JSON record of everything offloaded |
| `Settings.swift` | Preferences: destination, templates, file types, eject, sound, recent projects |
| `Assets.xcassets/AppIcon` | App icon sizes: the hand-made "Comet A" set from `Design/comet-a/` |
| `Design/comet-a/` | "Comet A" icon set by Yuwie, one PNG per icon slot |
| `Design/icon-1024.png` | Master app icon (Comet A, 1024×1024) |
| `Design/icon-legacy-blue.png`, `.svg` | The previous blue icon, kept for reference |
| `Design/screenshots/` | Screenshots of the app (taken from demo mode) |
| `SnapDropTests/` | Unit tests: templates, planner, sidecars, file types, junk skipping, cameras, ledger, copy/verify, end-to-end fake cards |

The project uses Xcode's folder-synced groups: any `.swift` file you add to the
`SnapDrop/` folder is automatically part of the app. No third-party dependencies.

## Updating the icon

The icon is the "Comet A" set from Yuwie's Figma file:
<https://www.figma.com/design/6ToCClZ7GdsUFwWitX4MgP>

Each size is drawn by hand. The 16×16, 16×16@2x and 32×32 versions are simplified so
they stay readable in the menu bar and Finder lists, so **don't generate the sizes by
scaling one image with `sips`**. To update it:

1. Export the set from Figma into `Design/comet-a/` with these names:
   `icon_16x16.png`, `icon_16x16@2x.png`, `icon_32x32.png`, `icon_32x32@2x.png`,
   `icon_128x128.png`, `icon_128x128@2x.png`, `icon_256x256.png`, `icon_256x256@2x.png`,
   `icon_512x512.png`, `icon_512x512@2x.png`, plus `snapdrop-icon-1024.png`.
2. Copy them into the asset catalog and refresh the master copy:

```sh
cp Design/comet-a/icon_*.png SnapDrop/Assets.xcassets/AppIcon.appiconset/
cp Design/comet-a/snapdrop-icon-1024.png Design/icon-1024.png
```

`Contents.json` already points each slot at the file with the same name.

## License

MIT — see [LICENSE](LICENSE).
