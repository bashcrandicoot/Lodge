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

    /// File types computers leave on cards that are never camera media: disk images (an
    /// installer .dmg copied onto a card, a Lodge download…). Compared lowercased, without the dot.
    static let junkExtensions: Set<String> = ["dmg"]

    /// True for system junk that should never be copied.
    static func isJunk(_ name: String) -> Bool {
        name.hasPrefix(".") || junkNames.contains(name.lowercased())
            || junkExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    /// True if a file name looks like a video clip.
    static func isClipFileName(_ name: String) -> Bool {
        !isJunk(name) && MediaCategory.classify(fileName: name) == .video
    }

    /// What a scan found: the files to work with, and what it skipped on purpose.
    struct Result: Equatable, Sendable {
        var files: [Clip] = []
        /// Card paths of ignored files and folders (a skipped folder counts once). Sorted.
        var ignored: [String] = []
    }

    /// Lists every real file on the card at `volumeURL` (the whole card, recursively),
    /// keeping only the chosen categories. Sorted by path on the card.
    static func scan(volumeURL: URL, categories: Set<MediaCategory> = Set(MediaCategory.allCases),
                     rules: FileRules = .standard) -> [Clip] {
        scanReport(volumeURL: volumeURL, categories: categories, rules: rules).files
    }

    /// `scan`, plus what was ignored: system junk (always) and anything on the ignore list in
    /// `rules` (".DS_Store", "._*"…). Ignored folders are skipped with everything inside them.
    static func scanReport(volumeURL: URL, categories: Set<MediaCategory> = Set(MediaCategory.allCases),
                           rules: FileRules = .standard) -> Result {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
                                      .fileSizeKey, .creationDateKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: volumeURL,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true }   // keep going past folders we can't read
        ) else { return Result() }

        var result = Result()
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            let values = try? url.resourceValues(forKeys: Set(keys))
            if isJunk(name) || rules.isIgnored(name) {
                if values?.isDirectory == true { enumerator.skipDescendants() }
                result.ignored.append(relativePath(of: url, in: volumeURL))
                continue
            }
            guard values?.isRegularFile == true, values?.isSymbolicLink != true else { continue }
            guard categories.contains(MediaCategory.classify(fileName: name)) else { continue }
            result.files.append(Clip(
                url: url,
                relativePath: relativePath(of: url, in: volumeURL),
                size: Int64(values?.fileSize ?? 0),
                creationDate: values?.creationDate,
                modificationDate: values?.contentModificationDate))
        }
        result.files.sort { $0.relativePath < $1.relativePath }
        result.ignored.sort()
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
}
