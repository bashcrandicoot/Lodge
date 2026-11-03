# User guide

Lodge copies files off a camera card or other pluggable drive, names each file from a template, and checks the copy before it keeps it. Plugging in a card does not start a copy. **Import** only opens Lodge with that card selected. Nothing is copied until you press Offload.

## Install and first launch

[Buy Lodge](https://buy.polar.sh/polar_cl_gS9NEtdIPJuJDXu8sdui02XetKbkwKuHgiYxi4FBkM1). Open the .dmg, and drag Lodge to Applications.

macOS asks the first time you open Lodge.

### macOS 15 Sequoia and later

1. Open Lodge.
2. Click **Done** on the warning.
3. Go to **System Settings > Privacy & Security**.
4. Click **Open Anyway** next to Lodge, and confirm.

### macOS 14 Sonoma

1. Right-click or Control-click Lodge.
2. Choose **Open**.
3. Choose **Open** again.

Return is the default button for **Get started** and for **Offload with `<preset>`**. The setup done screen draws a **⌘ ,** keycap. **⌘,** opens Settings.

Drive rows during setup show one of:

- **Free space unknown**
- **`<bytes>` free**
- **`<bytes>` free of `<bytes>`**

`<bytes>` is a file-size figure.

## Your first offload

### When Lodge asks to import

Lodge shows **Import with Lodge?** only when every one of these is true:

- The volume path is under `/Volumes/`, and it is not the startup disk.
- The volume is local, not a network volume.
- It is not a disk image.
- It is pluggable media: removable, or external and ejectable.
- It is not a backup volume.
- The destination folder is not on that volume.
- You have not chosen **Don’t ask for this card** for that card.
- The volume looks like camera media.

These camera folders qualify: `DCIM`, `PRIVATE/M4ROOT`, `PRIVATE/AVCHD`, `AVCHD`, `XDROOT`, `PRIVATE/XDROOT`, `BPAV`, `CONTENTS`, `MP_ROOT`, `CLIPS001`, `XFAVC`, `PRIVATE/PANA_GRP`, `PRIVATE/CANON`, and `BLACKMAGIC`. A volume also qualifies when media files sit in the top folders.

The same card is not asked twice within the debounce interval. A card plugged in during an offload or a format is queued until that finishes.

The title is the card name plus "connected". When the name does not already end in card, drive, ssd, or disk, the title uses " card connected" or " drive connected" (with the leading space). The body is **Import with Lodge?**

On a notification, the actions are **Import** and **Don’t Ask for This Card**.

If notifications are off, Lodge shows a floating panel with the same title and the same body. Its buttons are **Import** (Return), **Ignore**, and **Don’t ask for this card**.

**Import** opens Lodge with that card selected. **Ask with** chooses **Notification** (the default) or **Floating panel**.

While detection is paused, the menu says **Resume Detection**.

### Offload

While Lodge is ready, the bar says **Ready. Every file is verified with SHA-256 after copying.** The button help is **Copy and verify the new files**. During the copy the stage label is **Copying**, then **Verifying**.

Return is Offload when that is the default button.

If Offload cannot start, its caption is one of the messages in [Why Offload is waiting](#why-offload-is-waiting).

## Verification

Lodge copies one file like this:

1. It writes `<final name>.lodge-partial` and hashes the source with SHA-256 as it reads.
2. It reads that partial file back from disk and hashes it.
3. If the hashes match, it renames the partial file to the final name. If they do not, it deletes the partial file.

The card is only read. A file that is already at the final path is not overwritten.

What you see when a file fails:

- **`<name>` already exists — not overwriting it.**
- **Couldn’t create `<name>` in the destination.**
- **Checksum mismatch for `<name>`. The copy was deleted.**

When the batch finishes, the title is **Offload Complete**, **Finished with Problems**, or **Offload Cancelled**.

The line under it is **`<copied>` copied · `<skipped>` skipped · `<failed>` failed**. If the card is already gone after an eject, that line gains ** — card ejected, safe to remove**.

If a copy Lodge expected is missing at the destination, Offload tells you to choose Re-offload. The wording is in [Re-offload](#re-offload).

## Naming templates and tokens

The default folder template is `{date}/{project}`. The default file template is `{date}_{project}_{seq}`. The built-in preset that uses them is named **Date / Project**.

| Token | Meaning in the template editor | Rendered value |
| --- | --- | --- |
| `{project}` | Project name | the project field |
| `{camera}` | Selected camera | the selected camera |
| `{date}` | Capture date (2026-10-25) | `yyyy-MM-dd` |
| `{year}` | Year (2026) | `yyyy` |
| `{month}` | Month (10) | `MM` |
| `{day}` | Day (25) | `dd` |
| `{time}` | Capture time (143005) | `HHmmss` |
| `{type}` | Video, Photo, Audio or Other | **Video**, **Photo**, **Audio**, or **Other** |
| `{card}` | Card (volume) name | the volume name |
| `{original}` | Original file name, no extension | the source name, made safe |
| `{seq}` | Sequence number (0001); {seq:3} for 001 | at least 4 digits, unless `{seq:N}` says otherwise |
| `{ext}` | File extension (mp4) | the extension, lowercased |

In a file or folder name, `/`, `:`, `\`, `*`, `?`, `"`, `<`, `>`, `|`, and control characters become `-`. Spaces at the ends are trimmed, and leading dots are stripped so the name is not a hidden file.

The project name is cleaned separately. Letters, digits, and `-` stay. Any other character splits a word, and each word is capitalized, so "beach day" becomes `BeachDay`. The result is at most 60 characters, and leading or trailing `-` is removed.

Sequence numbers continue after the highest number already in the destination folder.

`jpeg` and `jpe` share `jpg`. `tiff` shares `tif`.

## Presets and quick dump

**Date / Project** is the built-in preset: folder `{date}/{project}`, file `{date}_{project}_{seq}`.

On the setup done screen, Return can be **Offload with `<preset>`**.

**Quick dump** is off until you turn it on.

## Sidecars and proxies

Proxies go in `Proxies/`. The default proxy extensions are `lrv` and `lrf`.

Sidecars go in `Sidecars/`. The default sidecar extensions are `thm`, `xml`, and `srt`.

They keep the clip’s new name.

These names are ignored and not copied. The defaults are `.DS_Store`, `._*`, `.Spotlight-V100`, `.Trashes`, `.fseventsd`, `.TemporaryItems`, and `Thumbs.db`.

When a date filter is on, sidecars and proxies go with their clip. Everything else outside the chosen days stays on the card.

## Filtering by date and skipping short videos

**Dates** is **Any date** until you change it. The other choices are **Today**, **Last 7 days**, and **Custom range**.

The date-filter help says: **Copies only files from these days, by the date each file was created (or last changed, if the card doesn’t record that). Sidecars and proxies go with their clip. Everything else stays on the card.**

If the chosen days leave nothing new, Offload says **Nothing new in the chosen dates — choose Any date to see everything**.

**Skip videos shorter than** is on, at 5 seconds. The value can be from 1 to 60 seconds. The slider stops at 30, and Off is 0.

If the only videos left were skipped for length, Offload says one of:

- **Only a short clip is left — choose Include Anyway to offload it**
- **Only short clips are left — choose Include All Short Clips to offload them**

## Destinations and free space

There is no destination folder until you choose one. The folder panel says **Choose the folder Lodge should copy your media into.** The button is **Choose**.

Offload stays off, and says why, in these cases:

- **Choose a destination folder**
- **The destination folder isn’t connected — choose another**
- **Not enough space: needs `<needed>`, `<available>` free**

`<needed>` and `<available>` are file-size figures. Lodge prefers the capacity macOS reports for important usage when that figure is above 0, then the available capacity. A lone 0 from the important-usage figure is not treated as a full disk.

On a favorite, the space reads **`<bytes>` free**. A favorite that is not mounted says **Not connected**.

Under the destination, the space reads **`<bytes>` available**, or **Free space unknown**, and **needs `<bytes>`** when a copy is planned.

A read-only destination uses one of:

- **This drive is read-only, so Lodge can’t write to it — choose another** when Lodge has no format name
- **This drive is read-only (NTFS). macOS can’t write to it.**
- **This drive is read-only (`<format>`), so Lodge can’t write to it — choose another** for any other format

Format names Lodge recognizes are **NTFS**, **exFAT**, **FAT32**, **Mac OS Extended**, and **APFS**.

## Re-offload

When copies are missing at the destination, Offload says:

- **1 copy is missing at the destination — choose Re-offload**
- **`<n>` copies are missing at the destination — choose Re-offload**

There is a re-offload confirmation. Return is its default button. The destructive button has no keyboard equivalent.

## Ejecting and the format confirmation

The manual command is **Eject Card**. After the card is gone, the label is **Ejected**.

**Eject Card** is disabled while an offload, a format, or an eject is in progress. On the finish bar it is disabled once the card has already been removed.

**Eject card after offload** is off. Its caption is **Only when every file was copied and verified.** Automatic eject runs only when that switch is on and every file verified. Lodge then unmounts the volume and ejects the disk. If that fails: **Couldn’t eject `<card name>`: `<system message>`**.

After a successful eject, the finish line can end with ** — card ejected, safe to remove**.

The format confirmation uses the same keys: Return is the default button, and the destructive button has no keyboard equivalent.

## Menu bar mode

**Keep Lodge running in the menu bar** is off. Turn it on and Lodge can keep running from the menu bar.

These sit with it:

| Setting | Default |
| --- | --- |
| Ask to import when a card or drive is plugged in | on |
| Show menu bar icon | on, and only shown while menu bar mode is on |
| Ask with | **Notification** (the other choice is **Floating panel**) |
| Open at login | off |

**Open at login** follows whether macOS will open Lodge at login. It is not stored as an ordinary on/off preference. The menu-bar hint includes **Allow Lodge in System Settings ▸ General ▸ Login Items.**

**⌘-drag** the menu bar icon out to turn **Show menu bar icon** off. If the icon is hidden, the hint says to quit with **⌘Q**. The menu bar item’s quit key is `q`.

While detection is paused, the menu says **Resume Detection**. The menu bar item for Settings uses **⌘,**.

A failed import-prompt test can report **“Ask to import” is off in Settings ▸ General ▸ Menu Bar.**

## Settings reference

Settings tabs are **General**, **Appearance**, **Presets**, **Destinations**, **Naming**, **Files**, and **Cameras**.

Theme is **Default**. Appearance is **Dark**. The other appearance choices are **System** and **Light**. A saved theme name Lodge does not know, including `comet` and `graphite`, becomes Default.

**Show files as** is **List**. The other choice is **Grid**. **Show thumbnails in the list** is off.

General groups these sections: **Files to Offload**, **Short Clips**, **After Offload**, **Menu Bar**, and **Updates**.

| Setting | Default |
| --- | --- |
| Destination folder | none, until you choose one |
| Eject card after offload | off |
| Folder template | `{date}/{project}` |
| File template | `{date}_{project}_{seq}` |
| Last project | empty |
| Recent projects | empty, and at most 6 |
| Files to offload | Video, Photos, Audio, and Other all on |
| Play a sound when an offload finishes | on |
| Skip videos shorter than | on, 5 seconds (1 through 60; the slider stops at 30, and Off is 0) |
| Theme | Default |
| Appearance | Dark |
| Show files as | List |
| Show thumbnails in the list | off |
| Quick dump | off |
| Dates | Any date |
| Keep Lodge running in the menu bar | off |
| Ask to import when a card or drive is plugged in | on |
| Show menu bar icon | on, while menu bar mode is on |
| Ask with | Notification |
| Open at login | off |
| Don’t ask for these cards | empty |
| Proxies | `lrv`, `lrf` |
| Sidecars | `thm`, `xml`, `srt` |
| Ignored names | `.DS_Store`, `._*`, `.Spotlight-V100`, `.Trashes`, `.fseventsd`, `.TemporaryItems`, `Thumbs.db` |
| Automatically check for updates | on |
| Update check interval | once a day |
| Automatically download and install updates | off |

The folder panel’s message is **Choose the folder Lodge should copy your media into.** Its button is **Choose**.

The updates footer says: **Lodge checks for a new version once a day. You can also choose Lodge ▸ Check for Updates… any time.**

## Keyboard shortcuts

| Shortcut | What it does |
| --- | --- |
| ⌘, | Settings. The menu bar item uses the same key. The setup done screen draws a **⌘ ,** keycap. The Settings toolbar help is **Settings (⌘,)**. |
| ⌘Q | Quit. The hidden-icon hint says **quit it from there with ⌘Q.** |
| ⌘-drag | Drag the menu bar icon out to turn **Show menu bar icon** off. |
| Return | The default button: Offload, Done, **Import** on the floating panel, **Get started**, and **Offload with `<preset>`**. Also the default button on the format confirmation and the re-offload confirmation. |
| Escape | **Cancel** during an offload. **Maybe Later** on the support note. Clears the selection in the list or grid. |
| Space | Quick Look on the selection. Space again is handled while the panel is up. The list and grid hint is **Press Space to preview the selected file with Quick Look**. |
| Up, Down, Left, Right | Move the selection in the list or grid. |
| ⌘-click | Toggle a file in the selection. |
| Shift-click | Extend the selection. |
| Double-click | Quick Look. |

The destructive button on the format confirmation and on the re-offload confirmation has no keyboard equivalent.

## Troubleshooting

### Why Offload is waiting

| Message | What it means |
| --- | --- |
| Insert a card to begin | No card yet. |
| Scanning card… | The scan is still running. |
| This card is empty | There is nothing to copy. |
| Enter a project name | The template uses `{project}`. |
| Choose a camera | The template uses `{camera}`. |
| Fix the naming template in Settings | The template is not usable. |
| Choose a destination folder | No folder yet. |
| The destination folder isn’t connected — choose another | That drive is not mounted. |
| Not enough space: needs `<needed>`, `<available>` free | The destination is smaller than the copy. |
| 1 copy is missing at the destination — choose Re-offload | One expected copy is missing. See [Re-offload](#re-offload). |
| `<n>` copies are missing at the destination — choose Re-offload | More than one expected copy is missing. |
| Only a short clip is left — choose Include Anyway to offload it | The only remaining video was skipped for length. |
| Only short clips are left — choose Include All Short Clips to offload them | The only remaining videos were skipped for length. |
| Nothing new in the chosen dates — choose Any date to see everything | The date filter is hiding every new file. |
| Everything on this card is already offloaded | There is nothing new to copy. |

A copy that does start can still fail with:

- **`<name>` already exists — not overwriting it.**
- **Couldn’t create `<name>` in the destination.**
- **Checksum mismatch for `<name>`. The copy was deleted.**

### Read-only drives

- **This drive is read-only, so Lodge can’t write to it — choose another**
- **This drive is read-only (NTFS). macOS can’t write to it.**
- **This drive is read-only (`<format>`), so Lodge can’t write to it — choose another**

Recognized format names are **NTFS**, **exFAT**, **FAT32**, **Mac OS Extended**, and **APFS**.

### If an import prompt does not appear

A failed import-prompt test uses one of these:

- **Lodge isn't ready yet.**
- **No cards or drives are connected.**
- **“Ask to import” is off in Settings ▸ General ▸ Menu Bar.**
- **Detection is paused (menu bar ▸ Resume Detection).**
- **None of the connected cards or drives qualify for a prompt. Details are in Console (subsystem com.sebastianphillips.Lodge, category ImportPrompt).**

The same card is also skipped for the rest of the debounce interval, and a card that appears during an offload or a format waits until that finishes.

### Report a Bug

**Report a Bug…** opens an email to bashframes@gmail.com. Nothing is sent until you send it.

The subject is **Lodge bug report (version `<version>` build `<build>`)**.

The body starts with **What happened?** and one of:

- **(What were you doing, and what went wrong? Steps to make it happen again help a lot.)**
- **(Lodge quit unexpectedly. What were you doing just before?)**

Then **Lodge `<version>` (build `<build>`)**, **macOS `<version>`**, and **Mac: `<model>`, `<chip>`**. The log section is **Lodge’s recent log:** or **(nothing logged recently)**. Up to 200 of Lodge’s own log lines from the last three days are attached as `Lodge log.txt`. Paths under your home folder, `/Volumes`, `/Users`, `/private`, `/var`, and `/tmp` are replaced with `<path>`.

If Mail cannot attach a crash report, the body adds **(The crash report couldn’t be attached. It’s in Console ▸ Crash Reports, under Lodge.)**.

The next time you launch, if a new `Lodge-….ips` or `Lodge_….crash` report is in Diagnostic Reports, Lodge asks **Lodge quit unexpectedly last time. Send a crash report?** The detail is **This opens a new email to bashframes with the crash report and Lodge’s recent log attached. File, card and drive names are left out. You can read it over before sending.** The buttons are **Send Report** and **Not Now**. This is not offered at login, and each report is offered once.

### Eject failed

**Couldn’t eject `<card name>`: `<system message>`**

## Updates

**Automatically check for updates** is on. Lodge checks once a day. **Automatically download and install updates** is off.

The footer says: **Lodge checks for a new version once a day. You can also choose Lodge ▸ Check for Updates… any time.**

## Support

If Lodge has been useful, [Support Lodge](https://ko-fi.com/bashframes).

The support note is titled **Support Lodge**. Its body is **Lodge is made by one person at bashframes. If it saves you time, you can chip in on Ko-fi. Thank you!** The buttons are **Don’t Ask Again**, **Maybe Later** (Escape), and **Support Lodge**. **Support Lodge** opens [ko-fi.com/bashframes](https://ko-fi.com/bashframes).

The note shows only when all of these are true:

- at least 5 offloads where every file was copied and verified
- at least 3 days after this version was first launched
- it has been shown fewer than 2 times
- you have not chosen **Support** or **Don’t Ask Again**
- the next ask date is unset or has passed

**Maybe Later** waits 30 days. The note is not shown during a copy.
