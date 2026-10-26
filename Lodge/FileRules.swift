import Foundation

/// What a file on the card is for, decided by its extension (Settings ▸ Files).
enum FileRole: String, Codable, Sendable {
    /// Real footage, photos, audio… named by the templates.
    case main
    /// A low-resolution copy made by the camera for quick editing (GoPro .LRV, DJI .LRF).
    case proxy
    /// A small helper file: thumbnails (.THM), metadata (.XML), telemetry (.SRT)…
    case sidecar

    /// The subfolder of the shoot folder these files go into (`nil` = next to the clips).
    var folderName: String? {
        switch self {
        case .main: return nil
        case .proxy: return "Proxies"
        case .sidecar: return "Sidecars"
        }
    }
}

/// The folder each kind of file goes into inside the shoot folder: one per file extension,
/// named in capitals ("MP4", "ARW", "WAV", "XYZ" for an unknown ".xyz"). Upper and lower case
/// share a folder (.MP4 and .mp4 both go in MP4), and so do two spellings of one format
/// (.JPEG goes in JPG, .TIFF in TIF). Proxies and sidecars use `FileRole.folderName` instead.
enum FormatFolder {
    /// Spellings of the same format that share a folder.
    static let aliases: [String: String] = ["jpeg": "jpg", "jpe": "jpg", "tiff": "tif"]

    /// "MP4" for "mp4" or "MP4"; nil for a file without an extension.
    static func name(forExtension ext: String) -> String? {
        let lower = ext.lowercased()
        guard !lower.isEmpty else { return nil }
        let name = NameRules.safeComponent((aliases[lower] ?? lower).uppercased())
        return name.isEmpty ? nil : name
    }

    /// "MP4" for "C0001.MP4"; nil for "README".
    static func name(forFile fileName: String) -> String? {
        name(forExtension: (fileName as NSString).pathExtension)
    }
}

/// Proxy and sidecar extensions, and the files that are never offloaded.
/// Pure and `Codable`, so it's saved in settings and presets and unit tested.
struct FileRules: Codable, Equatable, Hashable, Sendable {
    /// Lowercased, without the dot: ["lrv", "lrf"].
    var proxyExtensions: [String]
    /// Lowercased, without the dot: ["thm", "xml", "srt"].
    var sidecarExtensions: [String]
    /// Names (".DS_Store"), extensions (".thm" or "*.thm") or patterns ("._*").
    var ignorePatterns: [String]

    static let defaultProxyExtensions = ["lrv", "lrf"]
    static let defaultSidecarExtensions = ["thm", "xml", "srt"]
    static let defaultIgnorePatterns = [".DS_Store", "._*", ".Spotlight-V100", ".Trashes", ".fseventsd",
                                        ".TemporaryItems", "Thumbs.db"]

    /// The defaults: proxies and sidecars in their own folders, system junk ignored.
    static let standard = FileRules(proxyExtensions: defaultProxyExtensions,
                                    sidecarExtensions: defaultSidecarExtensions,
                                    ignorePatterns: defaultIgnorePatterns)

    /// No proxy or sidecar folders: helper files are sorted by extension like everything else,
    /// keeping their clip's name (and nothing extra is ignored).
    static let keepTogether = FileRules(proxyExtensions: [], sidecarExtensions: [], ignorePatterns: [])

    init(proxyExtensions: [String], sidecarExtensions: [String], ignorePatterns: [String]) {
        self.proxyExtensions = Self.cleanExtensions(proxyExtensions)
        self.sidecarExtensions = Self.cleanExtensions(sidecarExtensions)
        self.ignorePatterns = Self.cleanPatterns(ignorePatterns)
    }

    // MARK: Roles

    /// Main, proxy or sidecar, from the file name's extension (case-insensitive).
    func role(of fileName: String) -> FileRole {
        let ext = (fileName as NSString).pathExtension.lowercased()
        guard !ext.isEmpty else { return .main }
        if proxyExtensions.contains(ext) { return .proxy }
        if sidecarExtensions.contains(ext) { return .sidecar }
        return .main
    }

    // MARK: Ignore list

    /// True when a file or folder with this name is never offloaded.
    func isIgnored(_ name: String) -> Bool {
        ignorePatterns.contains { Self.matches(name, pattern: $0) }
    }

    /// - "._*", "*.tmp", "IMG_????.JPG": a pattern (`*` = anything, `?` = one character)
    /// - ".thm": that exact name, or any file ending in “.thm”
    /// - "Thumbs.db": that exact name
    /// Upper and lower case are treated the same.
    static func matches(_ name: String, pattern: String) -> Bool {
        let name = name.lowercased()
        let pattern = pattern.lowercased()
        guard !pattern.isEmpty else { return false }
        if pattern.contains("*") || pattern.contains("?") {
            return fnmatch(pattern, name, 0) == 0
        }
        if name == pattern { return true }
        // ".thm" also means "the .thm extension" (a single dot at the start, no other dots).
        if pattern.hasPrefix("."), pattern.dropFirst().allSatisfy({ $0 != "." }), pattern.count > 1 {
            return name.hasSuffix(pattern) && name.count > pattern.count
        }
        return false
    }

    /// True when an ignore pattern would hide real footage or photos (Settings warns about it,
    /// because ignored files aren't offloaded and Format would erase them).
    static func ignoresMainMedia(_ pattern: String) -> Bool {
        let samples = (MediaCategory.videoExtensions.union(MediaCategory.photoExtensions))
            .flatMap { ["C0001.\($0)", "C0001.\($0.uppercased())", "DCIM/GX010001.\($0)"] }
        return samples.contains { matches(($0 as NSString).lastPathComponent, pattern: pattern) }
    }

    // MARK: Cleaning user input

    /// ".LRV", "*.lrv", " lrv " → "lrv". `nil` when nothing usable is left.
    static func cleanExtension(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespaces).lowercased()
        while text.hasPrefix("*") || text.hasPrefix(".") { text.removeFirst() }
        guard !text.isEmpty, !text.contains("/"), !text.contains("."), !text.contains("*"),
              !text.contains(where: \.isWhitespace) else { return nil }
        return text
    }

    /// Cleaned, without duplicates, in the order given.
    static func cleanExtensions(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        return raw.compactMap(cleanExtension).filter { seen.insert($0).inserted }
    }

    /// Trimmed, no empty entries or "/" (patterns match one name), no duplicates (ignoring case).
    static func cleanPatterns(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        return raw.map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.contains("/") }
            .filter { seen.insert($0.lowercased()).inserted }
    }
}
