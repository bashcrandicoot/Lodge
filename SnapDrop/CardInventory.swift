import Foundation

/// Every file on a card, sorted by what the ledger knows about it.
///
/// Built once per scan (off the main thread, because it checks the destination copies exist)
/// and again after each offload.
struct CardInventory: Equatable, Sendable {
    /// Never offloaded (no ledger entry).
    var new: [Clip] = []
    /// Offloaded, and the verified copy is still at the destination with the right size.
    var offloaded: [Clip] = []
    /// Offloaded, but the copy is gone or has a different size now ("Missing copy").
    var missing: [Clip] = []
    /// The deepest folder that holds all the existing copies.
    var copiesFolder: String?

    var all: [Clip] { new + offloaded + missing }
    var fileCount: Int { new.count + offloaded.count + missing.count }

    /// Sorts `files` using the newest ledger entry for each one. `fileSize` returns the size of
    /// a regular file at a path, or `nil` if there is none (no checksums are recomputed).
    static func classify(files: [Clip], volumeIdentity: String, entries: [String: LedgerEntry],
                         fileSize: (String) -> Int64?) -> CardInventory {
        var result = CardInventory()
        var folders: [String] = []
        for file in files {
            guard let entry = entries[file.ledgerKey(volumeIdentity: volumeIdentity)], entry.size == file.size else {
                result.new.append(file)
                continue
            }
            if fileSize(entry.destinationPath) == entry.size {
                result.offloaded.append(file)
                folders.append((entry.destinationPath as NSString).deletingLastPathComponent)
            } else {
                result.missing.append(file)
            }
        }
        result.copiesFolder = FormatReadiness.commonFolder(folders)
        return result
    }

    /// Only the ledger keys (no destination check): known files count as offloaded.
    static func classify(files: [Clip], volumeIdentity: String, knownKeys: Set<String>) -> CardInventory {
        var result = CardInventory()
        for file in files {
            if knownKeys.contains(file.ledgerKey(volumeIdentity: volumeIdentity)) {
                result.offloaded.append(file)
            } else {
                result.new.append(file)
            }
        }
        return result
    }
}

/// Copying files again that the ledger already has.
enum ReoffloadMode: String, Equatable, Sendable {
    /// Only new files (the normal case).
    case off
    /// New files, plus files whose copy is missing at the destination.
    case missing
    /// Every file on the card. New copies are made next to the old ones; nothing is overwritten.
    case everything
}

/// Which files an offload copies, given the inventory and the user's choices.
/// Pure, so it's unit tested.
struct OffloadSelection: Equatable, Sendable {
    /// What the Offload button copies.
    var toCopy: [Clip] = []
    /// Card paths in `toCopy` that were offloaded before (shown with a "Re-offload" mark).
    var reoffloading: Set<String> = []
    /// Offloaded files (copy present) in the included types that aren't being copied again.
    var offloadedKept = 0
    /// Files with a missing copy in the included types that aren't being copied again.
    var missingKept = 0

    static func make(inventory: CardInventory, categories: Set<MediaCategory>,
                     reoffload: ReoffloadMode, reoffloadIDs: Set<String>) -> OffloadSelection {
        var result = OffloadSelection()
        let included = { (clip: Clip) in categories.contains(clip.category) }
        let picked = withSidecars(reoffloadIDs, files: inventory.all)
        result.toCopy = inventory.new.filter(included)
        for clip in inventory.missing where included(clip) {
            if reoffload != .off || picked.contains(clip.relativePath) {
                result.toCopy.append(clip)
                result.reoffloading.insert(clip.relativePath)
            } else {
                result.missingKept += 1
            }
        }
        for clip in inventory.offloaded where included(clip) {
            if reoffload == .everything || picked.contains(clip.relativePath) {
                result.toCopy.append(clip)
                result.reoffloading.insert(clip.relativePath)
            } else {
                result.offloadedKept += 1
            }
        }
        return result
    }

    /// Re-offloading a clip brings its sidecars (e.g. C0001M01.XML) along.
    static func withSidecars(_ ids: Set<String>, files: [Clip]) -> Set<String> {
        guard !ids.isEmpty else { return ids }
        let sidecars = SidecarMatcher.match(Offloader.order(files))
        var result = ids
        for id in ids {
            for sidecar in sidecars.byPrimary[id] ?? [] { result.insert(sidecar.file.relativePath) }
        }
        return result
    }
}
