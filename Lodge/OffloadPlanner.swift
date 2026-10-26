import Foundation

/// Where one file from the card will go. The plan is worked out before copying and is
/// shown as the live preview, so what you see is exactly what you get.
struct PlannedFile: Identifiable, Equatable, Sendable {
    let clip: Clip
    /// Folder inside the destination, e.g. "2026-10-25/Coastline" ("" = the destination itself).
    let folder: String
    /// "2026-10-25_Coastline_0001.mp4"
    let fileName: String
    /// For sidecars (e.g. C0001M01.XML): the original name of the clip it belongs to.
    let sidecarOf: String?
    /// Proxies and sidecars go into their own subfolder of the shoot folder.
    var role: FileRole = .main

    var id: String { clip.relativePath }
    var originalName: String { clip.url.lastPathComponent }
    var size: Int64 { clip.size }
    var category: MediaCategory { clip.category }
    /// "2026-10-25/Coastline/2026-10-25_Coastline_0001.mp4"
    var relativePath: String { folder.isEmpty ? fileName : folder + "/" + fileName }
}

/// Works out final names for a batch of files: applies the templates, continues
/// numbering after what's already in each folder, and never reuses a name.
enum OffloadPlanner {
    /// Lists what is already in a destination folder ("" = the destination itself).
    typealias ExistingNames = (_ folder: String) -> [String]

    static func plan(
        files: [Clip],
        naming: NamingTemplates,
        context: NamingContext,
        rules: FileRules = .standard,
        existingNames: @escaping ExistingNames
    ) -> [PlannedFile] {
        var names = NameBook(existingNames: existingNames)
        var counters: [String: Int] = [:]
        var result: [PlannedFile] = []

        let ordered = Offloader.order(files)
        let sidecars = SidecarMatcher.match(ordered, rules: rules)

        for file in ordered where sidecars.primary[file.relativePath] == nil {
            let folder = TemplateRenderer.folderPath(naming.folder, file: file, context: context)
            let ext = file.url.pathExtension.lowercased()
            let role = rules.role(of: file.url.lastPathComponent)

            // A proxy or sidecar without its clip (MEDIAPRO.XML, a lone .LRV…) keeps its own name
            // in the subfolder, so it doesn't use up a sequence number.
            if let subfolder = role.folderName {
                let target = subfolderPath(folder, subfolder)
                let original = (file.url.lastPathComponent as NSString).deletingPathExtension
                let name = names.unique(stem: NameRules.safeComponent(original), ext: ext, in: target)
                names.reserve(name, in: target)
                result.append(PlannedFile(clip: file, folder: target, fileName: name, sidecarOf: nil, role: role))
                continue
            }

            let stem = TemplateRenderer.fileStem(naming.file, file: file, context: context)
            let fileName: String

            if stem.padding != nil {
                // Numbered: continue after the highest number already used with this prefix.
                let prefix = stem.before.trimmingLeadingDotsAndSpaces()
                let key = folder.lowercased() + "\u{0}" + prefix.lowercased() + "\u{0}" + stem.fixedAfter.lowercased()
                var number = counters[key] ?? (highestSequence(
                    in: names.names(in: folder), prefix: prefix, fixedAfter: stem.fixedAfter,
                    endsAfterFixed: stem.afterIsFixed) + 1)
                var attempts = 0
                while names.isTaken(join(stem.name(sequence: number), ext), in: folder), attempts < 100_000 {
                    // A name so long the number was cut off can't be fixed by counting up.
                    if stem.name(sequence: number + 1) == stem.name(sequence: number) { break }
                    number += 1
                    attempts += 1
                }
                // (Only if a name was so long the number got cut off: fall back to "_2" suffixes.)
                fileName = names.unique(stem: stem.name(sequence: number), ext: ext, in: folder)
                counters[key] = number + 1
            } else {
                fileName = names.unique(stem: stem.name(sequence: nil), ext: ext, in: folder)
            }
            names.reserve(fileName, in: folder)
            result.append(PlannedFile(clip: file, folder: folder, fileName: fileName, sidecarOf: nil))

            // Sidecars (C0001M01.XML, GL010001.LRV, C0001.WAV…) follow their clip with the same new
            // name: next to it, or in its Proxies/ or Sidecars/ subfolder.
            let newStem = ext.isEmpty ? fileName : String(fileName.dropLast(ext.count + 1))
            for sidecar in sidecars.byPrimary[file.relativePath] ?? [] {
                let sidecarExt = sidecar.file.url.pathExtension.lowercased()
                let target = sidecar.role.folderName.map { subfolderPath(folder, $0) } ?? folder
                let sidecarName = names.unique(stem: newStem + sidecar.suffix, ext: sidecarExt, in: target)
                names.reserve(sidecarName, in: target)
                result.append(PlannedFile(clip: sidecar.file, folder: target, fileName: sidecarName,
                                          sidecarOf: file.url.lastPathComponent, role: sidecar.role))
            }
        }
        return result
    }

