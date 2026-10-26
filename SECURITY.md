# Security

Lodge 1.0.0 is the supported release.

## Reporting

Please report a vulnerability privately: [Open a security advisory](https://github.com/bashcrandicoot/Lodge/security/advisories/new).

Include the macOS version, the Lodge version, and what you observed. Give the maintainers a chance to respond before writing about it in public. A public issue is fine for a crash or a copy that failed. It is the wrong place for a report that would help someone erase a disk or read a card they should not have.

## What Lodge does on your Mac

Lodge does not connect to the network. Copying, the ledger, favorites, cameras, presets, and settings stay on the Mac, under `~/Library/Application Support/Lodge/` and in Lodge’s preferences.

During an offload Lodge only reads the card. It writes on the destination you chose, to a `<name>.lodge-partial` file, and renames that file after the SHA-256 matches.

**Format Card…** does erase a card. It asks first, with Cancel as the default, and it refuses anything that is not the scanned removable volume: the startup disk, a drive that is part of the Mac, a whole disk rather than a volume, and the drive the destination folder is on. It will format exFAT, FAT32, and FAT16 only. If you believe those checks can be bypassed, that is a security report.

The app is not notarized and is not sandboxed. A build you make yourself is signed to run locally. Download Lodge 1.0.0 from the [v1.0.0 release](https://github.com/bashcrandicoot/Lodge/releases/tag/v1.0.0).
