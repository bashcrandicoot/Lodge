# Changelog

## Unreleased

**Coming in the next update.** Not in the [Lodge 1.0.0](https://github.com/bashcrandicoot/Lodge/releases/tag/v1.0.0) download.

- **Expand All** and **Collapse All** open and close the Layout tree. Click a triangle, or Option-click to open or close everything inside a folder. Expand All also opens folders already at the destination, three levels in. In Lodge 1.0.0 the tree shows the folders, and you drag a level, or a token from **Add a level**, to rearrange it.
- A folder Lodge will create is marked **New**. One already there is marked **Already there**. A folder’s files can fold into one line, the first name with **+ N more** under it. Lodge 1.0.0 shows one example file name, and notes extra folders as a line such as **+ 2 more folders**.
- Tokens can sit side by side in one folder level, such as `{project}_{date}`. Drop a level or a token on the left or right side of a name. Drag a piece back out between folders to give it its own level. The separator is **Underscore**, **Hyphen**, **Space**, or **None**.
- The preset menu sits at the top right of the window, just left of **Recent Offloads** and **Settings**, and the window title is hidden. In Lodge 1.0.0 the preset menu is in the center of the toolbar, and the title reads Lodge.
- **Help > Contact Support…** and **Support Lodge…** join the Help menu. After a few offloads, Lodge shows a quiet tip once. You can dismiss it.

## 1.0.0

First public release of Lodge, a native Mac app (macOS 14 or later) for offloading camera memory cards. Download it from the [v1.0.0 release](https://github.com/bashcrandicoot/Lodge/releases/tag/v1.0.0): `Lodge-1.0.0.dmg` and `Lodge-1.0.0.zip`.

### Offload and verification

- Lodge notices a memory card when it is inserted, and cards that are already mounted at launch. Removable and ejectable volumes under `/Volumes` qualify. The drive that holds the destination folder is left out. The window comes forward. Closing the window quits the app.
- The window reads Card, Media, Destination, with the offload bar along the bottom.
- Lodge copies the new files only. Each file is written to `<name>.lodge-partial`, read back from disk, and checked with SHA-256. A matching hash is renamed to the final name. A mismatch deletes the partial file and is reported as a failure. The card is only ever read during a copy.
- The bar shows the current file, the count, bytes copied, time remaining, a **Verifying** state, and **Cancel**.
- The selected card’s line reads **54 new files · 5 ignored** before and during an offload, and **57 copied · 5 ignored** when it has finished. With nothing ignored, the “· N ignored” part is left off. One new file reads **1 new file**. None reads **No new files**.
- A clean finish can play the Glass sound. **Play a sound when an offload finishes** is on by default.
- **Eject card after offload** is off by default, and ejects only when every file copied and verified. The same switch ejects after a format.
- When the offload ends: **Show in Finder**, **Eject Card**, **Done**, and **Format Card…** when the card is ready. The summary line reads like **57 copied · 0 skipped · 0 failed**.

### Ledger and missing copies

- Every verified copy is recorded in `~/Library/Application Support/Lodge/ledger.json`. A file is identified by the card’s volume UUID (or its name), its path on the card, its size, and its modification time.
- Inserting that card again copies only files the ledger does not already have.
- If the copy is gone, or its size has changed, Media shows an orange warning such as **3 missing at destination**. Those files are not copied again until you ask.
- **Re-offload Missing Copies** copies the missing ones. **Re-offload Everything on This Card…** copies the card again, after a confirmation. The right-click menu has **Re-offload This File** and **Don’t Re-offload This File**. Re-offloaded files are new copies. Lodge does not overwrite what is already in the destination.
- **Forget This Card’s History…** clears the ledger for that card, so everything on it counts as new. Until it is offloaded again, it is not ready to format.

### Ready to format

- A green **Ready to format** badge appears when every file on the card has a verified copy that is still at the destination with the same size. The badge glows as it appears. Otherwise the card says how many files are not offloaded yet, how many copies are missing, or how many short clips were skipped.
- Ignored items (system files and the ignore list) are counted in the card line and do not block the badge. Formatting still erases them, and the confirmation says so.
- **Format Card…** is in the card’s **…** menu, its right-click menu, and the finished offload bar. The confirmation defaults to **Cancel**. The format button reads **Format**, or **Format and Discard N Short Clips** when the only files without a copy are clips you skipped on purpose.
- Lodge formats exFAT, FAT32, and FAT16, keeping that file system and the card’s name, with `diskutil eraseVolume`. It refuses anything that is not the scanned card, not mounted under `/Volumes`, not a volume on a disk, not removable media, the startup disk, or the drive the destination folder is on. Other file systems are left for the camera. Lodge checks again that the card is still ready immediately before erasing.
- The confirmation includes the tip that formatting in the camera is usually best.

### Naming

- A folder template and a file template. The default is `{date}/{project}` and `{date}_{project}_{seq}`.
- `{project}` is the project name from the main window. “Beach Shoot” becomes `BeachShoot`. Up to six recent projects stay one click away.
- Tokens: `{project}`, `{camera}`, `{date}`, `{year}`, `{month}`, `{day}`, `{time}`, `{type}`, `{card}`, `{original}`, `{seq}` (and `{seq:3}`), `{ext}`. The real extension is always added, in lower case. `{shoot}` is accepted as another name for `{project}`. Saved templates that still say `{shoot}` are updated, and a doubled `{project}` collapses to one.
- The **Examples** menu in Settings > Naming applies **Date / Project**, **Project / Date / Camera**, **Project / Type / Date**, **Year / Month / Day**, **Date / Project, Original Names**, or **Flat**, and can **Reset to Default**.
- Click a token chip to insert it. An unclosed `{`, an unknown token, `{seq}` twice, or a name starting with `.` is explained under the field, and Offload stays off until the error is fixed.
- The date is the file’s creation date, or its modification date when there is no creation date. Sequence numbers continue after the highest one already in that folder. Without `{seq}` or `{original}`, files that would share a name get `_2`, `_3`, and so on. Nothing is overwritten.
- The Media list previews the finished names, filtered with **All**, **Video**, **Photo**, **Audio**, and **Other**. Sidecars sit with their clip.

### Short clips

- **Settings > General > Skip videos shorter than** is a slider from **Off** to **30 s**, in steps of one second. The default is **5 s** (skipping is on). The stepper beside it goes from Off up to 60 seconds.
- Videos under the limit stay on the card with their sidecars and proxies. Media says **2 short clips skipped** (or **1 short clip skipped**). Open that list for **Include Anyway** on one clip or **Include All**.
- Clips whose length cannot be read, including BRAW and R3D, are always offloaded. Proxies are not skipped on their own. They follow their clip.

### Presets

- The toolbar menu above the funnel switches presets. A preset stores the destination, the folder and file templates, the camera, the short-clip setting, quick dump, and the file rules.
- **Save Current Setup as Preset…** saves what the window is using. Change something afterwards and the menu shows **Edited**, with **Update “Name”** for the preset in use. **Manage Presets…** opens Settings > Presets, where you can add, rename, edit, and remove them. An empty menu says **No Preset**.

### Quick dump

- **Quick dump: skip project name**, under the Camera field, removes `{project}` from both templates. `{date}/{project}` and `{date}_{project}_{seq}` become `{date}` and `{date}_{seq}`. There is no project to type. Numbering still continues from the destination folder. In the Layout tree, a level that quick dump removes is marked **Quick dump**.

### Destinations

- Favorite destinations, each with a name, a folder, and free space. Click the folder in Destination for the list, **Choose Other Folder…**, and **Edit Favorites…**.
- Settings > Destinations adds, removes, renames, reorders, changes the folder, and can **Make Default**. A favorite whose drive is unplugged says **Not connected** and cannot be selected.
- The list is `~/Library/Application Support/Lodge/destinations.json`, with a bookmark for each folder so a renamed or moved folder can still be found. On launch, Lodge selects the default favorite when that drive is connected. When it is not, Lodge selects the favorite you used last if that drive is connected, and otherwise any other connected favorite. A folder chosen with **Choose Other Folder…** is remembered, and the menu offers **Add “Folder” to Favorites**, using the folder’s name.

### Drag and drop

- Drop a folder from Finder onto the Destination column, or onto the Layout tree, to make it the place files are copied.
- With a card scanned, the Layout tree shows the folders the template will create, including **Proxies** and **Sidecars** when those files are in the plan. Drag a level to rearrange it. Drag a token from **Add a level** onto the tree, or click the token to append it. The tree says **Drag to rearrange**.
- A drop Lodge accepts gives trackpad feedback on a Force Touch trackpad.

### File rules

- Settings > Files. **Proxies** (default `lrv`, `lrf`) are copied into a `Proxies` folder next to the clips and named after the clip. **Sidecars** (default `thm`, `xml`, `srt`) go to a `Sidecars` folder the same way. Audio recorded beside a clip, such as a `.wav` with the same name, stays next to that clip and shares its new name. Sony names like `C0001M01.XML` keep the `M01` suffix.
- The ignore list (default `.DS_Store`, `._*`, `.Spotlight-V100`, `.Trashes`, `.fseventsd`, `.TemporaryItems`, `Thumbs.db`) is never offloaded. Patterns can use `*` and `?`. Lodge also always skips system junk: names that start with `.`, `System Volume Information`, `$RECYCLE.BIN`, `recycler`, `recycled`, and `desktop.ini`.
- Ignored items show up in the card line and do not stop **Ready to format**. A pattern that would hide photos or video is warned about, because formatting would erase those files.

### Themes and appearance

- **Default** is the theme Lodge starts with: a neutral black and white window, no colour wash, and the system accent on controls. In Dark mode the window is a neutral near-black. The accent is system blue unless another accent is chosen in System Settings. The ready-to-format badge and verified ticks stay green, warnings stay orange, and destructive actions stay red.
- **Aurora**, **Ocean**, **Twilight**, **Ember**, and **Forest** are optional colour themes. They paint a soft wash behind the window and use their own gradient on the Offload button, the progress bar, the glowing border of the step that needs you, the dots flowing between steps, and the glow when an offload finishes.
- Appearance is **Dark**, **Light**, or **System**. Lodge starts on **Dark**.
- With **Increase Contrast** or **Reduce Transparency** turned on, every theme uses solid colours.
- A saved theme named Comet or Graphite opens as Default.
- **Show files as** switches the Media column between a list and a thumbnail grid, and Lodge remembers the choice. **Show thumbnails in the list** adds small thumbnails to list rows.

### Motion

- A clean finished offload draws the checkmark in. With Reduce Motion, the finished mark is shown at once.
- The copied count in the summary, and the size of the new files, count up. With Reduce Motion they appear at their final value.
- Inserting a card plays a short accent glow on the card panel.
- Card rows and grid tiles lift slightly under the pointer. Reduce Motion keeps the highlight and skips the lift.
- The **Ready to format** badge glows, and the seal bounces, when it appears.
- Dropping a folder onto Destination or the Layout tree, and dropping a level or token onto the tree, gives a light haptic on a Force Touch trackpad when the drop is accepted.
- Animations follow **System Settings > Accessibility > Display > Reduce motion**.

### Also in this release

- Media as a list or a thumbnail grid. Tiles show a thumbnail, the new name, duration, type, and a paperclip count for sidecars. The file being copied shows a progress ring. Verified files get a green tick. Files offloaded earlier are dimmed. Missing copies are marked. Skipped short clips are marked, with **Include Anyway** in the menu.
- Thumbnails come from Quick Look, are cached, and are only read from the card. Formats Quick Look cannot draw show a symbol.
- Select files and press Space (or double-click, or **Quick Look**) to preview them. Arrow keys follow the list and the filter.
- Cameras in Settings > Cameras: a name, an optional short code for `{camera}`, drag to reorder. Lodge remembers which camera you used with each card.
- **Recent Offloads** from the clock in the toolbar, with **Show in Finder**.
- File types by extension, upper or lower case. Video includes `mp4`, `mov`, `mxf`, `braw`, `r3d`, `crm`, `mts`, `m2ts`, `avi`, `mkv`, `insv`, and `360`. Photos include JPEG, HEIC, PNG, TIFF, DNG, and common camera RAW types. Audio includes `wav`, `mp3`, `aac`, `m4a`, and `bwf`. Everything else is Other. GoPro `.lrv` and DJI `.lrf` are proxies, not a second copy of the footage.
- Settings tabs: General, Appearance, Presets, Destinations, Naming, Files, Cameras. Open them with Command-comma.
