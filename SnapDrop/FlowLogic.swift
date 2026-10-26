import Foundation

// Pure helpers that drive the main window. No UI code in here, so it's easy to unit test.

/// Which fields the current templates need filled in.
struct NamingNeeds: Equatable, Sendable {
    var project = false
    var shoot = false
    var camera = false

    init(project: Bool = false, shoot: Bool = false, camera: Bool = false) {
        self.project = project
        self.shoot = shoot
        self.camera = camera
    }

    init(_ naming: NamingTemplates?) {
        let naming = naming ?? .standard
        self.init(project: naming.uses(.project), shoot: naming.uses(.shoot), camera: naming.uses(.camera))
    }
}

/// Why the Offload button is disabled (or `nil` when everything is ready).
enum OffloadReadiness {
    static func blocker(
        hasCard: Bool,
        isScanning: Bool,
        newFileCount: Int,
        namingIsValid: Bool = true,
        needs: NamingNeeds = NamingNeeds(shoot: true),
        project: String = "",
        shootName: String,
        hasCamera: Bool = false,
        hasDestination: Bool,
        requiredBytes: Int64,
        availableBytes: Int64?
    ) -> String? {
        if !hasCard { return "Insert a card to begin" }
        if isScanning { return "Scanning card…" }
        if newFileCount == 0 { return "Everything on this card is already offloaded" }
        if !namingIsValid { return "Fix the naming template in Settings" }
        if needs.project && project.isEmpty { return "Enter a project name" }
        if needs.shoot && shootName.isEmpty { return "Enter a shoot name" }
        if needs.camera && !hasCamera { return "Choose a camera" }
        if !hasDestination { return "Choose a destination folder" }
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
