import AppKit

/// "Show in Finder" in one Finder window. Handing Finder many files at once opens a window per
/// folder they're in (an offload into dated or per-camera folders opened a whole stack), so
/// several files open the folder they share instead, and one file is selected in its folder.
enum FinderReveal {
    enum Target: Equatable {
        /// Open Finder on the folder that holds this item, with the item selected.
        case select(URL)
        /// Open this folder in Finder.
        case open(URL)
    }

    /// What to show for the copied `files` of an offload into `destination`.
    static func target(files: [URL], destination: URL?) -> Target? {
        let files = Array(Set(files.map(\.standardizedFileURL))).sorted { $0.path < $1.path }
        if files.count == 1 { return .select(files[0]) }
        let destination = destination?.standardizedFileURL
        guard let first = files.first else { return destination.map(Target.open) }
        // The deepest folder every file is in.
        var shared = first.deletingLastPathComponent().pathComponents
        for file in files.dropFirst() {
            let parent = file.deletingLastPathComponent().pathComponents
            shared = Array(zip(shared, parent).prefix { $0 == $1 }.map(\.0))
        }
        let folder = URL(fileURLWithPath: NSString.path(withComponents: shared), isDirectory: true)
        // Files that only share "/" or a whole volume (shouldn't happen): the destination instead.
        if shared.count <= 1 || (shared.count <= 3 && shared.first == "/" && shared[1] == "Volumes") {
            return .open(destination ?? folder)
        }
        return .open(folder)
    }

    static func show(_ target: Target?) {
        switch target {
        case .select(let url): NSWorkspace.shared.activateFileViewerSelecting([url])
        case .open(let folder): NSWorkspace.shared.open(folder)
        case nil: break
        }
    }

    static func show(files: [URL], destination: URL?) {
        show(target(files: files, destination: destination))
    }
}
