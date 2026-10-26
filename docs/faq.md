# FAQ

Short answers. The [user guide](user-guide.md) has the detail, and [Getting started](getting-started.md) covers the download.

## Which Mac do I need?

macOS 14 Sonoma or later. Lodge is a universal app for Apple silicon and Intel Macs.

## Does Lodge change the card while it copies?

The copy only reads the card. Each file is written on the destination, checked with SHA-256, and only then given its final name. **Format Card…** is the command that erases a card, and it asks first.

## What does “verified” mean?

Lodge hashes the file as it reads it from the card, writes a `<name>.lodge-partial` file, reads that file back, and hashes it again. The two SHA-256 values have to match. The partial file is then renamed. If they do not match, the partial file is deleted and that file is counted as failed.

## What does “54 new files · 5 ignored” mean?

That is the line on the selected card before and during an offload. **57 copied · 5 ignored** is the same line after the offload finishes. The numbers follow your card. Ignored items are system files and your ignore list. They are not copied, and they do not stop the card being ready to format.

## Why is a copy “missing at destination”?

The ledger has the file, and the copy is gone or its size has changed. Lodge will not copy it again until you choose **Re-offload Missing Copies**, **Re-offload This File**, or **Re-offload Everything on This Card…**. New copies never overwrite what is already in the folder.

## When can I format the card?

When every file has a verified copy that is still at the destination, at the same size, the card shows **Ready to format**. Skipped short clips are called out separately: the button reads **Format and Discard N Short Clips**, so it is clear those takes have no copy. Ignored system files do not block the badge. Cancel is the default in the confirmation.

Lodge formats exFAT, FAT32, and FAT16, and keeps the card’s name. Other formats are left for the camera. It also refuses the startup disk, a drive that is part of the Mac, and the drive your destination folder is on.

## What is the difference between a preset and Examples?

**Examples**, in Settings > Naming, fills in a folder template and a file template. A preset saves the whole setup: destination, templates, camera, short clips, quick dump, and file rules. After you change that setup, the menu says **Edited**. The preset menu sits at the top right of the window, and the window title is hidden. When a card is inserted, Lodge selects the camera you last used with that card, by its volume UUID or its name.

## How do I change the folders in Layout?

Once a card is scanned, **Layout** in Destination shows the folders Lodge will make, including a folder for each extension, then **Proxies** and **Sidecars** when those files are in the plan. Drag a level to move it, or drag or click a token from **Add a level**. The header says **Drag to rearrange**. **Expand All** and **Collapse All** sit beside **Layout**. Expand All’s help reads **Expand All (or Option-click a triangle)**. Collapse All’s label is **Collapse all folders**. A level quick dump removes stays in the tree, struck through.

## What is quick dump?

**Quick dump** takes `{project}` out of the templates so there is nothing to type. An ⓘ beside the checkbox says: Skips the project name and dumps all the footage straight into a dated folder. `{date}/{project}` and `{date}_{project}_{seq}` become `{date}` and `{date}_{seq}`. Numbering carries on, and each file type still gets its own folder.

## What does the short-clip slider do?

**Skip videos shorter than** runs from **Off** to **30 s**. It starts at **5 s**. The stepper next to it goes up to 60 seconds. Clips under the limit stay on the card with their sidecars until you choose **Include Anyway** or **Include All**. Clips whose length cannot be read, such as BRAW and R3D, are always copied.

## Which drives does Lodge see?

Removable or ejectable volumes mounted under `/Volumes`. A card that was already inserted at launch counts. The startup disk does not, and neither does the volume your destination folder is on.

## Why didn’t Lodge ask to import my card?

