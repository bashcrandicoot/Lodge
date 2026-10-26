# Getting started

Home base for your media. Lodge is a universal app for Apple silicon and Intel Macs, on macOS 14 or later. This is the path from the download to the first offload. The [user guide](user-guide.md) covers every control.

## Download Lodge

<a href="https://bashframes.gumroad.com/l/lodge"><img src="assets/download-button.png" alt="Download Lodge for Mac" width="320" height="72"></a>

[Download Lodge from Gumroad](https://bashframes.gumroad.com/l/lodge). Open the disk image and drag Lodge to Applications. Pay what you want.

No account, no analytics. Lodge 1.0.0 doesn’t use the network. Copying never uploads anything.

## Open Lodge the first time

Lodge is not notarized, so macOS asks before it will launch.

### macOS 15 Sequoia and later

1. Open Lodge.
2. Click **Done** on the warning.
3. Go to **System Settings > Privacy & Security**.
4. Click **Open Anyway** next to Lodge, and confirm.

### macOS 14 Sonoma

1. Right-click or Control-click Lodge.
2. Choose **Open**.
3. Choose **Open** again.

Closing the window quits Lodge. Leave it open while you work so it can see cards as you insert them.

## Allow access to the card

The first time Lodge reads a card, macOS asks to allow access to files on a removable volume. Choose **Allow**.

If you chose Don’t Allow, turn it back on in **System Settings > Privacy & Security > Files and Folders**.

## Choose a destination

The Destination column starts empty.

1. Click **Choose Folder…**, or drop a folder from Finder onto Destination.
2. Lodge remembers that folder.
3. Open the folder’s menu and choose **Add “Folder” to Favorites** (it uses the folder’s name) to keep it in the list you switch from. Each favorite stores a bookmark, so Lodge can still find the folder if you rename or move it. **Settings > Destinations** is the same list: add, rename, reorder, and **Make Default**.
4. Click the folder name to switch favorites, choose another folder, or edit the list. A favorite on a drive that is unplugged says **Not connected** and cannot be selected.

The next time Lodge opens, it selects the default favorite when that drive is connected. When it is not, Lodge selects the favorite you used last if that drive is connected, and otherwise any other connected favorite.

## Offload

1. Insert a memory card, or plug in a card reader. Lodge lists removable drives mounted under `/Volumes`. A card that was already in when Lodge opened is included. The window comes forward.
2. If more than one card is mounted, click the one you want in the Card column.
3. In Media, enter a **Project** name when the template uses `{project}`. The default template does. “Beach Shoot” is saved as `BeachShoot`. Choose a **Camera** when the template uses `{camera}`.
4. Read the live names in the list. They are the names Lodge will write.
5. Click **Offload N Files**.

While it runs, the bar shows the current file, how many are done, the bytes copied, the time left, and a **Verifying** state. **Cancel** stops the rest. Each finished file is checked with SHA-256 before it keeps its final name.

When the offload succeeds, Lodge can play the Glass sound (on by default). Then you can **Show in Finder**, **Eject Card**, or **Done**. If every file on the card has a verified copy that is still in the destination, **Format Card…** is there too, and the card shows **Ready to format**.

The card’s own line reads **54 new files · 5 ignored** before and during the copy, and **57 copied · 5 ignored** once it has finished. The numbers follow the card. Ignored files are system junk and your ignore list. They are not copied.

## If the Offload button is waiting

The button’s caption is the reason. Common ones:

- **Enter a project name**
- **Choose a camera**
- **Choose a destination folder**
- **Not enough space**, with the size it needs and the size free
- **Everything on this card is already offloaded**
- **Insert a card to begin**

## Build from source

The download above is the way to install Lodge. If you want to build it yourself, start with [CONTRIBUTING.md](../CONTRIBUTING.md).

For help, write to [bashframes@gmail.com](mailto:bashframes@gmail.com).

© 2026 BashFrames
