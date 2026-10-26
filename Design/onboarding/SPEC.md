# Lodge onboarding: brand pass. Spec for Cody

**Status: PREVIEW. Nothing here is approved.** Oct 26, 2026. This is a rebrand of Ida's 7 concept screens (`ida-original/`, untouched copies). Her layout, copy and flow are kept. Every change is listed in "Changes from Ida's version" at the bottom.

All sizes are **points** (the PNGs are @2x, 2560×1600 px, so 1 pt = 2 px). The window is 1280×800 pt.

## Files

| Path | What |
|---|---|
| `01-splash.png` … `07-done-first-ingest.png` | The 7 screens @2x (Ida's file names) |
| `contact-sheet.png` | All 7 on one sheet |
| `onboarding.html` | Branded HTML source (generated, see below) |
| `style.css` | The stylesheet. Every token below is defined in it |
| `build_assets.py` → `build_html.py` → `render.py` | Rebuild pipeline: assets, then HTML from Ida's original plus `style.css`, then PNGs and the contact sheet |
| `assets/scene-splash.{svg,pdf}`, `scene-splash@1x.png`, `@2x.png` | Splash background, 1280×800 pt. The PDF is vector |
| `assets/scene-done.{svg,pdf}`, `@1x`, `@2x` | Done-screen background, 1280×800 pt |
| `assets/app-icon-{64,128,256,1024}.png` | The v5 B app icon (the sidebar uses it; the splash no longer does). In the app, use `NSApp.applicationIconImage` / `Image(nsImage:)` instead |
| `assets/lodge-wordmark-white.{svg,pdf}` (+ `-black` for light mode) | Outlined wordmark. The PDF is 53.42×18.18 pt (sidebar size), vector, and scales |
| `assets/lodge-glyph-cabin-color.{svg,pdf}`, `-512.png` (+ `-white`) | Cabin glyph. The PDF is 42×42 pt, vector |

Xcode: add the PDFs to the asset catalog with **Preserve Vector Data** on and **Single Scale**. The scene PDFs are heavy (gradients plus about 170 stars). If they rasterise slowly, use the @1x/@2x PNGs as a 2-scale image set instead.

## Global tokens (Dark appearance)

**Colours**. Use SwiftUI system names where they exist.

| Token | Value | SwiftUI / AppKit |
|---|---|---|
| Window background | #1A1A1C | `Color(nsColor: .windowBackgroundColor)` (close to it), or a fixed #1A1A1C if you want the exact look |
| Sidebar | #202022 | `NavigationSplitView` sidebar material (`.sidebar`) |
| Card / group box | white 4.5% + 1 pt inner stroke white 8% | `GroupBox`-like: `.background(.quaternary.opacity(0.5))`, `.separator` stroke |
| Inset well (fields, preview boxes) | black 22% + stroke white 8–16% | `.textBackgroundColor` / `TextField(.roundedBorder)` |
| Label | white 85% | `.primary` |
| Secondary label | white 55% | `.secondary` |
| Helper text | white 42% | `.secondary.opacity(0.75)` (between secondary and tertiary) |
| Tertiary | white 25% | `.tertiary` |
| Separator | white 8% | `Divider()` / `.separator` |
| **Accent / every interactive control** | **#0A84FF** (light #007AFF) | `.accentColor` = `Color.blue` |
| Success / done / verified | #32D74B (light #28CD41) | `Color.green` |
| Warning (none on these screens) | #FF9F0A | `Color.orange` |
| Destructive (none on these screens) | #FF453A | `Color.red` |
| Folder icon | #5BAEF7 | Finder-style folder. Or use `Image(systemName: "folder.fill").foregroundStyle(.blue)` |
| Brand afterglow (illustration only) | #F5A35C → #D2683C | Asset colours `BrandGlow1` and `BrandGlow2` |
| Brand lavender (text on the night scene) | #C9C0DD | Asset colour `BrandLavender` |
| Night sky (illustration only) | #1A1433 → #231A45 → #2E2150 → #4A2C52 | In the scene assets |

**Rule:** buttons, toggles, checkboxes, radios, segmented selection, focus ring, progress, selection and links are **system blue**. Orange and purple appear only in the brand art (scene, icon, glyph, the "calm." gradient, the splash pill dots).

**Token pills** (template tokens such as `{Date}`) are 12 pt mono, padding 2×6, radius 5. Background is the system colour at 14–22%; text is a lighter tint of the same colour.

| Category | Tokens | Colour | Fill | Text | |
|---|---|---|---|---|---|
| Project | Project, Client | `.indigo` #5E5CE6 | 22% | #B4B3FF |
| Date | Date, Time | `.cyan` #64D2FF | 15% | #8FDDFF |
| Device | Camera, Reel | `.pink` #FF375F | 16% | #FF94AA |
| Source | CardName, MediaType, OriginalName | `.green` #32D74B | 15% | #7BE38E | ← **stays green. Decided by Sebastian, Oct 26, 2026** |
| Person / sequence | Operator, Counter | `.yellow` #FFD60A | 14% | #FFE15C |

**Type**: SF Pro, which SwiftUI gives you automatically. Display is used at 20 pt and above, Text below that.

| Role | Font | Size / weight | SwiftUI |
|---|---|---|---|
| Splash headline | SF Pro Display | 64 Bold, tracking −2.5%, line 1.02 | `.system(size: 64, weight: .bold)` + `.tracking(-1.6)` |
| Done headline | SF Pro Display | 40 Bold, −2.2%, line 1.1 | `.system(size: 40, weight: .bold)` |
| Step title (h1) | SF Pro Display | 26 Bold, −1.2% | `.largeTitle.bold()` (26 pt on macOS) |
| Step intro | SF Pro Text | 14 Regular, secondary, line 1.45 | `.system(size: 14)` |
| Splash sub | SF Pro Display | 17 Regular, #C9C0DD, line 1.5 | `.title3` is 15, so use `.system(size: 17)` |
| Eyebrow "Step N of 5" | SF Pro Text | 12 Semibold, secondary, sentence case | `.subheadline.weight(.semibold)` |
| Card title | SF Pro Text | 13 Semibold, white | `.headline` |
| Body / option label | SF Pro Text | 13 Regular/Medium | `.body` |
| Helper / description | SF Pro Text | 12 Regular, helper colour | `.callout` |
| Section label | SF Pro Text | 12 Semibold, secondary | `.subheadline.weight(.semibold)` |
| Meta (free space, chips) | SF Pro Text | 11 | `.caption` |
| Paths, file names, tokens | **SF Mono** 11–13 Regular | | `.system(size: 12, design: .monospaced)` |

The PNGs were rendered without SF Mono or Menlo installed. Mono text in the PNGs is **DejaVu Sans Mono** (the font Menlo is derived from), so on a Mac, SF Mono will be slightly narrower and lighter.

**Controls** (standard SwiftUI controls give you these):

| Control | Size | Radius | Notes |
|---|---|---|---|
| Push button (footer, "Choose…") | h 28, padding 12 | 7 | Secondary: white 10% fill. Primary: blue, white text. `.buttonStyle(.borderedProminent)` + `.controlSize(.large)` |
| Large button (splash, done) | h 36, padding 18, 14 Medium | 9 | `.controlSize(.extraLarge)` on macOS 14+ |
| Small button (add row) | h 24, 12 pt | 6 | `.controlSize(.small)` |
| Switch | 32×18, knob 16 | 9 | `Toggle(.switch)`, tint blue |
| Checkbox | 16 | 4 | `Toggle(.checkbox)` |
| Radio | 16, dot 6 | – | `Picker(.radioGroup)` |
| Segmented | h 28, inner radius 5 | 7 | `Picker(.segmented)` |
| Text field | h 30 | 7 | Focused: 1 pt blue stroke + 3.5 pt blue 35% ring (system focus ring) |
| Card / group | – | 10 | Done-screen material panel 14, drop zone 14 |
| Window | 1280×800 | 12 | Unified title bar 52 pt, traffic lights at x 20, centred at y 26 |

## Shell (screens 02–06)

- **Title bar** 52 pt, transparent and unified (`.windowStyle(.hiddenTitleBar)` or `.toolbar` with `NavigationSplitView`). The traffic lights sit on the sidebar. The title "Set up your first template" is centred over the content pane in 13 Semibold, secondary. A 1 pt hairline (black 45% + white 3.5% highlight) sits under the title bar of the content pane only.
- **Sidebar** 256 wide, #202022, full height, with a right hairline. Padding: 64 top (under the traffic lights), 14 sides, 16 bottom.
  - Brand lockup at y 64: app icon 32×32 pt (the squircle reads as about 26), gap 6, white wordmark 18.2 pt tall (cap height 14.5 = squircle ÷ 1.8, per the brand lockup rule), cap centred on the icon. 24 pt below it:
  - "First template": 11 Semibold, helper colour, inset 10.
  - Steps: rows 34 tall, gap 2, radius 7, padding 10, 13 pt, number disc 20.
    - Upcoming: 1 pt ring white 16%, number in helper colour, label secondary.
    - Current: row fill white 8%, label white Semibold, disc **blue** with a white number.
    - Done: disc **green** with a white 11 pt checkmark (`checkmark.circle.fill`, green), label primary.
  - The note sits at the bottom: card white 4%, 1 pt white 8% stroke, radius 10, padding 12, 12 pt secondary, bold run in primary.
- **Content pane**:
  - Progress bar 3 pt directly under the title bar. Track white 6%, fill blue, trailing radius 2. Widths 20/40/60/80/100%.
  - Head padding 28 top / 44 sides: eyebrow, then 6, then h1, then 6, then intro (max width 760).
  - Body padding 22 top / 44 sides.
- **Footer** 60 tall, 1 pt separator above, padding 44 left / 24 right. "Skip setup" (13 Medium secondary + Regular helper text) on the left. On the right: **Back** (secondary push button with ←) and the **Primary** button (blue), gap 10. Back is at 40% opacity on step 1.

## Per screen

### 01 Splash
- Background: `scene-splash` full-bleed 1280×800 (cabin at bottom centre, x 640, base y 714, 0.31×; horizon y 612; moon top right; no stars behind the text block). An 90 pt bottom fade (#0E091E 0 → 55%) sits behind the version line.
- Title bar transparent, traffic lights only, no title.
- Centred stack in the band y 48–548 (content sits at about y 137–460, leaving ≥ 40 pt of clear sky above the cabin smoke). **No app icon on the splash. Decided by Sebastian, Oct 26, 2026.** The cabin in the scene is the only cabin on this screen.
  - Wordmark white (`lodge-wordmark-white.pdf`), 42.7 tall (cap height 34), then 34
  - "From card to calm.": 64 Bold white. **"calm."** is filled with a linear gradient #F5A35C → #D2683C (the brand afterglow). Then 16
  - Sub: 17 SF Pro Display Regular #C9C0DD, max width 560. Then 24
  - 3 pills: 12 Medium white 85%, padding 6×12, capsule, fill white 8% + 1 pt white 10% stroke, background blur 12. Dots 6 pt: #F5A35C / #C9C0DD / #D2683C. Then 28
  - CTA row, gap 10: **Get started →** (large, blue) and **Import existing templates…** (large, glass: white 10% + white 12% stroke, text white 80%)
- Bottom line 12 pt white 62%, inset 24, 18 from the bottom: "Version 1.0 · Concept" on the left; "Press [Return ↩] to begin" on the right (keycap: white 12% fill, radius 5).

### 02 What's a template?
- Flow row: card "Your card today" (252 tall; scattered mono 11 chips, white 7% fill, radius 6) → 96 column → card "With Lodge".
- Centre tile: 58×58, radius 14, gradient #2E2150 → #1A1433 (the icon's night sky), 1 pt white 12% stroke, with the **colour cabin glyph** at 42 (`lodge-glyph-cabin-color.pdf`). Caption "Template" 11 Semibold secondary, and a white 30% arrow.
- Tree: mono 12, rows 24, indent 18. Folders #5BAEF7, files secondary with a helper-colour icon, root white Medium, `ingest-report.mhl` green with a shield.
- 3 value cards, gap 12, padding 16×18. Icon tile 30, radius 8: blue on blue 16% (`square.3.layers.3d`), green on green 14% (`checkmark.shield`), indigo #8E8CFF on indigo 20% (`arrow.triangle.2.circlepath`). Title 13 Semibold white; text 12 secondary.

### 03 Destination
- Two columns, gap 16.
- Left card, "Primary destination":
  - "Required" chip (neutral: white 8% fill, 11 Medium secondary, capsule).
  - Drive rows: 34 icon tile (white 7%, radius 8), name 13 Semibold, usage bar 5 tall (track white 10%, fill white 45%), free space 11 helper, radio on the right.
  - Selected row: fill blue 16%, 1 pt blue 55% stroke, radius 8, blue drive icon, blue usage fill, blue radio.
  - "Folder" field (mono 12.5, folder icon) + **Choose…** push button.
- Right column:
  - "Backup destination" card: green shield; the switch is **blue**. Inset drive row: green drive icon, blue usage fill, mono path, **Change** button.
  - "When copying finishes" card: blue checkboxes.
  - Tip line: `info.circle` secondary + 12.5 helper text.

### 04 Folder structure
- Presets: buttons 30 tall, radius 8, white 6% + 1 pt white 8% stroke, 12.5 Medium secondary. Selected: blue 16% fill, 1 pt blue 70% stroke, white label, blue icon. "Blank" is outline only (1 pt white 16%).
- Editor card: rows 36, radius 7. Selected row: white 7% fill + 1 pt blue 60% stroke, with a blue text caret. Grips white 22%, carets helper colour, folders #5BAEF7. Route chips (Root / Video / Audio / Stills / Empty) are neutral chips. "Empty" uses helper-colour text.
- Add row: 1 pt separator above, small buttons "+ Folder" and "+ Subfolder", then "Route by media type" (12 secondary) with a **blue** switch on the right.
- Tokens panel, 250 wide: "Tokens · click to insert" (12 Semibold secondary + Regular helper), rows of pills with right-aligned 11.5 helper text. "Date format" is a pop-up button (`Picker(.menu)`) with ⌃⌄ chevrons, mono 12.

### 05 Naming & safety
- Two columns at a 1.25 : 1 ratio.
- "Rename files" card:
  - Blue switch.
  - Pattern field: min height 40, radius 7, inset well, **focused** (blue stroke + ring) with the pills inline and a blue caret; `.{ext}` in helper colour on the right.
  - Quick add row.
  - Live preview inset: mono 11.5. Old names in helper colour with strikethrough, arrow in helper colour, new names primary.
  - Checkbox "Keep sidecar files paired".
- "Verify every copy" card: green shield, blue switch, segmented "xxHash64 · fast | MD5 | SHA-256" (track white 7%, selected white 22%), checkbox "Write an ASC MHL report".
- "If a file already exists" card: radio group. "Recommended" is a **green** status chip (green 14% fill, #6EE087 text, 10 pt).

### 06 Review & save
- Columns 330 | fill.
- "Template name" field: 13 Semibold white with a film icon.
- Summary card: rows with padding 10 and separators. Icon in secondary (backup in green), key 11 helper, value 13 Medium. **Edit** is a blue link (12 Medium).
- Blue checkbox "Use as my default template".
- Live preview card: "Live preview" label + sample pills, tree as on 02 (rows 23), "… 211 more clips" in helper colour, MHL line in green.
- The primary button reads "✓ Save template".

### 07 Done / first ingest
- Background: `scene-done` full-bleed (cabin bottom left, x 330, base y 710, 0.30×). Title bar transparent; title "Lodge" in white 60%.
- Left column (600 wide, padding 88 top / 64 left):
  - Badge 52, radius 14, solid **green** with a white 26 checkmark, then 22
  - "Template saved": 12 Semibold #7BE38E
  - Headline 40 Bold white, 2 lines
  - Paragraph 15 #C9C0DD, max 470, with "Film shoot — Standard" in white Semibold
  - Tips: keycaps (`⌘ I`, `⌘ T`) and a blue switch row, 13 pt white 78%, gap 10
  - The left column must clear the cabin smoke (top about y 500): content ends about y 345.
- Right column (padding 72 top / 56 right / 150 bottom, centred vertically):
  - **Card detected** panel, material: #1E1E20 at 90% + blur 30 + saturate 1.4, 1 pt white 12% stroke, radius 14, shadow #080414 55% blur 60 y 24, padding 18. It shows:
    - Blue 8 pt pulse dot (blue 25% halo), "Card detected" 13 Semibold white, "just now" helper.
    - 48 tile (radius 11) with `sdcard`, "A001 · Sony FX6" 16 Semibold, and the meta line 12.5 secondary.
    - Chips: Project / Operator neutral, "2 destinations · 3.1 TB free" green.
    - **Ingest with Film shoot — Standard** (large blue, fills the width) + a square **Eject** large secondary button.
    - Estimate line 12 helper, centred.
  - Drop zone: 1.5 pt dashed white 28%, radius 14, padding 24, fill #140E28 at 45% + blur 16. Folder 34 in #5BAEF7, title 14 Semibold white, text 12 #C9C0DD.
  - Links: "Take the 60-second tour · Open Lodge", 13 Medium white 88% (separator white 45%).

## Light mode notes (not rendered)

- **Onboarding sheets (02–06):** use the system light palette. Window #ECECEC/#FFFFFF (`.windowBackgroundColor`), sidebar #F2F2F7-ish (`.sidebar`), cards white + 1 pt black 8% stroke, labels black 85% / 50% / 26%. Accent **#007AFF**, green #28CD41. Use the **black** wordmark (`lodge-wordmark-black`) in the sidebar. The app icon is unchanged. Folder colour #1E90F5. Token pills: the same hues at 12–15% fill with darker text: indigo #4B49C8, cyan #0A7FA8, pink #D81B4C, green #1E8E3E, yellow #9A7A00 (yellow on white needs the dark text).
- **Splash and done (01, 07): DECIDED (Sebastian, Oct 26, 2026). The night scene stays in light mode too** (there is no day version, the same as the light README header). Force these two screens to the dark appearance (`.environment(\.colorScheme, .dark)` / `.preferredColorScheme(.dark)` on the hosting view), so the text stays white / #C9C0DD, the done panel stays the dark material, and the controls use the dark-mode blue #0A84FF. Only the onboarding sheets 02–06 follow the system appearance.

## Changes from Ida's version

1. Ember-orange placeholder mark → **v5 B app icon** in the sidebar, and the **outlined Lodge wordmark** in place of the live "LODGE" tracked caps and the Inter Tight text wordmark. The splash shows **only the wordmark**: Ida's big mark is removed (decided by Sebastian, Oct 26, 2026).
2. Warm charcoal palette → **neutral macOS Dark Mode** (#1A1A1C window, #202022 sidebar, white-alpha labels and strokes).
3. All orange controls → **system blue**: primary buttons, radios, checkboxes, switches (her pine-green switches too), selected drive and preset, progress bar, focus ring, text caret, "Edit" links. Orange gradient buttons with dark text → flat blue with white text.
4. Green kept only for status: done steps, verified/shield, "Recommended", the done badge, the "2 destinations" chip.
5. Eyebrows "STEP N OF 5" / section labels: tracked uppercase orange → sentence case in secondary grey (macOS style). "Card detected" is no longer uppercase orange.
6. Token colours: ember/sky/plum/pine/sand → system indigo/cyan/pink/green/yellow tints (same category mapping).
7. Folder icons warm beige/orange → Finder blue. Route chips (Video/Audio/Stills/Required) → neutral grey.
8. **Splash**: radial ember glow + contour lines → the full brand **night scene** with the cabin. "calm." gradient is now the brand afterglow (#F5A35C → #D2683C). Pills are glass with brand dots. h1 68 → 64. "Return" keycap → "Return ↩".
9. **Done**: ember glow background → the night scene with the cabin bottom left. The card-detected panel became an opaque dark material (blue status dot instead of an ember outline/glow). Drop-zone folder is blue; the links are now white.
10. Template tile on 02: generic "layers" icon → the **colour cabin glyph** on a night-sky tile.
11. **Footer page dots removed**: the sidebar steps and the progress bar already show position. "Skip setup" is now left-aligned with the buttons right-aligned. Footer 68 → 60.
12. Title bar: 40 pt opaque bar → 52 pt transparent unified title bar, with the traffic lights on a full-height sidebar (macOS 11+ `NavigationSplitView` look).
13. Sizes tightened to macOS metrics: h1 28 → 26, intro 14.5 → 14, body 13, buttons 34 → 28 (large 42 → 36), fields 36 → 30, switches 34×20 → 32×18, card radius 12 → 10.
14. 03: the backup card lost its green border (the switch says it's on). The "Low on space?" tip uses `info.circle` instead of the sand sparkle.
15. 04: "Route by media type" became a plain label + switch (it was a ghost button containing a switch). The date format became a pop-up button with ⌃⌄.
16. Fonts: Inter / Inter Tight / JetBrains Mono → SF Pro Text / SF Pro Display / SF Mono.

No copy was changed.

## Decided (Sebastian, Oct 26, 2026)

- The splash shows only the wordmark, with no app icon.
- Splash and done keep the night scene in light mode, forced to the dark appearance.
- The token colours stay as specified, and Source tokens stay **green**.

## Open questions / uncertain

- **Folder colour** #5BAEF7 imitates Finder; SF Symbol `folder.fill` in `.blue` would be the native alternative.
- **Mono font in the PNGs** is DejaVu Sans Mono (SF Mono/Menlo aren't on the render box). The real app uses SF Mono.
- **macOS 26 (Tahoe) metrics**: the window/control radii follow macOS 14/15 here. On Tahoe, standard controls are rounder (capsule-ish large buttons, larger window radius). Using stock SwiftUI controls picks this up automatically.
