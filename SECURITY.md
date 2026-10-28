# Security

Lodge 1.0.3 is the supported release.

## Reporting

Please report a vulnerability privately: [Open a security advisory](https://github.com/bashcrandicoot/Lodge/security/advisories/new). You can also write to [bashframes@gmail.com](mailto:bashframes@gmail.com).

Include the macOS version, the Lodge version, and what you observed. Give the maintainers a chance to respond before writing about it in public. A public issue is fine for a crash or a copy that failed. It is the wrong place for a report that would help someone erase a disk or read a card they should not have.

## What Lodge does on your Mac

No account, no analytics, and copying never uploads anything. The only time Lodge goes online is a daily check for updates, which you can turn off in Settings > General. Updates are EdDSA-signed through Sparkle. The support link opens Ko-fi in your browser. Copying, the ledger, favorites, cameras, presets, and settings stay on the Mac, under `~/Library/Application Support/Lodge/` and in Lodge’s preferences.

During an offload Lodge only reads the card. It writes on the destination you chose, to a `<name>.lodge-partial` file, and renames that file after the SHA-256 matches.

**Format Card…** does erase a card. It asks first, with Cancel as the default, and it refuses anything that is not the scanned removable volume: the startup disk, a drive that is part of the Mac, a whole disk rather than a volume, and the drive the destination folder is on. It will format exFAT, FAT32, and FAT16 only. If you believe those checks can be bypassed, that is a security report.

The app is not notarized and is not sandboxed. A build you make yourself is signed to run locally.

On macOS 15 Sequoia and later, open Lodge, click **Done**, then go to **System Settings > Privacy & Security** and click **Open Anyway**. On macOS 14, right-click Lodge and choose **Open**.

[Download Lodge from Ko-fi](https://ko-fi.com/s/fb9fab53be).
