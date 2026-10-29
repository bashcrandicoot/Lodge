import Foundation

// Pure helpers that drive the main window. No UI code in here, so it's easy to unit test.

/// Which fields the current templates need filled in.
struct NamingNeeds: Equatable, Sendable {
    var project = false
    var camera = false

    init(project: Bool = false, camera: Bool = false) {
        self.project = project
        self.camera = camera
    }

    init(_ naming: NamingTemplates?) {
        let naming = naming ?? .standard
        self.init(project: naming.uses(.project), camera: naming.uses(.camera))
    }
}

/// Why the Offload button is disabled (or `nil` when everything is ready).
enum OffloadReadiness {
    static func blocker(
        hasCard: Bool,
        isScanning: Bool,
        newFileCount: Int,
        missingCopies: Int = 0,
        shortClipsSkipped: Int = 0,
        outsideDates: Int = 0,
        cardIsEmpty: Bool = false,
        namingIsValid: Bool = true,
        needs: NamingNeeds = NamingNeeds(project: true),
        project: String,
        hasCamera: Bool = false,
        hasDestination: Bool,
        destinationConnected: Bool = true,
        destinationReadOnlyReason: String? = nil,
        requiredBytes: Int64,
        availableBytes: Int64?
    ) -> String? {
        if !hasCard { return "Insert a card to begin" }
        if isScanning { return "Scanning card…" }
        if cardIsEmpty { return "This card is empty" }
        if newFileCount == 0 && missingCopies > 0 {
            return missingCopies == 1
                ? "1 copy is missing at the destination — choose Re-offload"
                : "\(missingCopies) copies are missing at the destination — choose Re-offload"
        }
        if newFileCount == 0 && shortClipsSkipped > 0 {
            return shortClipsSkipped == 1
                ? "Only a short clip is left — choose Include Anyway to offload it"
                : "Only short clips are left — choose Include All Short Clips to offload them"
        }
        if newFileCount == 0 && outsideDates > 0 {
            return "Nothing new in the chosen dates — choose Any date to see everything"
        }
        if newFileCount == 0 { return "Everything on this card is already offloaded" }
        if !namingIsValid { return "Fix the naming template in Settings" }
        if needs.project && project.isEmpty { return "Enter a project name" }
        if needs.camera && !hasCamera { return "Choose a camera" }
        if !hasDestination { return "Choose a destination folder" }
        if !destinationConnected { return "The destination folder isn’t connected — choose another" }
        if let destinationReadOnlyReason { return destinationReadOnlyReason }
        if let available = availableBytes, available < requiredBytes {
            return "Not enough space: needs \(OffloadFormatting.bytes(requiredBytes)), \(OffloadFormatting.bytes(available)) free"
        }
        return nil
    }
}

/// Helpers for showing a plan as a folder tree.
enum PlanLayout {
    /// The distinct destination folders, in the order files go into them.
    static func folders(_ plan: [PlannedFile]) -> [String] {
        var seen = Set<String>()
        return plan.compactMap { seen.insert($0.folder).inserted ? $0.folder : nil }
    }
}

/// Text formatting for counts, sizes and time remaining.
enum OffloadFormatting {
    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    /// "1.2 GB of 4.8 GB"
    static func bytesProgress(done: Int64, total: Int64) -> String {
        "\(bytes(done)) of \(bytes(total))"
    }

    /// "1 File" / "12 Files"
    static func fileCount(_ count: Int) -> String {
        count == 1 ? "1 File" : "\(count) Files"
    }

    /// The selected card's line: "54 new files · 5 ignored" before and during an offload,
    /// "57 copied · 5 ignored" once it has finished.
    static func cardDetail(newFiles: Int, copied: Int?, ignored: Int) -> String {
        let main: String
        if let copied {
            main = "\(copied) copied"
        } else {
            switch newFiles {
            case 0: main = "No new files"
            case 1: main = "1 new file"
            default: main = "\(newFiles) new files"
            }
        }
        return ignored > 0 ? "\(main) · \(ignored) ignored" : main
    }

    /// "Offload 12 Files"
    static func offloadButtonTitle(fileCount count: Int) -> String {
        count == 0 ? "Offload Files" : "Offload \(fileCount(count))"
    }

    /// Seconds left, based on the average speed so far. `nil` until there's enough data.
    static func estimatedSecondsRemaining(bytesDone: Int64, bytesTotal: Int64, elapsed: TimeInterval) -> TimeInterval? {
        guard bytesTotal > 0 else { return nil }
        if bytesDone >= bytesTotal { return 0 }
        guard bytesDone > 0, elapsed >= 2 else { return nil }
        let bytesPerSecond = Double(bytesDone) / elapsed
        guard bytesPerSecond > 0 else { return nil }
        return Double(bytesTotal - bytesDone) / bytesPerSecond
    }