    /// The highest number in names shaped like `<prefix><digits><fixedAfter>…` (0 if none).
    /// With `endsAfterFixed`, the name must end right there (only an extension may follow).
    /// Comparison ignores case, like the Mac's file system.
    static func highestSequence(in names: [String], prefix: String, fixedAfter: String,
                                endsAfterFixed: Bool = false) -> Int {
        let lowerPrefix = prefix.lowercased()
        let lowerAfter = fixedAfter.lowercased()
        var highest = 0
        for name in names {
            let lower = name.lowercased()
            guard lower.hasPrefix(lowerPrefix) else { continue }
            let rest = lower.dropFirst(lowerPrefix.count)
            let digits = rest.prefix { $0.isASCII && $0.isNumber }
            let tail = rest.dropFirst(digits.count)
            guard !digits.isEmpty, tail.hasPrefix(lowerAfter),
                  let value = Int(digits.prefix(9)) else { continue }
            if endsAfterFixed {
                let end = tail.dropFirst(lowerAfter.count)
                guard end.isEmpty || end.hasPrefix(".") else { continue }
            }
            highest = max(highest, value)
        }
        return highest
    }

    /// "name.ext" (or just "name" for files without an extension).
    static func join(_ stem: String, _ ext: String) -> String {
        ext.isEmpty ? stem : stem + "." + ext
    }

    /// "2026-10-25/Coastline" + "Proxies" (or just "Proxies" at the destination itself).
    static func subfolderPath(_ folder: String, _ subfolder: String) -> String {
        folder.isEmpty ? subfolder : folder + "/" + subfolder
    }

    /// A folder lister that reads the real destination (each folder read once).
    static func diskLister(root: URL?) -> ExistingNames {
        let cache = ListingCache()
        return { folder in
            guard let root else { return [] }
            if let cached = cache.entries[folder] { return cached }
            let url = folder.isEmpty ? root : root.appendingPathComponent(folder, isDirectory: true)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
            cache.entries[folder] = names
            return names
        }
    }

    private final class ListingCache {
        var entries: [String: [String]] = [:]
    }

    /// Last-moment safety net while copying: if `url` (or its partial file) exists,
    /// returns "name_2.ext", "name_3.ext"… instead. Never overwrites anything.
    static func freeURL(for url: URL, fileManager: FileManager = .default) -> URL {
        func taken(_ candidate: URL) -> Bool {
            fileManager.fileExists(atPath: candidate.path)
                || fileManager.fileExists(atPath: Copier.partialURL(for: candidate).path)
        }
        guard taken(url) else { return url }
        let folder = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let stem = url.deletingPathExtension().lastPathComponent
        var suffix = 2
        while true {
            let candidate = folder.appendingPathComponent(join("\(stem)_\(suffix)", ext))
            if !taken(candidate) { return candidate }
            suffix += 1
        }
    }
}

/// Finds sidecar files: "other" or audio files (and anything listed as a proxy or sidecar in
/// `FileRules`) that belong to a photo or video because they share its name in the same card
/// folder — exactly ("C0001.XML", "DJI_0001.LRF"), with Sony's metadata suffix ("C0001M01.XML"),
/// or as a GoPro low-res proxy ("GL010001.LRV" for "GX010001.MP4").
enum SidecarMatcher {
    struct Sidecar: Equatable {
        let file: Clip
        /// Extra text kept after the new name, e.g. "M01" ("" for an exact match).
        let suffix: String
        /// `.proxy` and `.sidecar` go into their own subfolder; `.main` stays next to the clip.
        var role: FileRole = .main
    }

    struct Result {
        /// Primary file's card path → its sidecars, in card-path order.
        var byPrimary: [String: [Sidecar]] = [:]
        /// Sidecar's card path → its primary file's card path.
        var primary: [String: String] = [:]
    }

