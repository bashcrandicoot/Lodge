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
    /// Card paths the scan skipped because of the ignore list or system junk (".DS_Store", ".Trashes"…).
    /// Never offloaded and never counted against "Ready to format".
    var ignored: [String] = []

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
    /// Files with a missing copy in the included types and dates that aren't being copied again.
    var missingKept = 0
    /// New short videos (and their sidecars) left on the card by "Skip videos shorter than".
    var skippedShort = ShortClipSkip()
    /// New files (in the included types) left on the card by the date filter, sidecars included.
    var outsideDates = 0

    /// Short clips are only skipped among new files: anything picked for re-offload is copied.
    /// The date filter applies to everything, except single files picked with "Re-offload This File".
    static func make(inventory: CardInventory, categories: Set<MediaCategory>,
                     reoffload: ReoffloadMode, reoffloadIDs: Set<String>,
                     shortRule: ShortClipRule = .off, durations: [String: Double] = [:],
                     includedShortIDs: Set<String> = [], includeAllShort: Bool = false,
                     rules: FileRules = .standard,
                     dateFilter: DateFilter = .any, now: Date = Date(), calendar: Calendar = .current) -> OffloadSelection {
        var result = OffloadSelection()
        let outside = dateFilter.excludedIDs(in: inventory.all, rules: rules, now: now, calendar: calendar)
        let included = { (clip: Clip) in categories.contains(clip.category) }
        let inDates = { (clip: Clip) in !outside.contains(clip.relativePath) }
        let picked = withSidecars(reoffloadIDs, files: inventory.all, rules: rules)
        let newFiles = inventory.new.filter(included).filter(inDates)
        result.outsideDates = inventory.new.filter(included).count - newFiles.count
        result.skippedShort = ShortClipSkip.find(candidates: newFiles, files: inventory.all, durations: durations,
                                                 rule: shortRule, included: includedShortIDs,
                                                 includeAll: includeAllShort, rules: rules)
        result.toCopy = newFiles.filter { !result.skippedShort.ids.contains($0.relativePath) }
        for clip in inventory.missing where included(clip) {
            if (reoffload != .off && inDates(clip)) || picked.contains(clip.relativePath) {
                result.toCopy.append(clip)
                result.reoffloading.insert(clip.relativePath)
            } else if inDates(clip) {
                // Missing copies from other days aren't offered for re-offload while the dates are set.
                result.missingKept += 1
            }
        }
        for clip in inventory.offloaded where included(clip) {
            if (reoffload == .everything && inDates(clip)) || picked.contains(clip.relativePath) {
                result.toCopy.append(clip)
                result.reoffloading.insert(clip.relativePath)
            } else {
                result.offloadedKept += 1
            }
        }
        return result
    }

    /// Re-offloading a clip brings its sidecars and proxies (e.g. C0001M01.XML, GL010001.LRV) along.
    static func withSidecars(_ ids: Set<String>, files: [Clip], rules: FileRules = .standard) -> Set<String> {
        guard !ids.isEmpty else { return ids }
        let sidecars = SidecarMatcher.match(Offloader.order(files), rules: rules)
        var result = ids
        for id in ids {
            for sidecar in sidecars.byPrimary[id] ?? [] { result.insert(sidecar.file.relativePath) }
        }
        return result
    }
}
