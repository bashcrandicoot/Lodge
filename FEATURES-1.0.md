# Lodge 1.0 feature inventory

Taken from the source at tag `v1.0`, commit `d5d4f9f`. Quoted strings are the ones in that tree. This is not a description of later licensing work.

## Trial and unlock

There is no trial and no unlock flow. A search of that commit finds no license gate, no expiry, and no purchase check in the app. Lodge 1.0 runs without a key.

What can look like a trial is the support note, and it does not lock anything. `SupportPromptPolicy` in `Lodge/SupportPrompt.swift` shows the note only when all of these are true:

- at least 5 offloads where every file was copied and verified (`requiredOffloads = 5`)
- at least 3 days after this version was first launched (`minimumUse = 3 * 24 * 60 * 60`)
- shown fewer than 2 times (`maximumShows = 2`)
- the user has not chosen the "Support Lodge" button or "Don’t Ask Again" (`neverAskAgain`)
- `nextAskDate` is unset or has passed

"Maybe Later" waits 30 days (`laterDelay = 30 * 24 * 60 * 60`). The card is not shown during a copy. The title is "Support Lodge". The body is "Lodge is made by one person at bashframes. If it saves you time, you can chip in on Ko-fi. Thank you!" Buttons: "Don’t Ask Again", "Maybe Later" (Escape), "Support Lodge". "Support Lodge" opens `https://ko-fi.com/bashframes` (`Lodge/Support.swift`).

## Import flow

Lodge does not copy on plug-in. The prompt asks, and the user still presses Offload.

`ImportPromptPolicy.verdict` (`Lodge/ImportPromptPolicy.swift`) prompts only when all of these hold:

- the volume path is under `/Volumes/` and it is not the startup disk
- the volume is local (not a network volume)
- it is not a disk image
- it is pluggable media: removable, or external and ejectable
- it is not a backup volume
- the destination folder is not on that volume
- the user has not chosen "Don’t ask for this card" for that card
- the volume looks like camera media

Camera folders checked include `DCIM`, `PRIVATE/M4ROOT`, `PRIVATE/AVCHD`, `AVCHD`, `XDROOT`, `PRIVATE/XDROOT`, `BPAV`, `CONTENTS`, `MP_ROOT`, `CLIPS001`, `XFAVC`, `PRIVATE/PANA_GRP`, `PRIVATE/CANON`, and `BLACKMAGIC`. A volume also qualifies when media files sit in the top folders.

The same card is not asked twice within the debounce interval. A card plugged in during an offload or a format is queued until that finishes (`Lodge/ImportPrompter.swift`).

The notification title is the card name plus "connected", or " card connected" / " drive connected" when the name does not already end in card, drive, ssd, or disk. The body is "Import with Lodge?". The actions are "Import", "Ignore", and "Don’t Ask for This Card" (`Lodge/ImportPrompter.swift`).

Lodge shows the floating panel (`Lodge/ImportPromptPanel.swift`) when Ask with is "Floating panel", when notification permission is still undecided, when notifications are off, when alerts are disabled, or when the alert style is None. Posting the notification can also fail and fall back to the panel. The panel uses the same title and the body "Import with Lodge?", with buttons "Import", "Ignore", and "Don’t ask for this card". It is a nonactivating panel (`styleMask` includes `.nonactivatingPanel`) and does not take the keyboard, so Return does not press Import. The buttons are a click.

"Import" opens Lodge with that card selected. Nothing is copied until Offload.

The ask can be turned off. While detection is paused the menu says "Resume Detection". Debug builds have Menu bar ▸ Test Import Prompt (`testPrompt`, compiled only inside `#if DEBUG`). Its failures use these strings:

- "Lodge isn't ready yet."
- "No cards or drives are connected."
- "“Ask to import” is off in Settings ▸ General ▸ Menu Bar."
- "Detection is paused (menu bar ▸ Resume Detection)."
- "None of the connected cards or drives qualify for a prompt. Details are in Console (subsystem com.sebastianphillips.Lodge, category ImportPrompt)."

## Verify

`Copier` (`Lodge/Copier.swift`) copies one file like this:

1. Write `"<final name>.lodge-partial"` (`partialSuffix = ".lodge-partial"`), hashing the source with SHA-256 as it is read, in 8 MB chunks.
2. Read the partial file back from disk and hash it.
3. If the hashes match, rename the partial file to the final name. If they do not, delete the partial file.