    /// `files` must already be in offload order; the first matching photo/video wins.
    static func match(_ files: [Clip], rules: FileRules = .standard) -> Result {
        var primaries: [String: String] = [:]   // "folder|stem" (lowercased) → card path
        for file in files where file.category.isPrimaryMedia && rules.role(of: file.url.lastPathComponent) == .main {
            let key = Self.key(folder: folder(of: file), stem: stem(of: file))
            if primaries[key] == nil { primaries[key] = file.relativePath }
        }

        var result = Result()
        let candidates = files
            .filter { $0.category == .other || $0.category == .audio
                || rules.role(of: $0.url.lastPathComponent) != .main }
            .sorted { $0.relativePath < $1.relativePath }
        for file in candidates {
            let folder = folder(of: file)
            let stem = stem(of: file)
            var match: (primary: String, suffix: String)?
            if let primary = primaries[key(folder: folder, stem: stem)] {
                match = (primary, "")
            } else if let suffix = sonySuffix(of: stem),
                      let primary = primaries[key(folder: folder, stem: String(stem.dropLast(suffix.count)))] {
                match = (primary, suffix)
            } else if let primary = goProStems(forProxy: stem).lazy
                        .compactMap({ primaries[key(folder: folder, stem: $0)] }).first {
                match = (primary, "")
            }
            guard let match, match.primary != file.relativePath else { continue }
            let role = rules.role(of: file.url.lastPathComponent)
            result.byPrimary[match.primary, default: []].append(
                Sidecar(file: file, suffix: match.suffix, role: role))
            result.primary[file.relativePath] = match.primary
        }
        return result
    }

    /// "M01" from "C0001M01" (an "M" plus two digits at the end, after at least one character).
    static func sonySuffix(of stem: String) -> String? {
        let characters = Array(stem)
        guard characters.count > 3 else { return nil }
        let tail = characters.suffix(3)
        guard let m = tail.first, m == "M" || m == "m",
              tail.dropFirst().allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return String(tail)
    }

    /// GoPro names its low-res proxy "GL010001.LRV" for the clip "GX010001.MP4" (or "GH…" on
    /// older cameras). Returns the clip names to look for, or nothing if it isn't a "GL" name.
    static func goProStems(forProxy stem: String) -> [String] {
        guard stem.count > 2, stem.uppercased().hasPrefix("GL") else { return [] }
        let rest = stem.dropFirst(2)
        let upper = stem.hasPrefix("GL")
        return upper ? ["GX" + rest, "GH" + rest] : ["gx" + rest, "gh" + rest]
    }

    private static func folder(of file: Clip) -> String {
        (file.relativePath as NSString).deletingLastPathComponent
    }

    private static func stem(of file: Clip) -> String {
        (file.url.lastPathComponent as NSString).deletingPathExtension
    }

    private static func key(folder: String, stem: String) -> String {
        folder.lowercased() + "|" + stem.lowercased()
    }
}

/// Keeps track of names that exist on disk or were already handed out in this plan.
private struct NameBook {
    let existingNames: OffloadPlanner.ExistingNames
    private var taken: [String: Set<String>] = [:]
    private var listed: [String: [String]] = [:]

    init(existingNames: @escaping OffloadPlanner.ExistingNames) {
        self.existingNames = existingNames
    }

    mutating func names(in folder: String) -> [String] {
        let key = folder.lowercased()
        if let names = listed[key] { return names }
        let names = existingNames(folder).map { name in
            LegacyMigration.withoutPartialSuffix(name)
        }
        listed[key] = names
        taken[key, default: []].formUnion(names.map { $0.lowercased() })
        return names
    }

    mutating func isTaken(_ name: String, in folder: String) -> Bool {
        _ = names(in: folder)
        return taken[folder.lowercased(), default: []].contains(name.lowercased())
    }

    mutating func reserve(_ name: String, in folder: String) {
        _ = names(in: folder)
        taken[folder.lowercased(), default: []].insert(name.lowercased())
    }

    /// "stem.ext", or "stem_2.ext", "stem_3.ext"… if that's taken.
    mutating func unique(stem: String, ext: String, in folder: String) -> String {
        var candidate = OffloadPlanner.join(stem, ext)
        var suffix = 2
        while isTaken(candidate, in: folder) {
            candidate = OffloadPlanner.join("\(stem)_\(suffix)", ext)
            suffix += 1
        }
        return candidate
    }
}

private extension String {
    func trimmingLeadingDotsAndSpaces() -> String {
        String(drop { $0 == "." || $0 == " " })
    }
}
