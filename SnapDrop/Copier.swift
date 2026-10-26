import Foundation
import CryptoKit

/// Things that can go wrong while copying one clip.
enum CopierError: LocalizedError {
    case destinationExists(String)
    case couldNotCreate(String)
    case checksumMismatch(String)

    var errorDescription: String? {
        switch self {
        case .destinationExists(let name): return "\(name) already exists — not overwriting it."
        case .couldNotCreate(let name): return "Couldn't create \(name) in the destination."
        case .checksumMismatch(let name): return "Checksum mismatch for \(name). The copy was deleted."
        }
    }
}

/// Copies a single file safely and verifies it with SHA-256.
///
/// 1. Copy into "<final name>.snapdrop-partial", hashing the source bytes as they're read.
/// 2. Re-read the copy from disk and hash it.
/// 3. Hashes match -> rename to the final name. Otherwise delete the partial file.
/// The source (the card) is only ever read, never changed.
enum Copier {
    /// Read/write in 8 MB chunks so big clips never have to fit in memory.
    static let chunkSize = 8 * 1024 * 1024

    static func partialURL(for finalURL: URL) -> URL {
        finalURL.deletingLastPathComponent()
            .appendingPathComponent(finalURL.lastPathComponent + ".snapdrop-partial")
    }

    /// Copies `source` to `finalURL` and verifies it. Returns the SHA-256 (hex).
    /// `onBytes` is called after each chunk with the number of bytes just copied.
    @discardableResult
    static func copyAndVerify(
        source: URL,
        to finalURL: URL,
        onBytes: (Int64) async -> Void = { _ in }
    ) async throws -> String {
        let fm = FileManager.default
        let partial = partialURL(for: finalURL)

        guard !fm.fileExists(atPath: finalURL.path) else {
            throw CopierError.destinationExists(finalURL.lastPathComponent)
        }
        guard !fm.fileExists(atPath: partial.path),
              fm.createFile(atPath: partial.path, contents: nil) else {
            throw CopierError.couldNotCreate(partial.lastPathComponent)
        }

        do {
            // Step 1: copy + hash the source.
            let reader = try FileHandle(forReadingFrom: source)
            defer { try? reader.close() }
            let writer = try FileHandle(forWritingTo: partial)
            var hasher = SHA256()
            do {
                while true {
                    try Task.checkCancellation()
                    let count: Int = try autoreleasepool {
                        guard let data = try reader.read(upToCount: chunkSize), !data.isEmpty else { return 0 }
                        hasher.update(data: data)
                        try writer.write(contentsOf: data)
                        return data.count
                    }
                    if count == 0 { break }
                    await onBytes(Int64(count))
                }
                try writer.synchronize()
                try writer.close()
            } catch {
                try? writer.close()
                throw error
            }
            let sourceHash = hexString(hasher.finalize())

            // Step 2: hash the copy as it is on disk.
            try Task.checkCancellation()
            let copyHash = try sha256(of: partial)
            guard copyHash == sourceHash else {
                throw CopierError.checksumMismatch(source.lastPathComponent)
            }

            // Keep the original dates on the copy (handy in Finder and editing apps).
            if let attributes = try? fm.attributesOfItem(atPath: source.path) {
                var dates: [FileAttributeKey: Any] = [:]
                dates[.creationDate] = attributes[.creationDate]
                dates[.modificationDate] = attributes[.modificationDate]
                try? fm.setAttributes(dates, ofItemAtPath: partial.path)
            }

            // Step 3: give it its final name. moveItem refuses to overwrite an existing file.
            try fm.moveItem(at: partial, to: finalURL)
            return sourceHash
        } catch {
            try? fm.removeItem(at: partial)
            throw error
        }
    }

    /// SHA-256 of a file, read in chunks.
    static func sha256(of url: URL, chunkSize: Int = Copier.chunkSize) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let more: Bool = try autoreleasepool {
                guard let data = try handle.read(upToCount: chunkSize), !data.isEmpty else { return false }
                hasher.update(data: data)
                return true
            }
            if !more { break }
        }
        return hexString(hasher.finalize())
    }

    static func hexString(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Offloading a whole card

/// Live progress numbers for the UI.
struct OffloadProgress: Sendable, Equatable {
    var filesDone = 0
    var filesTotal = 0
    var currentFile = ""
    var bytesDone: Int64 = 0
    var bytesTotal: Int64 = 0

    var fraction: Double {
        bytesTotal > 0 ? min(1, Double(bytesDone) / Double(bytesTotal)) : 0
    }
}

/// The result shown when an offload finishes.
struct OffloadSummary: Sendable, Equatable {
    var copied = 0
    var skipped = 0
    var failed = 0
    var cancelled = false
    var failures: [String] = []
}

/// Everything needed to offload one card.
struct OffloadJob: Sendable {
    let card: CardVolume
    /// Only the clips that haven't been offloaded before.
    let clips: [Clip]
    let shootName: String
    let destination: URL
    /// How many clips were skipped because the ledger already has them.
    let alreadyOffloaded: Int
}

/// Runs a whole offload: names, copies and verifies each clip in order.
/// Meant to be called off the main thread (see `OffloadSession.start`).
enum Offloader {
    static func run(
        job: OffloadJob,
        progress: @Sendable (OffloadProgress) async -> Void,
        record: @Sendable (LedgerEntry) async -> Void
    ) async -> OffloadSummary {
        var summary = OffloadSummary(skipped: job.alreadyOffloaded)

        // Oldest first, so numbering follows the order clips were shot.
        let ordered = job.clips.sorted {
            ($0.captureDate, $0.relativePath) < ($1.captureDate, $1.relativePath)
        }

        var state = OffloadProgress(
            filesTotal: ordered.count,
            bytesTotal: ordered.reduce(Int64(0)) { $0 + $1.size }
        )
        var allocator = SequenceAllocator()

        for clip in ordered {
            if Task.isCancelled {
                summary.cancelled = true
                break
            }
            state.currentFile = clip.url.lastPathComponent
            await progress(state)
            let bytesBefore = state.bytesDone

            do {
                let date = Renamer.dateString(for: clip.captureDate)
                let folder = Renamer.folderURL(destination: job.destination, dateString: date, shootName: job.shootName)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let prefix = Renamer.prefix(dateString: date, shootName: job.shootName)
                let finalURL = allocator.nextFileURL(folder: folder, prefix: prefix, fileExtension: clip.url.pathExtension)

                let hash = try await Copier.copyAndVerify(source: clip.url, to: finalURL) { bytes in
                    state.bytesDone += bytes
                    await progress(state)
                }

                summary.copied += 1
                await record(LedgerEntry(
                    sourceKey: clip.ledgerKey(volumeIdentity: job.card.identity),
                    cardName: job.card.name,
                    sourceRelativePath: clip.relativePath,
                    destinationPath: finalURL.path,
                    size: clip.size,
                    sha256: hash,
                    offloadedAt: Date()
                ))
            } catch is CancellationError {
                summary.cancelled = true
                break
            } catch {
                summary.failed += 1
                summary.failures.append("\(clip.relativePath): \(error.localizedDescription)")
            }

            state.bytesDone = bytesBefore + clip.size
            state.filesDone += 1
            await progress(state)
        }
        return summary
    }
}