The card is only read. Failures shown to the user:

- "`<name>` already exists — not overwriting it."
- "Couldn’t create `<name>` in the destination."
- "Checksum mismatch for `<name>`. The copy was deleted."

While ready, the bar says "Ready. Every file is verified with SHA-256 after copying." (`Lodge/OffloadBar.swift`). During the copy the stage label is "Copying", then "Verifying". The button help is "Copy and verify the new files".

Finish titles (`Lodge/OffloadBar.swift`): "Offload Complete", "Finished with Problems", "Offload Cancelled". The subtitle is "`<copied>` copied · `<skipped>` skipped · `<failed>` failed" (`OffloadFormatting.summaryLine` in `Lodge/FlowLogic.swift`). If the card is gone after eject, that line gains " — card ejected, safe to remove".

## Rename rules

Default templates (`Lodge/NamingTemplate.swift`):

- folder: `{date}/{project}`
- file: `{date}_{project}_{seq}`

The built-in preset name is "Date / Project".

Tokens and what they become:

| Token | Meaning in the template editor | Rendered value |
| --- | --- | --- |
| `{project}` | "Project name" | the project field |
| `{camera}` | "Selected camera" | the selected camera |
| `{date}` | "Capture date (2026-10-25)" | `yyyy-MM-dd` |
| `{year}` | "Year (2026)" | `yyyy` |
| `{month}` | "Month (10)" | `MM` |
| `{day}` | "Day (25)" | `dd` |
| `{time}` | "Capture time (143005)" | `HHmmss` |
| `{type}` | "Video, Photo, Audio or Other" | "Video", "Photo", "Audio", or "Other" |
| `{card}` | "Card (volume) name" | the volume name |
| `{original}` | "Original file name, no extension" | the source name, made safe |
| `{seq}` | "Sequence number (0001); {seq:3} for 001" | at least 4 digits, unless `{seq:N}` says otherwise |
| `{ext}` | "File extension (mp4)" | the extension, lowercased |

`NameRules.safeComponent` replaces `/`, `:`, `\`, `*`, `?`, `"`, `<`, `>`, `|`, and control characters with `-`, trims spaces, and strips leading dots so a name is not a hidden file.

`Renamer.sanitizeName` (`Lodge/Renamer.swift`) is the project-name cleanup: letters, digits, and `-` stay; other characters split words; each word is capitalized ("beach day" becomes "BeachDay"); the result is at most 60 characters and is trimmed of leading and trailing `-`.

Sequence numbers continue after the highest number already in the destination folder. A file that is already at the final path is not overwritten (the Copier error above).

Proxies (`lrv`, `lrf` by default) go in `Proxies/`. Sidecars (`thm`, `xml`, `srt` by default) go in `Sidecars/`. They keep the clip’s new name. `jpeg` / `jpe` share `jpg`, and `tiff` shares `tif` (`FileRules.aliases` in `Lodge/FileRules.swift`).

## Eject

The manual command is "Eject Card" (`Lodge/CardStageView.swift` and `Lodge/OffloadBar.swift`). After the card is gone the label is "Ejected". The button is disabled while an offload, a format, or an eject is in progress, and on the finish bar it is disabled once `cardRemoved` is set.

Automatic eject runs only when "Eject card after offload" is on and every file verified (`Lodge/AppModel.swift`). The call is `FileManager.unmountVolume` with `.allPartitionsAndEjectDisk`. Failure is "Couldn’t eject `<card name>`: `<system message>`".

The setting’s own caption is "Only when every file was copied and verified." (`Lodge/SettingsView.swift`).

## Free space and read-only

Blocker when the destination is smaller than the copy (`OffloadReadiness.blocker` in `Lodge/FlowLogic.swift`):

"Not enough space: needs `<needed>`, `<available>` free"

`<needed>` and `<available>` are `ByteCountFormatter` file-style strings.

Read-only (`VolumeInfo.readOnlyMessage`):

- no format name: "This drive is read-only, so Lodge can’t write to it — choose another"
- NTFS: "This drive is read-only (NTFS). macOS can’t write to it."
- any other format: "This drive is read-only (`<format>`), so Lodge can’t write to it — choose another"

Recognized format names: "NTFS", "exFAT", "FAT32", "Mac OS Extended", "APFS".

Other destination blockers in the same function:

