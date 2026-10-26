<p align="center">
  <picture>
    <source media="(prefers-color-scheme: light)" srcset="docs/assets/lodge-header-light.png">
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/lodge-header-dark.png">
    <img alt="Lodge. Home base for your media. A log cabin at night, with pines and mountains." src="docs/assets/lodge-header-dark.png" width="960">
  </picture>
</p>

<h1 align="center">From card to calm.</h1>

<p align="center">
  Lodge gets your footage off camera cards safely, checked and neatly named.
</p>

<p align="center">
  Lodge is a universal app. It runs on Apple silicon and Intel Macs, on macOS 14 or later.
</p>

<p align="center">Formerly SnapDrop. On its first launch, Lodge copies SnapDrop’s data and settings and leaves the originals where they are. Anything Lodge already has is kept.</p>

<p align="center">
  <a href="https://github.com/bashcrandicoot/Lodge/releases/tag/v1.0.0"><img alt="macOS 14 or later" src="https://img.shields.io/badge/macOS-14%2B-3A3A3C?style=flat&logo=apple&logoColor=white"></a>
  <a href="https://www.swift.org"><img alt="Swift 5" src="https://img.shields.io/badge/Swift-5-F05138?style=flat&logo=swift&logoColor=white"></a>
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/License-MIT-0A84FF?style=flat"></a>
  <a href="https://github.com/bashcrandicoot/Lodge"><img alt="Vibe Coded" src="https://img.shields.io/badge/-Vibe%20Coded-0A84FF?style=flat"></a>
</p>

<p align="center">
  <img alt="Lodge in Dark mode, ready to offload a memory card. Card, Media, and Destination sit left to right, and the Offload button runs along the bottom." src="docs/assets/screenshots/ready-dark.png" width="880">
</p>

## Key features

Lodge 1.0.0 is the download below. **Coming in the next update** marks anything newer than that download. Where 1.0.0 works differently, the note says how. That update also adds **Help > Contact Support…** and **Support Lodge…**, and a quiet tip after a few offloads that you can dismiss.

- **Verified copies.** Each file is written as `<name>.lodge-partial`, read back, and hashed. When the SHA-256 matches the card, Lodge renames it to the final name. A mismatch deletes the partial file and reports a failure. The card is only read.
- **Names from a template.** The default is `{date}/{project}` and `{date}_{project}_{seq}`. In Settings > Naming the menu is **Examples**: ready-made folder and file pairs, plus token buttons and a live example. `{project}` is the shoot or job name.
- **A ledger of what was copied.** Lodge remembers each verified file in `~/Library/Application Support/Lodge/ledger.json`. The same card again copies only what is new. If a copy is missing or its size has changed, Media warns you, in orange, and offers **Re-offload**.
- **Ready to format.** When every file has a verified copy that is still at the destination, the card shows a green **Ready to format** badge, and **Format Card…** is available. Cancel is the default. Lodge keeps exFAT, FAT32, or FAT16, and the card’s name.
- **Short clips.** **Skip videos shorter than** runs from **Off** to **30 s**. The default is **5 s**. A stepper beside the slider goes up to 60 seconds. Skipped clips stay on the card with their sidecars until you choose **Include Anyway** or **Include All**.
- **Presets.** A preset saves a whole setup: destination, templates, camera, short clips, quick dump, and file rules. After you change something, the menu says **Edited** and offers to update that preset. Manage them in Settings > Presets. **Coming in the next update.** The preset menu sits at the top right of the window, just left of **Recent Offloads** and **Settings**, and the window title is hidden. In Lodge 1.0.0 the preset menu is in the center of the toolbar, and the title reads Lodge.
- **Quick dump.** **Quick dump: skip project name** takes `{project}` out of the templates, so there is nothing to type. Numbering carries on from the files already in the folder.
- **Proxies and sidecars.** A `.lrv` file is a low-resolution proxy. Lodge does not copy it as video. With the default file rules, `lrv` and `lrf` go in a **Proxies** folder, and `thm`, `xml`, and `srt` go in a **Sidecars** folder. Both keep the clip’s new name. Lodge never copies the ignore list, or system junk such as `recycler` and `recycled`.
- **Favorites.** On launch, Lodge selects the default favorite when that drive is connected, then the last-used favorite if that drive is connected, then any other connected favorite.
- **Themes.** Lodge opens in Dark mode with the **Default** theme: a neutral black window and system-blue controls. **Aurora**, **Ocean**, **Twilight**, **Ember**, and **Forest** are optional colour themes in Settings > Appearance.
- **Motion.** A finished offload draws its checkmark and counts the copied files up. Inserting a card glows the card panel. Rows and thumbnail tiles lift under the pointer. The **Ready to format** badge glows when it appears. Turn on Reduce Motion in System Settings and Lodge keeps still.

