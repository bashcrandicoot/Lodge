import AVFoundation
import Foundation

/// "Skip short videos": accidental takes under a few seconds aren't offloaded unless included.
struct ShortClipRule: Equatable, Sendable {
    var isEnabled = true
    /// Clips shorter than this many seconds are skipped.
    var threshold: Double = 5

    static let off = ShortClipRule(isEnabled: false)
    static let thresholdRange = 1...60

    /// `nil` (length unknown, e.g. BRAW or R3D) is never short.
    func isShort(_ duration: Double?) -> Bool {
        guard isEnabled, let duration, duration.isFinite, duration >= 0 else { return false }
        return duration < threshold
    }
}

/// Which new videos (and their sidecars) the rule skips. Pure, so it's unit tested.
struct ShortClipSkip: Equatable, Sendable {
    /// The skipped videos, in card order.
    var clips: [Clip] = []
    /// Card paths of the skipped videos and their sidecars.
    var ids: Set<String> = []
    /// Skipped video's card path → how many sidecars stay behind with it.
    var sidecarCounts: [String: Int] = [:]

    var isEmpty: Bool { clips.isEmpty }

    /// `candidates` are the files that would otherwise be copied; `files` is everything on the card
    /// (for matching sidecars). Videos in `included` ("Include Anyway") are kept.
    static func find(candidates: [Clip], files: [Clip], durations: [String: Double],
                     rule: ShortClipRule, included: Set<String>, includeAll: Bool) -> ShortClipSkip {
        guard rule.isEnabled, !includeAll else { return ShortClipSkip() }
        var result = ShortClipSkip()
        for clip in candidates where clip.category == .video && !included.contains(clip.relativePath)
            && rule.isShort(durations[clip.relativePath]) {
            result.clips.append(clip)
            result.ids.insert(clip.relativePath)
        }
        guard !result.ids.isEmpty else { return result }
        // A skipped clip's sidecars (C0001M01.XML) stay behind with it.
        let candidateIDs = Set(candidates.map(\.relativePath))
        let sidecars = SidecarMatcher.match(Offloader.order(files))
        for id in Array(result.ids) {
            for sidecar in sidecars.byPrimary[id] ?? [] where candidateIDs.contains(sidecar.file.relativePath) {
                result.ids.insert(sidecar.file.relativePath)
                result.sidecarCounts[id, default: 0] += 1
            }
        }
        return result
    }
}

enum DurationFormatting {
    /// 3.7 → "0:03", 75 → "1:15", 3_725 → "1:02:05" (rounded down, like the camera shows it).
    static func short(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.isFinite ? seconds.rounded(.down) : 0))
        let (hours, minutes, secs) = (total / 3600, total / 60 % 60, total % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    /// "Under 5 seconds" / "Under 1 second"
    static func threshold(_ seconds: Double) -> String {
        let value = Int(seconds)
        return value == 1 ? "1 second" : "\(value) seconds"
    }
}

/// Reads video lengths. The real one uses AVFoundation; tests use a fake.
protocol DurationReading: Sendable {
    /// Seconds, or `nil` when the length can't be read.
    func duration(of url: URL) async -> Double?
}

/// AVFoundation's `load(.duration)`. Only reads the file's header; never writes to the card.
struct AVDurationReader: DurationReading {
    /// Formats AVFoundation can't open: don't even try (their length stays unknown).
    static let unreadableExtensions: Set<String> = ["braw", "r3d", "crm", "ari", "cine", "nev"]
    var timeout: Duration = .seconds(3)

    static func canRead(_ url: URL) -> Bool {
        !unreadableExtensions.contains(url.pathExtension.lowercased())
    }

    func duration(of url: URL) async -> Double? {
        guard Self.canRead(url) else { return nil }
        let timeout = self.timeout
        return await withTaskGroup(of: Double?.self) { group in
            group.addTask {
                let asset = AVURLAsset(url: url)
                guard let time = try? await asset.load(.duration), time.isNumeric else { return nil }
                let seconds = time.seconds
                return seconds.isFinite && seconds > 0 ? seconds : nil
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}

enum DurationScanner {
    /// Reads the lengths of the videos in `clips`, a few at a time. Keyed by card path.
    /// `cache` (keyed by ledger key, so a changed file is read again) is consulted first;
    /// the returned `fresh` values should be added to it.
    static func read(_ clips: [Clip], volumeIdentity: String, cache: [String: Double?],
                     reader: DurationReading, width: Int = 4)
        async -> (byPath: [String: Double], fresh: [String: Double?]) {
        var byPath: [String: Double] = [:]
        var fresh: [String: Double?] = [:]
        var pending: [(path: String, key: String, url: URL)] = []
        for clip in clips where clip.category == .video {
            let key = clip.ledgerKey(volumeIdentity: volumeIdentity)
            if let cached = cache[key] {
                if let cached { byPath[clip.relativePath] = cached }
            } else {
                pending.append((clip.relativePath, key, clip.url))
            }
        }
        await withTaskGroup(of: (String, String, Double?).self) { group in
            var next = 0
            func addNext() {
                guard next < pending.count else { return }
                let item = pending[next]
                next += 1
                group.addTask { (item.path, item.key, await reader.duration(of: item.url)) }
            }
            for _ in 0..<max(1, width) { addNext() }
            while let (path, key, seconds) = await group.next() {
                fresh[key] = .some(seconds)
                if let seconds { byPath[path] = seconds }
                addNext()
            }
        }
        return (byPath, fresh)
    }
}