- "Insert a card to begin"
- "Scanning card…"
- "This card is empty"
- "1 copy is missing at the destination — choose Re-offload" / "`<n>` copies are missing at the destination — choose Re-offload"
- "Only a short clip is left — choose Include Anyway to offload it" / "Only short clips are left — choose Include All Short Clips to offload them"
- "Nothing new in the chosen dates — choose Any date to see everything"
- "Everything on this card is already offloaded"
- "Fix the naming template in Settings"
- "Enter a project name"
- "Choose a camera"
- "Choose a destination folder"
- "The destination folder isn’t connected — choose another"

Space shown on a favorite (`Lodge/DestinationStageView.swift`): "`<bytes>` free". Under the destination: "`<bytes>` available", or "Free space unknown", plus "needs `<bytes>`" when a copy is planned. A favorite that is not mounted says "Not connected".

First-launch drive rows (`OnboardingDrive.spaceText` in `Lodge/Onboarding.swift`):

- "Free space unknown"
- "`<bytes>` free"
- "`<bytes>` free of `<bytes>`"

`VolumeInfo` (`Lodge/FlowLogic.swift`) prefers `volumeAvailableCapacityForImportantUsage` when it is above 0, then `volumeAvailableCapacity`, then `statfs`. A lone 0 from the important-usage figure is not treated as a full disk.

## Report a Bug

Menu item "Report a Bug…" (`Lodge/LodgeApp.swift`) calls `BugReport.compose` (`Lodge/BugReport.swift`). Nothing is sent until the user sends the email. The message goes to `bashframes@gmail.com`.

Subject: "Lodge bug report (version `<version>` build `<build>`)".

Body starts with "What happened?" and one of:

- "(What were you doing, and what went wrong? Steps to make it happen again help a lot.)"
- "(Lodge quit unexpectedly. What were you doing just before?)"

Then "Lodge `<version>` (build `<build>`)", "macOS `<version>`", "Mac: `<model>`, `<chip>`". Paths under the home folder, `/Volumes`, `/Users`, `/private`, `/var`, and `/tmp` are replaced with `<path>`.

When Mail can attach files, the log goes out as `Lodge log.txt` (up to 200 of Lodge’s own lines from the last three days) and a crash report, if there is one, goes out as its own `.txt`. The message body names those files under "Attached:" and does not paste the log. The `mailto:` fallback attaches nothing. It puts the log in the body under "Lodge’s recent log:" (or "(nothing logged recently)"), cut to fit. If there was a crash report, that fallback adds "(The crash report couldn’t be attached. It’s in Console ▸ Crash Reports, under Lodge.)".

On the next launch, if a new `Lodge-….ips` or `Lodge_….crash` report is in Diagnostic Reports, the alert is "Lodge quit unexpectedly last time. Send a crash report?" The detail is "This opens a new email to bashframes with the crash report and Lodge’s recent log attached. File, card and drive names are left out. You can read it over before sending." Buttons: "Send Report" and "Not Now". It is not offered at login, and each report is offered once.

## Settings and defaults

Stored in Lodge’s preferences (`Lodge/Settings.swift`) unless noted. Missing keys use these defaults.

| Setting | Default | Where it is set |
| --- | --- | --- |
| Destination folder | none | chosen by the user; legacy path key `destinationPath` |
| "Eject card after offload" | off | `ejectAfterOffload` |
| Folder template | `{date}/{project}` | `NamingTemplates.defaultFolder` |
| File template | `{date}_{project}_{seq}` | `NamingTemplates.defaultFile` |
| Last project | empty | |
| Recent projects | empty, at most 6 | `maxRecentProjects` |
| Files to offload | Video, Photos, Audio, and Other all on | excluded list starts empty |
| "Play a sound when an offload finishes" | on | |
| "Skip videos shorter than" | on, 5 seconds | range 1...60; the slider stops at 30 and Off is 0 (`Lodge/PresetViews.swift`) |
| Theme | "Default" (saved id `default`) | unknown saved names, including `comet` and `graphite`, become Default (`Lodge/Theme.swift`) |
| Appearance | "Dark" | choices "System", "Light", "Dark" |
| "Show files as" | "List" | other choice "Grid" (`Lodge/Thumbnails.swift`) |
| "Show thumbnails in the list" | off | |
| Quick dump | off | |
| Dates | "Any date" | also "Today", "Last 7 days", "Custom range" (`Lodge/DateFilter.swift`) |
| "Keep Lodge running in the menu bar" | off | |
| "Ask to import when a card or drive is plugged in" | on | |
| "Show menu bar icon" | on | only shown while menu bar mode is on |
| "Ask with" | "Notification" | other choice "Floating panel" |
| "Open at login" | off | `SMAppService` status, not a preference bool (`Lodge/MenuBar.swift`) |
| Don’t ask for these cards | empty | |
| File rules | proxies `lrv`, `lrf`; sidecars `thm`, `xml`, `srt`; ignore `.DS_Store`, `._*`, `.Spotlight-V100`, `.Trashes`, `.fseventsd`, `.TemporaryItems`, `Thumbs.db` | `FileRules.standard` |
| Updates: automatic check | on | `SUEnableAutomaticChecks` in `Lodge/Info.plist` |
| Updates: check interval | 86400 seconds (once a day) | `SUScheduledCheckInterval` |
| Updates: automatic download | off | not set in Info.plist; the switch is "Automatically download and install updates" (`Lodge/Updates.swift`) |