### Layout

Once a card is scanned, **Layout** in Destination shows the folders the offload will make, including **Proxies** and **Sidecars** when those files are in the plan. Drop a Finder folder on Destination, or on the tree, to copy there.

In Lodge 1.0.0 you drag a level to rearrange it, or drag a token from **Add a level** onto the tree. Click a token to add it at the end. The header says **Drag to rearrange**. Hover a level to remove it. The tree shows one example file name, and extra folders appear as a line such as **+ 2 more folders**. A level that quick dump removes is struck through and tagged **Quick dump**.

**Coming in the next update.** **Expand All** and **Collapse All** open or close the tree. Option-click a triangle does the same for everything inside that folder. Drop a level or a token on the left or right side of a folder’s name to put the tokens side by side, such as `{project}_{date}`. The separator is **Underscore**, **Hyphen**, **Space**, or **None**. When a folder holds more than one file, they start as one line: the first name, with **+ N more** under it.

The card’s line reads **54 new files · 5 ignored** before and during an offload, and **57 copied · 5 ignored** when that offload has finished. Ignored items are system files and anything on your ignore list. They are counted, and they are not copied.

| Ready | Copying | Finished |
| --- | --- | --- |
| ![The Lodge window in Dark mode before an offload, with a card selected, file names previewed in Media, a destination folder chosen, and Offload ready along the bottom.](docs/assets/screenshots/ready-dark.png) | ![Lodge copying files from a card. The offload bar shows the file in progress, how far through the batch the copy is, and Cancel.](docs/assets/screenshots/running-dark.png) | ![A finished Lodge offload. The card shows the green Ready to format badge, and the bar summarizes how many files were copied.](docs/assets/screenshots/finished-dark.png) |

## Download Lodge 1.0.0

Download **Lodge 1.0.0** from the [v1.0.0 release](https://github.com/bashcrandicoot/Lodge/releases/tag/v1.0.0).

- [Lodge-1.0.0.dmg](https://github.com/bashcrandicoot/Lodge/releases/download/v1.0.0/Lodge-1.0.0.dmg) — open the disk image and drag Lodge to Applications.
- [Lodge-1.0.0.zip](https://github.com/bashcrandicoot/Lodge/releases/download/v1.0.0/Lodge-1.0.0.zip) — unzip it and move Lodge to Applications.

Lodge is not notarized. The first time you open it:

- **macOS 15 Sequoia and later.** Open Lodge, click **Done** on the warning, then go to **System Settings > Privacy & Security**, click **Open Anyway** next to Lodge, and confirm.
- **macOS 14 Sonoma.** Right-click or Control-click Lodge, choose **Open**, then **Open** again.

The first time Lodge reads a card, macOS asks for access to files on a removable volume. Choose **Allow**.

## Getting started

1. Move Lodge to Applications and open it, using the steps above if macOS stops you.
2. Click **Choose Folder…** in Destination, or drop a folder from Finder. Lodge remembers that folder. To keep it in the list you switch from, open the folder’s menu and choose **Add “Folder” to Favorites**.
3. Insert a memory card, or a card reader. Lodge notices removable drives mounted under `/Volumes`, including a card that was already in when it opened, and brings its window forward.
4. Name the shoot if your template asks for a project, then click **Offload**.

The next time Lodge opens, it selects the default favorite when that drive is connected, then the last-used favorite if that drive is connected, then any other connected favorite. Closing the window quits Lodge.

The longer path, including what to do if Offload is waiting, is in [Getting started](docs/getting-started.md).

## Documentation

- [Getting started](docs/getting-started.md)
- [User guide](docs/user-guide.md)
- [FAQ](docs/faq.md)
- [Changelog](docs/changelog.md)
- [Website](https://bashcrandicoot.github.io/Lodge/)
- [Contributing](CONTRIBUTING.md)
- [Security](SECURITY.md)

## Support

Lodge is made by BashFrames. For help, write to [bashframes@gmail.com](mailto:bashframes@gmail.com).

If Lodge has been useful, you can [Support Lodge](https://bashframe.gumroad.com/l/lodge).

## License

MIT. See [LICENSE](LICENSE). © 2026 BashFrames.