    /// "About 3 min left", "Less than a minute left", …
    static func etaText(_ seconds: TimeInterval?) -> String {
        guard let seconds else { return "Estimating time…" }
        if seconds <= 0 { return "Almost done" }
        if seconds < 60 { return "Less than a minute left" }
        let minutes = Int((seconds / 60).rounded(.up))
        if minutes < 60 { return "About \(minutes) min left" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "About \(hours) hr left" : "About \(hours) hr \(rest) min left"
    }

    /// "3 copied · 1 skipped · 0 failed"
    static func summaryLine(_ summary: OffloadSummary) -> String {
        "\(summary.copied) copied · \(summary.skipped) skipped · \(summary.failed) failed"
    }
}

/// Free / total space of the volume a URL lives on.
///
/// `volumeAvailableCapacityForImportantUsage` is only reliable on APFS: on exFAT, FAT32 and
/// HFS+ drives (and anything mounted through FSKit) macOS often reports 0 or nothing, even
/// with hundreds of GB free. So it's only trusted when it's above 0; otherwise Lodge falls back
/// to `volumeAvailableCapacity`, then to `statfs`.
enum VolumeInfo {
    static func availableBytes(at url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey,
                                                       .volumeAvailableCapacityKey])
        return resolveAvailable(important: values?.volumeAvailableCapacityForImportantUsage,
                                available: values?.volumeAvailableCapacity.map(Int64.init),
                                statfs: { statfsInfo(at: url)?.availableBytes })
    }

    static func totalBytes(at url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey])
        if let total = values?.volumeTotalCapacity, total > 0 { return Int64(total) }
        return statfsInfo(at: url)?.totalBytes ?? values?.volumeTotalCapacity.map(Int64.init)
    }

    /// Picks the free space to show from the three sources, best first. A source that reports 0
    /// is only believed when a fallback agrees (or there's nothing else to go on), so a drive
    /// isn't shown as "Zero KB free" just because macOS skipped the important-usage figure.
    /// `statfs` is a closure so it's only called when it's needed.
    static func resolveAvailable(important: Int64?, available: Int64?, statfs: () -> Int64?) -> Int64? {
        if let important, important > 0 { return important }
        if let available, available > 0 { return available }
        let fromStatfs = statfs()
        if let fromStatfs, fromStatfs > 0 { return fromStatfs }
        // Every source that answered said 0. Trust that only if one of the fallbacks said so:
        // the important-usage figure alone isn't enough to call a drive full.
        if available == 0 || fromStatfs == 0 { return 0 }
        return nil
    }

    // MARK: Read-only drives

    /// Why Lodge can't write to the volume a URL lives on, or `nil` when it can.
    static func readOnlyReason(at url: URL) -> String? {
        let values = try? url.resourceValues(forKeys: [.volumeIsReadOnlyKey, .volumeLocalizedFormatDescriptionKey])
        let info = statfsInfo(at: url)
        let isReadOnly = values?.volumeIsReadOnly ?? info?.isReadOnly ?? false
        guard isReadOnly else { return nil }
        return readOnlyMessage(format: formatName(fsType: info?.fsType,
                                                  description: values?.volumeLocalizedFormatDescription))
    }

    /// "This drive is read-only (NTFS). macOS can’t write to it."
    static func readOnlyMessage(format: String?) -> String {
        guard let format else { return "This drive is read-only, so Lodge can’t write to it — choose another" }
        if format == "NTFS" { return "This drive is read-only (NTFS). macOS can’t write to it." }
        return "This drive is read-only (\(format)), so Lodge can’t write to it — choose another"
    }

    /// A short, familiar name for a file system: "NTFS", "exFAT", "FAT32", "Mac OS Extended", "APFS".
    static func formatName(fsType: String?, description: String?) -> String? {
        switch fsType?.lowercased() {
        case "ntfs", "ufsd_ntfs", "tuxera_ntfs": return "NTFS"
        case "exfat": return "exFAT"
        case "msdos": return "FAT32"
        case "hfs": return "Mac OS Extended"
        case "apfs": return "APFS"
        default: break
        }
        guard let description, !description.isEmpty else { return fsType }
        if description.localizedCaseInsensitiveContains("NTFS") { return "NTFS" }
        return description
    }

    struct StatfsInfo: Equatable {
        var availableBytes: Int64
        var totalBytes: Int64
        var fsType: String
        var isReadOnly: Bool
    }

    static func statfsInfo(at url: URL) -> StatfsInfo? {
        var stats = statfs()
        guard statfs(url.path, &stats) == 0 else { return nil }
        let blockSize = Int64(stats.f_bsize)
        let fsType = withUnsafeBytes(of: stats.f_fstypename) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        return StatfsInfo(availableBytes: Int64(stats.f_bavail) * blockSize,
                          totalBytes: Int64(stats.f_blocks) * blockSize,
                          fsType: fsType,
                          isReadOnly: stats.f_flags & UInt32(MNT_RDONLY) != 0)
    }
}

/// How the app reacts when an offload ends.
enum OffloadFeedback {
    /// Every file copied and verified, nothing cancelled.
    static func isCleanSuccess(_ summary: OffloadSummary) -> Bool {
        !summary.cancelled && summary.failed == 0 && summary.copied > 0
    }

    /// The "Glass" sound plays only after a clean success, and only if it's turned on in Settings.
    static func shouldPlaySuccessSound(_ summary: OffloadSummary, enabled: Bool) -> Bool {
        enabled && isCleanSuccess(summary)
    }
}