Settings tabs are General, Appearance, Presets, Destinations, Naming, Files, and Cameras (`Lodge/SettingsView.swift`).

Other General strings: "Files to Offload", "Short Clips", "After Offload", "Menu Bar", "Updates". The hidden-icon hint says quit with ⌘Q. The menu-bar hint includes "Allow Lodge in System Settings ▸ General ▸ Login Items."

Date filter help (`Lodge/DateFilter.swift`): "Copies only files from these days, by the date each file was created (or last changed, if the card doesn’t record that). Sidecars and proxies go with their clip. Everything else stays on the card."

Folder panel (`Lodge/Settings.swift`): message "Choose the folder Lodge should copy your media into." Prompt button "Choose".

Updates footer (`Lodge/Updates.swift`): "Lodge checks for a new version once a day. You can also choose Lodge ▸ Check for Updates… any time."

## Keyboard shortcuts

| Shortcut | What it does | Source |
| --- | --- | --- |
| ⌘, | Settings. Also the menu bar item’s key. The setup done screen draws a "⌘ ," keycap. | `Lodge/LodgeApp.swift`, `Lodge/MenuBar.swift`, `Lodge/ContentView.swift`, `Lodge/OnboardingDone.swift` |
| ⌘Q | Quit. The menu bar item’s key is `q`. The hidden-icon hint says "quit it from there with ⌘Q." | `Lodge/MenuBar.swift`, `Lodge/SettingsView.swift` |
| ⌘-drag | Drag the menu bar icon out to turn "Show menu bar icon" off. | `Lodge/MenuBar.swift` |
| Return (`.defaultAction`) | Offload, Done, "Get started", and "Offload with `<preset>`". The import panel is nonactivating, so Return does not press its Import button. | `Lodge/OffloadBar.swift`, `Lodge/OnboardingView.swift`, `Lodge/OnboardingDone.swift`, `Lodge/ImportPromptPanel.swift` |
| Escape (`.cancelAction`) | "Cancel" during an offload. "Maybe Later" on the support note. The support note’s other button is "Support Lodge". | `Lodge/OffloadBar.swift`, `Lodge/SupportPrompt.swift` |
| Return | On the format confirmation, "Cancel" (`keyEquivalent` `\r`). "Format" has no key equivalent. | `Lodge/FormatViews.swift` |
| Return | "Re-offload Everything" and "Forget History" are two alerts (`Lodge/ReoffloadAlert.swift`). On "Re-offload everything on “`<card>`”?", the first button is "Re-offload Everything" and the second is "Cancel". On "Forget the offload history of “`<card>`”?", "Cancel" is Return and "Forget History" has an empty key equivalent. | `Lodge/ReoffloadAlert.swift` |
| Space | Quick Look on the selection. Space while Quick Look is open closes it. | `Lodge/ClipsStageView.swift`, `Lodge/MediaPreview.swift` |
| Up, Down, Left, Right | Move the selection in the list or grid. | `Lodge/ClipsStageView.swift` |
| Escape | Clear the selection. | `Lodge/ClipsStageView.swift` |
| ⌘-click | Toggle a file in the selection. | `Lodge/ClipsStageView.swift`, `Lodge/MediaPreview.swift` |
| Shift-click | Extend the selection. | `Lodge/ClipsStageView.swift` |
| Double-click | Quick Look. | `Lodge/ClipsStageView.swift` |

The list and grid accessibility hint is "Press Space to preview the selected file with Quick Look". The Settings toolbar help is "Settings (⌘,)".
