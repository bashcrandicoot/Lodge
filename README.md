<p align="center">
  <picture>
    <source media="(prefers-color-scheme: light)" srcset="docs/assets/lodge-header-light.png">
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/lodge-header-dark.png">
    <img alt="Lodge. Media made easy." src="docs/assets/lodge-header-dark.png" width="960">
  </picture>
</p>

<p align="center">
  Lodge is a native Mac app for offloading camera memory cards. It copies video, photos, audio, and the small files that belong with them, checks every copy, and names the files from a template you set.
</p>

<p align="center">Formerly SnapDrop.</p>

<p align="center">On its first launch, Lodge copies over SnapDrop’s data and settings. The originals stay where they are.</p>

<p align="center">
  <a href="https://github.com/bashcrandicoot/Lodge/releases/latest"><img alt="macOS 14 or later" src="https://img.shields.io/badge/macOS-14%2B-3A3A3C?style=flat&logo=apple&logoColor=white"></a>
  <a href="https://www.swift.org"><img alt="Swift 5" src="https://img.shields.io/badge/Swift-5-F05138?style=flat&logo=swift&logoColor=white"></a>
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/License-MIT-0A84FF?style=flat"></a>
  <a href="https://github.com/bashcrandicoot/Lodge"><img alt="Vibe Coded" src="https://img.shields.io/badge/-Vibe%20Coded-0A84FF?style=flat"></a>
</p>

<p align="center">
  <a href="https://github.com/bashcrandicoot/Lodge/releases/latest"><strong>Download Lodge 1.0.0</strong></a>
  &nbsp;·&nbsp;
  <a href="docs/getting-started.md">Getting started</a>
  &nbsp;·&nbsp;
  <a href="docs/user-guide.md">User guide</a>
  &nbsp;·&nbsp;
  <a href="https://bashcrandicoot.github.io/Lodge/">Website</a>
</p>

<p align="center">
  <img alt="Lodge ready to offload a card, Default theme, Dark mode" src="docs/assets/screenshots/ready-dark.png" width="880">
</p>

## Offload a card

1. Insert a memory card, or a card reader. Lodge notices removable drives mounted under `/Volumes`, including cards that were already in when it opened, and brings its window forward.
2. Choose a destination folder. Favorites are one click away, and you can drop a folder from Finder onto Destination.
3. Name the shoot if your template asks for a project, then click **Offload**. Lodge copies the new files, verifies each one with SHA-256, and leaves the card alone.

The card’s line reads **54 new files · 5 ignored** before and during an offload, and **57 copied · 5 ignored** when that offload has finished. Ignored items are system files and anything on your ignore list. They are counted, and they are not copied.

## What you can do

- **Verified copies.** Each file is written as `<name>.lodge-partial`, read back, and hashed. When the SHA-256 matches the card, Lodge renames it to the final name. A mismatch deletes the partial file and reports a failure. Nothing on the card is changed.
- **Names from a template.** The default is `{date}/{project}` and `{date}_{project}_{seq}`. Settings > Naming has an **Examples** menu, token buttons, and a live example. `{project}` is the shoot or job name.
- **A ledger of what was copied.** Lodge remembers each verified file in `~/Library/Application Support/Lodge/ledger.json`. The same card again copies only what is new. If a copy is missing or its size has changed, the Media panel warns you, in orange, and offers **Re-offload**.
- **Ready to format.** When every file has a verified copy that is still at the destination, the card shows a green **Ready to format** badge, and **Format Card…** is available. Cancel is the default. Lodge keeps exFAT, FAT32, or FAT16, and the card’s name.
- **Short clips.** **Skip videos shorter than** runs from **Off** to **30 s**. The default is **5 s**. A stepper beside the slider goes up to 60 seconds. Skipped clips stay on the card with their sidecars until you choose **Include Anyway** or **Include All**.
- **Presets.** The toolbar menu saves a whole setup: destination, templates, camera, short clips, quick dump, and file rules. After you change something, the menu says **Edited** and offers to update that preset. Manage them in Settings > Presets.
- **Quick dump.** **Quick dump: skip project name** takes `{project}` out of the templates, so there is nothing to type. Numbering carries on from the files already in the folder.
- **Drag and drop.** Drop a Finder folder on Destination, or on the Layout tree, to copy there. In the tree, drag a folder level to move it, or drag a token on to add one. A drop that Lodge accepts gives a light click on a Force Touch trackpad.
- **File rules.** Proxy extensions (default `lrv`, `lrf`) go in a **Proxies** folder. Sidecar extensions (default `thm`, `xml`, `srt`) go in a **Sidecars** folder. Both keep the clip’s new name. The ignore list is never copied.
- **Themes.** Lodge opens in Dark mode with the **Default** theme: a neutral black window and system-blue controls. **Aurora**, **Ocean**, **Twilight**, **Ember**, and **Forest** are optional colour themes in Settings > Appearance.
- **Motion.** A finished offload draws its checkmark and counts the copied files up. Inserting a card glows the card panel. Rows and thumbnail tiles lift under the pointer. The **Ready to format** badge glows when it appears. Turn on Reduce Motion in System Settings and Lodge keeps still.

The full tour is in the [user guide](docs/user-guide.md). Questions are in the [FAQ](docs/faq.md). This release is [1.0.0](docs/changelog.md).

| Ready | Copying | Finished |
| --- | --- | --- |
| ![Ready to offload](docs/assets/screenshots/ready-dark.png) | ![Copying and verifying](docs/assets/screenshots/running-dark.png) | ![Offload finished, card ready to format](docs/assets/screenshots/finished-dark.png) |

## Install

Download **Lodge 1.0.0** from the [latest release](https://github.com/bashcrandicoot/Lodge/releases/latest). The release assets are `Lodge-1.0.0.dmg` and `Lodge-1.0.0.zip`.

Lodge is not notarized.

- **macOS 15 and later.** Open Lodge, click **Done** on the warning, then go to **System Settings > Privacy & Security** and click **Open Anyway**.
- **macOS 14.** Right-click Lodge, choose **Open**, then **Open** again.

The first time Lodge reads a card, macOS asks for access to files on a removable volume. Choose **Allow**. Step by step: [Getting started](docs/getting-started.md).

Building from source is covered in [CONTRIBUTING.md](CONTRIBUTING.md).

## Documentation

- [Getting started](docs/getting-started.md)
- [User guide](docs/user-guide.md)
- [FAQ](docs/faq.md)
- [Changelog](docs/changelog.md)
- [Contributing](CONTRIBUTING.md)
- [Security](SECURITY.md)

## License

MIT. See [LICENSE](LICENSE). Copyright © 2026 Sebastian Phillips.
