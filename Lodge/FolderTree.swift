import Foundation

/// The folders an offload creates, as a tree (the Destination stage's Layout).
/// Built from the plan, so it shows exactly what will be made. Pure, so it's unit tested.
struct FolderNode: Identifiable, Equatable, Sendable {
    /// "A7S3"; the destination's own name for the root.
    var name: String
    /// Inside the destination: "Coastline/2026-10-25/A7S3" ("" = the destination itself).
    var path: String
    /// 0 for the destination, 1 for the first level…
    var depth: Int
    var children: [FolderNode] = []
    /// Files copied straight into this folder, in plan order.
    var files: [PlannedFile] = []
    /// "Proxies" or "Sidecars": made for proxy and sidecar files, not by the templates.
    var isRoleFolder = false
    /// "MP4", "ARW", "WAV"…: the folder for one file extension, made by Lodge, not the templates.
    var isFormatFolder = false

    var id: String { path }

    /// Every file in this folder and the ones below it.
    var fileCount: Int { files.count + children.reduce(0) { $0 + $1.fileCount } }

    /// This folder and every folder below it, depth first.
    var allPaths: [String] { [path] + children.flatMap(\.allPaths) }

    /// The folder at `path`, if it's in this tree.
    func node(at path: String) -> FolderNode? {
        if self.path == path { return self }
        for child in children where path == child.path || path.hasPrefix(child.path + "/") {
            return child.node(at: path)
        }
        return nil
    }
}

enum FolderTree {
    /// The tree of every folder in `plan`, with each file in its folder.
    /// Folders are sorted like the Finder; Proxies and Sidecars come after the others.
    static func build(rootName: String, plan: [PlannedFile]) -> FolderNode {
        final class Box {
            var name: String
            var path: String
            var depth: Int
            var children: [String: Box] = [:]
            var files: [PlannedFile] = []
            init(name: String, path: String, depth: Int) { self.name = name; self.path = path; self.depth = depth }
        }
        let root = Box(name: rootName, path: "", depth: 0)
        for file in plan {
            var box = root
            for component in file.folder.split(separator: "/").map(String.init) where !component.isEmpty {
                let key = component.lowercased()
                if let existing = box.children[key] {
                    box = existing
                } else {
                    let path = box.path.isEmpty ? component : box.path + "/" + component
                    let child = Box(name: component, path: path, depth: box.depth + 1)
                    box.children[key] = child
                    box = child
                }
            }
            box.files.append(file)
        }
        let roleFolders = Set([FileRole.proxy, .sidecar].compactMap(\.folderName))
        func node(_ box: Box) -> FolderNode {
            let children = box.children.values
                .map(node)
                .sorted { a, b in
                    if a.isRoleFolder != b.isRoleFolder { return !a.isRoleFolder }
                    return a.name.localizedStandardCompare(b.name) == .orderedAscending
                }
            // A role folder holds only proxies or sidecars.
            let isRole = roleFolders.contains(box.name) && !box.files.isEmpty
                && box.files.allSatisfy { $0.role != .main } && box.children.isEmpty
            // A format folder holds the files Lodge sorted into it by extension.
            let isFormat = !isRole && !box.files.isEmpty && box.children.isEmpty
                && box.files.allSatisfy { $0.role == .main && $0.sortFolder == box.name && $0.folder == box.path }
            return FolderNode(name: box.name, path: box.path, depth: box.depth,
                              children: children, files: box.files, isRoleFolder: isRole, isFormatFolder: isFormat)
        }
        return node(root)
    }

    /// Folders already on disk that the offload doesn't use, sorted like the Finder.
    /// Matching ignores case, like the Mac's file system.
    static func otherFolders(onDisk: [String], planned: [String]) -> [String] {
        let used = Set(planned.map { $0.lowercased() })
        return onDisk
            .filter { !used.contains($0.lowercased()) && !$0.hasPrefix(".") }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// The template level each tree depth shows (depth 1 = the first level kept).
    /// Quick dump can leave levels out, so depths and template levels don't always line up.
    static func levelIndices(template: String, quickDump: Bool) -> [Int] {
        FolderTemplateEditor.levels(template).enumerated()
            .filter { !quickDump || !QuickDump.strip($0.element).isEmpty }
            .map(\.offset)
    }

    /// How one piece of a level ("{date}") comes out for a file: "2026-10-25".
    /// Empty if it has no value; nil if the piece isn't valid on its own.
    static func render(piece: String, file: Clip, context: NamingContext) -> String? {
        guard let template = NamingTemplate.parse(piece, kind: .folder).template,
              let parts = template.components.first else { return nil }
        return NameRules.safeComponent(TemplateRenderer.renderLevel(parts, file: file, context: context))
    }
}

/// Reads which folders exist under the destination, once per folder until `refresh()`.
@MainActor
final class FolderListing: ObservableObject {
    /// Subfolder names of a folder, or nil if it doesn't exist.
    typealias Lister = (URL) -> [String]?

    @Published private(set) var revision = 0
    private var cache: [String: [String]?] = [:]

    /// Names of the folders inside `path` (relative to `root`), or nil if it doesn't exist.
    func subfolders(root: URL, path: String, using lister: Lister) -> [String]? {
        let key = root.path + "\u{0}" + path
        if let cached = cache[key] { return cached }
        let url = path.isEmpty ? root : root.appendingPathComponent(path, isDirectory: true)
        let names = lister(url)
        cache[key] = names
        return names
    }

    func refresh() {
        cache = [:]
        revision += 1
    }

    /// The real disk: visible folders only (no packages such as a Photos library), at most 500.
    nonisolated static func diskSubfolders(_ url: URL) -> [String]? {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder), isFolder.boolValue else { return nil }
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
        let items = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys,
                                                                   options: [.skipsHiddenFiles])) ?? []
        return items.compactMap { item -> String? in
            let values = try? item.resourceValues(forKeys: Set(keys))
            guard values?.isDirectory == true, values?.isPackage != true else { return nil }
            return item.lastPathComponent
        }
        .prefix(500)
        .map { $0 }
    }
}
