import Foundation

/// One video file found on a card.
struct Clip: Identifiable, Hashable, Sendable {
    /// Full location on the card.
    let url: URL
    /// Path inside the card, e.g. "DCIM/100MEDIA/C0001.MP4".
    let relativePath: String
    /// Size in bytes.
    let size: Int64
    let creationDate: Date?
    let modificationDate: Date?

    var id: String { relativePath }

    /// The date used for naming: creation date, falling back to modification date.
    var captureDate: Date { creationDate ?? modificationDate ?? Date() }

    /// The key that identifies this exact clip in the ledger.
    func ledgerKey(volumeIdentity: String) -> String {
        LedgerKey.make(
            volumeIdentity: volumeIdentity,
            relativePath: relativePath,
            size: size,
            modificationDate: modificationDate
        )
    }
}

/// Finds video clips on a card. Read-only: it never changes anything on the card.
enum ClipScanner {
    /// File extensions we treat as video clips (compared lowercased).
    static let videoExtensions: Set<String> = ["mp4", "mov", "mxf", "braw"]

    /// Where common cameras put their clips, relative to the card's root.
    static let cameraFolders = [
        "DCIM",                  // most cameras (searched recursively)
        "PRIVATE/M4ROOT/CLIP",   // Sony
        "CONTENTS/CLIPS",        // Panasonic
    ]

    /// True if a file name looks like a clip we should copy.
    /// Hidden files (starting with ".") — including macOS "._" junk files — are skipped.
    static func isClipFileName(_ name: String) -> Bool {
        if name.hasPrefix(".") { return false }
        let ext = (name as NSString).pathExtension.lowercased()
        return videoExtensions.contains(ext)
    }

    /// Lists all clips on the card at `volumeURL`.
    /// Looks in the known camera folders first; if none of those has clips,
    /// it searches the whole card.
    static func scan(volumeURL: URL) -> [Clip] {
        let fm = FileManager.default
        var found: [URL] = []
        var seen = Set<String>()

        for folder in cameraFolders {
            let dir = volumeURL.appendingPathComponent(folder, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
            for url in clipFiles(in: dir) where seen.insert(url.standardizedFileURL.path).inserted {
                found.append(url)
            }
        }

        if found.isEmpty {
            found = clipFiles(in: volumeURL)
        }

        return found
            .compactMap { makeClip(at: $0, root: volumeURL) }
            .sorted { $0.relativePath < $1.relativePath }
    }

    /// Recursively lists clip files inside `directory`.
    static func clipFiles(in directory: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var result: [URL] = []
        for case let url as URL in enumerator {
            guard isClipFileName(url.lastPathComponent) else { continue }
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isRegularFile == true {
                result.append(url)
            }
        }
        return result
    }

    /// The path of `file` relative to `root` ("DCIM/100/C0001.MP4").
    static func relativePath(of file: URL, in root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = file.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        if filePath.hasPrefix(prefix) {
            return String(filePath.dropFirst(prefix.count))
        }
        return file.lastPathComponent
    }

    private static func makeClip(at url: URL, root: URL) -> Clip? {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .creationDateKey, .contentModificationDateKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
        return Clip(
            url: url,
            relativePath: relativePath(of: url, in: root),
            size: Int64(values.fileSize ?? 0),
            creationDate: values.creationDate,
            modificationDate: values.contentModificationDate
        )
    }
}
