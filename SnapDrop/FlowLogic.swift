import Foundation

// Pure helpers that drive the main window. No UI code in here, so it's easy to unit test.

/// One row of the live "name preview": what a clip is called now, and what it will be called.
struct NamePreviewItem: Identifiable, Equatable, Sendable {
    let id: String            // the clip's path on the card
    let originalName: String  // "C0001.MP4"
    let folder: String        // "2026-10-25/BeachShoot"
    let newName: String       // "2026-10-25_BeachShoot_0001.mp4"
    let size: Int64
}

enum NamePreview {
    /// Shown in the preview while the shoot-name field is still empty.
    static let placeholderShootName = "ShootName"

    /// Works out the final names for `clips`, exactly the way the offload will
    /// (same order, same numbering).
    /// - Parameter highestExisting: highest sequence number already used in each
    ///   "date/shoot" folder at the destination, so the preview continues after it.
    static func preview(clips: [Clip], shootName: String, highestExisting: [String: Int] = [:]) -> [NamePreviewItem] {
        var next: [String: Int] = [:]
        return Offloader.order(clips).map { clip in
            let date = Renamer.dateString(for: clip.captureDate)
            let folder = "\(date)/\(shootName)"
            let number = next[folder] ?? ((highestExisting[folder] ?? 0) + 1)
            next[folder] = number + 1
            let name = Renamer.fileName(
                prefix: Renamer.prefix(dateString: date, shootName: shootName),
                sequence: number,
                fileExtension: clip.url.pathExtension)
            return NamePreviewItem(
                id: clip.relativePath,
                originalName: clip.url.lastPathComponent,
                folder: folder,
                newName: name,
                size: clip.size)
        }
    }

    /// The distinct "date/shoot" folders the clips will go into, in order.
    static func folders(for items: [NamePreviewItem]) -> [String] {
        var seen = Set<String>()
        return items.compactMap { seen.insert($0.folder).inserted ? $0.folder : nil }
    }

    /// Looks at the destination on disk to find the highest number already used in
    /// each folder the clips will go into. (Reads the disk, so not "pure".)
    static func highestExisting(destination: URL?, clips: [Clip], shootName: String) -> [String: Int] {
        guard let destination, !shootName.isEmpty else { return [:] }
        var result: [String: Int] = [:]
        let dates = Set(clips.map { Renamer.dateString(for: $0.captureDate) })
        for date in dates {
            let folder = Renamer.folderURL(destination: destination, dateString: date, shootName: shootName)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            let highest = Renamer.highestSequence(in: names, prefix: Renamer.prefix(dateString: date, shootName: shootName))
            if highest > 0 { result["\(date)/\(shootName)"] = highest }
        }
        return result
    }
}

/// Why the Offload button is disabled (or `nil` when everything is ready).
enum OffloadReadiness {
    static func blocker(
        hasCard: Bool,
        isScanning: Bool,
        newClipCount: Int,
        shootName: String,
        hasDestination: Bool,
        requiredBytes: Int64,
        availableBytes: Int64?
    ) -> String? {
        if !hasCard { return "Insert a card to begin" }
        if isScanning { return "Scanning card…" }
        if newClipCount == 0 { return "All clips on this card are already offloaded" }
        if shootName.isEmpty { return "Enter a shoot name" }
        if !hasDestination { return "Choose a destination folder" }
        if let available = availableBytes, available < requiredBytes {
            return "Not enough space: needs \(OffloadFormatting.bytes(requiredBytes)), \(OffloadFormatting.bytes(available)) free"
        }
        return nil
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

    /// "1 Clip" / "12 Clips"
    static func clipCount(_ count: Int) -> String {
        count == 1 ? "1 Clip" : "\(count) Clips"
    }

    /// "Offload 12 Clips"
    static func offloadButtonTitle(clipCount count: Int) -> String {
        count == 0 ? "Offload Clips" : "Offload \(clipCount(count))"
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
enum VolumeInfo {
    static func availableBytes(at url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    static func totalBytes(at url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey])
        return values?.volumeTotalCapacity.map(Int64.init)
    }
}
