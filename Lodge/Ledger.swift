import Foundation

/// One clip that was successfully copied and verified.
struct LedgerEntry: Codable, Identifiable, Hashable, Sendable {
    /// Unique key for the clip on the card (see `LedgerKey`).
    let sourceKey: String
    let cardName: String
    let sourceRelativePath: String
    /// Where the verified copy now lives.
    let destinationPath: String
    let size: Int64
    /// SHA-256 checksum (hex) of the clip.
    let sha256: String
    /// When it was offloaded.
    let offloadedAt: Date

    /// Unique per copy: the same clip can be offloaded again (a new copy, never overwritten).
    var id: String { sourceKey + "\u{0}" + destinationPath }
}

/// Builds the identity key for a clip:
/// card UUID (or name) + path on card + size + modification time.
/// If any of those differ, it's treated as a different clip.
enum LedgerKey {
    static func make(volumeIdentity: String, relativePath: String, size: Int64, modificationDate: Date?) -> String {
        // Whole seconds only: memory-card file systems store coarse timestamps.
        let modified = modificationDate.map { String(Int64($0.timeIntervalSince1970.rounded(.down))) } ?? "nodate"
        return "\(volumeIdentity)|\(relativePath)|\(size)|\(modified)"
    }
}

/// The list of everything Lodge has ever offloaded, saved as JSON at
/// ~/Library/Application Support/Lodge/ledger.json
@MainActor
final class Ledger: ObservableObject {
    @Published private(set) var entries: [LedgerEntry] = []
    /// Set if loading or saving failed, so the UI can show it.
    @Published private(set) var lastError: String?

    private(set) var knownKeys: Set<String> = []
    let fileURL: URL

    nonisolated static var defaultFileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support
            .appendingPathComponent("Lodge", isDirectory: true)
            .appendingPathComponent("ledger.json")
    }

    init(fileURL: URL = Ledger.defaultFileURL) {
        self.fileURL = fileURL
        load()
    }

    /// The most recent offloads, newest first.
    func recent(limit: Int = 50) -> [LedgerEntry] {
        Array(entries.suffix(limit).reversed())
    }

    func contains(key: String) -> Bool {
        knownKeys.contains(key)
    }

    /// The newest entry for each clip key (used to check a card is safe to format).
    func entriesByKey() -> [String: LedgerEntry] {
        var result: [String: LedgerEntry] = [:]
        for entry in entries { result[entry.sourceKey] = entry }
        return result
    }

    /// Records a verified copy and saves the ledger to disk right away.
    func add(_ entry: LedgerEntry) {
        entries.append(entry)
        knownKeys.insert(entry.sourceKey)
        save()
    }

    /// Ledger keys start with the card's identity (see `LedgerKey`).
    nonisolated static func belongs(_ entry: LedgerEntry, toVolume identity: String) -> Bool {
        entry.sourceKey.hasPrefix(identity + "|")
    }

    func entryCount(forVolume identity: String) -> Int {
        entries.filter { Ledger.belongs($0, toVolume: identity) }.count
    }

    /// Forgets one copy. If the clip was offloaded more than once, the older copies remain.
    func forget(_ entry: LedgerEntry) {
        remove { $0 == entry }
    }

    /// Forgets everything offloaded from one card: its files show as new again.
    /// The copies at the destination are not touched.
    @discardableResult
    func forget(volumeIdentity identity: String) -> Int {
        remove { Ledger.belongs($0, toVolume: identity) }
    }

    @discardableResult
    private func remove(where shouldRemove: (LedgerEntry) -> Bool) -> Int {
        let before = entries.count
        entries.removeAll(where: shouldRemove)
        let removed = before - entries.count
        guard removed > 0 else { return 0 }
        knownKeys = Set(entries.map(\.sourceKey))
        save()
        return removed
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            entries = try decoder.decode([LedgerEntry].self, from: data)
            knownKeys = Set(entries.map(\.sourceKey))
        } catch {
            lastError = "Couldn’t read the ledger: \(error.localizedDescription)"
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(entries)
            try data.write(to: fileURL, options: .atomic)
            lastError = nil
        } catch {
            lastError = "Couldn’t save the ledger: \(error.localizedDescription)"
        }
    }
}