Lodge asks only while it is running, and only when you are in another app. Keep it running after you close the window with **Settings > General > Menu Bar > Keep Lodge running in the menu bar**. If a Focus or Do Not Disturb is on, macOS holds the notification back: set **Ask with** to **Floating panel**. Lodge also skips drives without camera folders or media, your destination drives, and cards you chose **Don’t ask** for. See [Ask to import](user-guide.md#ask-to-import).

## Why did macOS block Lodge?

Lodge is not notarized.

On macOS 15 Sequoia and later, open Lodge, click **Done**, then go to **System Settings > Privacy & Security**, click **Open Anyway** next to Lodge, and confirm.

On macOS 14 Sonoma, right-click or Control-click Lodge, choose **Open**, then **Open** again.

The first time Lodge reads a card, also allow access to files on a removable volume.

## How do I get help?

Write to [bashframes@gmail.com](mailto:bashframes@gmail.com). If Lodge has been useful, [Support Lodge](https://bashframes.gumroad.com/l/lodge). Pay what you want.

**Help > Contact Support…** opens an email to that address, subject Lodge Support, with the Lodge and macOS versions under your message. **Help > Support Lodge…** and **Lodge > Support Lodge…** open the same page in your browser. **Lodge > About Lodge** says Made by BashFrames, with a link to the same email. Settings > General ends with **Support** and **Support Lodge**.

After five offloads where every file was copied and verified, and at least three days after you first open that version, a short **Support Lodge** note shows up at most twice, and only when Lodge is idle. It never appears during a copy. **Maybe Later** asks once more, 30 days later. **Support Lodge** and **Don’t Ask Again** stop it.

## How do I update Lodge?

**Lodge > Check for Updates…** looks now. The item is dimmed while a check is already running. In Settings > General, under **Updates**, **Automatically check for updates** is on, and **Automatically download and install updates** is off. The second switch is unavailable while automatic checks are off. Lodge checks once a day. Updates are EdDSA-signed through Sparkle.

Lodge 1.0.0 can’t update itself. [Download Lodge from Gumroad](https://bashframes.gumroad.com/l/lodge) once to get 1.0.1. After that, Lodge updates itself.

## How are files sorted into folders?

Files land in the folder the template makes, and then in a folder named for the extension, in capitals: `MP4/`, `ARW/`, `WAV/`, and so on. `.mp4` and `.MP4` share `MP4/`. `.JPG`, `.JPEG`, and `.JPE` share `JPG/`. `.TIF` and `.TIFF` share `TIF/`. An unknown extension still gets a folder. A file with no extension stays in the template folder. With the default file rules, `lrv` and `lrf` go in **Proxies/**, and `thm`, `xml`, and `srt` go in **Sidecars/**, named after their clip. Audio recorded beside a clip, such as `C0001.WAV`, goes in `WAV/` and shares the clip’s new name.

**Flat**, in Settings > Naming, uses an empty folder template. It skips the shoot folders. Each file type still gets its own folder, straight in the destination.

## Does Lodge need a network?

No account, no analytics, and copying never uploads anything. The only time Lodge goes online is a daily check for updates, which you can turn off in Settings > General. The ledger and your settings stay in your Library folder.

## Where do my settings live?

`~/Library/Application Support/Lodge/` holds `ledger.json`, `destinations.json`, `cameras.json`, and `presets.json`. Templates, the theme, and the switches live in Lodge’s preferences.

## Can I use Light mode, or another colour?

Yes. Settings > Appearance. Lodge starts in Dark mode with **Default**: a neutral black and white window, and system-blue controls (or whatever accent you set in System Settings). **Aurora**, **Ocean**, **Twilight**, **Ember**, and **Forest** are optional colour themes. **Light** and **System** are next to **Dark**.

## What if two files would get the same name?

Lodge does not overwrite. With `{seq}` in the template, numbering continues after the highest number already in the shoot folder and every format folder under it. Without `{seq}` or `{original}`, a repeated name gets `_2`, `_3`, and so on.

## What happens the first time I open Lodge?

**Welcome to Lodge** is a short guide to your first preset: destination, folders, naming and safety. It does not show if you already have presets, favorites, or offloads. **Keep Lodge running in the menu bar** is off by default. When it is on, closing the window leaves Lodge running. **Show menu bar icon** and **Open at login** are in Settings > General > Menu Bar. When a card is plugged in while you are in another app, Lodge can ask **Import with Lodge?** as a notification or a floating panel.

## I turned a file type off. Will Format still wait for it?

The type switches decide what the next offload copies. **Ready to format** looks at the whole card, not only the types you left on. A photo you excluded still has to be offloaded, or the card is not ready. Ignored names are the exception: they are never copied, and they do not block the badge.
