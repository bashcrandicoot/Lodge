# FAQ

Short answers. The [user guide](user-guide.md) has the detail, and [Getting started](getting-started.md) covers the download.

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

**Examples**, in Settings > Naming, fills in a folder template and a file template. A preset saves the whole setup: destination, templates, camera, short clips, quick dump, and file rules. After you change that setup, the menu says **Edited**.

**Coming in the next update.** The preset menu sits at the top right of the window, and the window title is hidden. In Lodge 1.0.0 the preset menu is in the center of the toolbar, and the title reads Lodge.

## How do I change the folders in Layout?

Once a card is scanned, **Layout** in Destination shows the folders Lodge will make, including **Proxies** and **Sidecars** when those files are in the plan. In Lodge 1.0.0, drag a level to move it, or drag or click a token from **Add a level**. The header says **Drag to rearrange**. One example file name is shown, and extra folders appear as a line such as **+ 2 more folders**. A level quick dump removes stays in the tree, struck through.

**Coming in the next update.** **Expand All** and **Collapse All** open or close the tree, and Option-click a triangle does the same for everything inside that folder. Drop a token on the left or right side of a name to put tokens side by side, such as `{project}_{date}`. The separator can be an underscore, a hyphen, a space, or nothing. A folder’s files can fold into one line, the first name with **+ N more** under it.

## What is quick dump?

**Quick dump: skip project name** takes `{project}` out of the templates so there is nothing to type. `{date}/{project}` and `{date}_{project}_{seq}` become `{date}` and `{date}_{seq}`. Numbering carries on from the folder.

## What does the short-clip slider do?

**Skip videos shorter than** runs from **Off** to **30 s**. It starts at **5 s**. The stepper next to it goes up to 60 seconds. Clips under the limit stay on the card with their sidecars until you choose **Include Anyway** or **Include All**. Clips whose length cannot be read, such as BRAW and R3D, are always copied.

## Which drives does Lodge see?

Removable or ejectable volumes mounted under `/Volumes`. A card that was already inserted at launch counts. The startup disk does not, and neither does the volume your destination folder is on.

## Why did macOS block Lodge?

Lodge is not notarized.

On macOS 15 Sequoia and later, open Lodge, click **Done**, then go to **System Settings > Privacy & Security**, click **Open Anyway** next to Lodge, and confirm.

On macOS 14 Sonoma, right-click or Control-click Lodge, choose **Open**, then **Open** again.

The first time Lodge reads a card, also allow access to files on a removable volume.

## How do I get help?

Write to [bashframes@gmail.com](mailto:bashframes@gmail.com). If Lodge has been useful, you can [Support Lodge](https://bashframe.gumroad.com/l/lodge).

**Coming in the next update.** **Help > Contact Support…** and **Support Lodge…** are in the Help menu. After a few offloads, Lodge shows a quiet tip once. You can dismiss it.

## Does Lodge need a network?

No. There is no account and no upload. The ledger and your settings stay in your Library folder.

## Where do my settings live?

`~/Library/Application Support/Lodge/` holds `ledger.json`, `destinations.json`, `cameras.json`, and `presets.json`. Templates, the theme, and the switches live in Lodge’s preferences.

## Can I use Light mode, or another colour?

Yes. Settings > Appearance. Lodge starts in Dark mode with **Default**: a neutral black and white window, and system-blue controls (or whatever accent you set in System Settings). **Aurora**, **Ocean**, **Twilight**, **Ember**, and **Forest** are optional colour themes. **Light** and **System** are next to **Dark**.

## What if two files would get the same name?

Lodge does not overwrite. With `{seq}` in the template, numbering continues after the highest number already in the folder. Without `{seq}` or `{original}`, a repeated name gets `_2`, `_3`, and so on.

## I turned a file type off. Will Format still wait for it?

The type switches decide what the next offload copies. **Ready to format** looks at the whole card, not only the types you left on. A photo you excluded still has to be offloaded, or the card is not ready. Ignored names are the exception: they are never copied, and they do not block the badge.
