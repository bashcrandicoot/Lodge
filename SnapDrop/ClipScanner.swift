import Foundation

/// One file found on a card (video, photo, audio or anything else).
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

    /// Video, photo, audio or other — from the file extension.
    var category: MediaCategory { MediaCategory.classify(fileName: url.lastPathComponent) }

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

/// Finds the files on a card. Read-only: it never changes anything on the card.
enum ClipScanner {
    /// File extensions we treat as video clips (compared lowercased).
    static var videoExtensions: Set<String> { MediaCategory.videoExtensions }

    /// Folders and files that computers (not cameras) leave on cards. Compared lowercased.
    /// Anything starting with "." (".Spotlight-V100", ".fseventsd", ".Trashes",
    /// ".TemporaryItems", ".DS_Store", "._C0001.MP4"…) is skipped as well.
    static let junkNames: Set<String> = [
        "system volume information", "$recycle.bin", "recycler", "recycled", "thumbs.db", "desktop.ini",
    ]

    /// True for system junk that should never be copied.
    static func isJunk(_ name: String) -> Bool {
        name.hasPrefix(".") || junkNames.contains(name.lowercased())
    }

    /// True if a file name looks like a video clip.
    static func isClipFileName(_ name: String) -> Bool {
        !isJunk(name) && MediaCategory.classify(fileName: name) == .video
    }

    /// Lists every real file on the card at `volumeURL` (the whole card, recursively),
    /// keeping only the chosen categories. Sorted by path on the card.
    static func scan(volumeURL: URL, categories: Set<MediaCategory> = Set(MediaCategory.allCases)) -> [Clip] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
                                      .fileSizeKey, .creationDateKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: volumeURL,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true }   // keep going past folders we can't read
        ) else { return [] }

        var result: [Clip] = []
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            let values = try? url.resourceValues(forKeys: Set(keys))
            if isJunk(name) {
                if values?.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            guard values?.isRegularFile == true, values?.isSymbolicLink != true else { continue }
            guard categories.contains(MediaCategory.classify(fileName: name)) else { continue }
            result.append(Clip(
                url: url,
                relativePath: relativePath(of: url, in: volumeURL),
                size: Int64(values?.fileSize ?? 0),
                creationDate: values?.creationDate,
                modificationDate: values?.contentModificationDate))
        }
        return result.sorted { $0.relativePath < $1.relativePath }
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
}
