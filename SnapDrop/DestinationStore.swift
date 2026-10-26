import Foundation
import AppKit

/// A folder you offload to often, like "Footage SSD" or "Client Deliveries".
struct FavoriteDestination: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    /// Absolute folder path.
    var path: String
    /// A Finder-style bookmark, so a folder that was moved or renamed can still be found.
    var bookmark: Data?

    init(id: UUID = UUID(), name: String, path: String, bookmark: Data? = nil) {
        self.id = id
        self.name = name
        self.path = path
        self.bookmark = bookmark
    }

    var url: URL { URL(fileURLWithPath: path, isDirectory: true) }

    /// Name for menus (never blank).
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? url.lastPathComponent : trimmed
    }

    var abbreviatedPath: String { (path as NSString).abbreviatingWithTildeInPath }

    /// An external drive gets a drive icon, everything else a folder.
    var symbol: String { path.hasPrefix("/Volumes/") ? "externaldrive.fill" : "folder.fill" }
}

/// The favorite destinations, which one is the default and which was used last.
/// Saved as JSON at ~/Library/Application Support/SnapDrop/destinations.json.
@MainActor
final class DestinationStore: ObservableObject {
    @Published private(set) var favorites: [FavoriteDestination] = []
    /// The favorite SnapDrop falls back to when the last one used isn't connected.
    @Published private(set) var defaultID: UUID?
    /// The favorite picked most recently (`nil` when the last pick was some other folder).
    @Published private(set) var lastUsedID: UUID?
    @Published private(set) var lastError: String?
    /// Bumped whenever a drive mounts or unmounts, so "Not connected" labels stay current.
    @Published private(set) var mountRevision = 0

    /// `nil` keeps everything in memory (previews, demo mode, tests).
    let fileURL: URL?
    /// Is the folder at this path there right now? (Injected by tests.)
    let folderExists: (String) -> Bool
    /// True once a saved list was read, so the one-time migration never runs again.
    private var loadedSavedList = false
    private var observers: [NSObjectProtocol] = []

    nonisolated static var defaultFileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support
            .appendingPathComponent("SnapDrop", isDirectory: true)
            .appendingPathComponent("destinations.json")
    }

    nonisolated static func isFolder(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private struct Stored: Codable {
        var favorites: [FavoriteDestination]
        var defaultID: UUID?
        var lastUsedID: UUID?
    }

    init(fileURL: URL? = DestinationStore.defaultFileURL, favorites: [FavoriteDestination] = [],
         defaultID: UUID? = nil, folderExists: @escaping (String) -> Bool = DestinationStore.isFolder) {
        self.fileURL = fileURL
        self.folderExists = folderExists
        self.favorites = favorites
        self.defaultID = defaultID ?? favorites.first?.id
        load()
        findMovedFolders()
    }

    /// Watches drives coming and going (refreshes "Not connected"). The app's store lives
    /// as long as the app, so the observers are never removed.
    func startWatchingDrives() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.drivesChanged() }
            })
        }
    }

    func drivesChanged() {
        mountRevision += 1
        findMovedFolders()
    }

    // MARK: Looking up

    func favorite(id: UUID?) -> FavoriteDestination? {
        guard let id else { return nil }
        return favorites.first { $0.id == id }
    }

    /// The favorite for a folder path, if it is one.
    func favorite(forPath path: String?) -> FavoriteDestination? {
        guard let path else { return nil }
        let wanted = Self.normalized(path)
        return favorites.first { Self.normalized($0.path) == wanted }
    }

    var defaultFavorite: FavoriteDestination? { favorite(id: defaultID) ?? favorites.first }

    /// False when the folder is missing, e.g. its drive isn't plugged in.
    func isConnected(_ favorite: FavoriteDestination) -> Bool {
        folderExists(favorite.path)
    }

    /// The folder to use when SnapDrop starts. The default favorite is the one source of truth
    /// (Settings ▸ Destinations); if its drive isn't connected, the favorite used last, then any
    /// connected favorite. A folder picked with "Choose Other Folder…" only lasts until then.
    func launchDestination(currentPath: String?) -> String? {
        if let preferred = defaultFavorite, isConnected(preferred) { return preferred.path }
        if let last = favorite(id: lastUsedID), isConnected(last) { return last.path }
        if let any = favorites.first(where: isConnected) { return any.path }
        if favorites.isEmpty, let currentPath, folderExists(currentPath) { return currentPath }
        return defaultFavorite?.path ?? currentPath
    }

    // MARK: Migration

    /// The first time favorites exist, the single destination chosen before becomes the
    /// first favorite (named after its folder) and the default. Returns true if it did.
    @discardableResult
    func migrate(legacyPath: String?) -> Bool {
        guard !loadedSavedList, favorites.isEmpty, let legacyPath, !legacyPath.isEmpty else { return false }
        let favorite = makeFavorite(path: legacyPath, name: URL(fileURLWithPath: legacyPath).lastPathComponent)
        favorites = [favorite]
        defaultID = favorite.id
        lastUsedID = favorite.id
        save()
        return true
    }

    /// The old Settings ▸ General ▸ Destination folder joins the favorites (once; the app keeps a
    /// flag). The first favorite becomes the default; otherwise the default is left alone.
    /// Returns true if a favorite was added.
    @discardableResult
    func adoptLegacyDestination(_ path: String?) -> Bool {
        guard let path, !path.isEmpty, favorite(forPath: path) == nil else { return false }
        if migrate(legacyPath: path) { return true }
        let wasEmpty = favorites.isEmpty
        let favorite = add(path: path)
        if wasEmpty { lastUsedID = favorite.id; save() }
        return true
    }

    // MARK: Editing

    /// Adds a favorite for `path` (or returns the existing one) with a unique name.
    @discardableResult
    func add(path: String, name: String? = nil) -> FavoriteDestination {
        if let existing = favorite(forPath: path) { return existing }
        let base = name ?? URL(fileURLWithPath: path).lastPathComponent
        var candidate = base
        var number = 2
        while favorites.contains(where: { $0.displayName.caseInsensitiveCompare(candidate) == .orderedSame }) {
            candidate = "\(base) \(number)"
            number += 1
        }
        let favorite = makeFavorite(path: path, name: candidate)
        favorites.append(favorite)
        if defaultID == nil { defaultID = favorite.id }
        save()
        return favorite
    }

    func rename(_ id: UUID, to name: String) {
        guard let index = favorites.firstIndex(where: { $0.id == id }), favorites[index].name != name else { return }
        favorites[index].name = name
        save()
    }

    func setPath(_ id: UUID, to path: String) {
        guard let index = favorites.firstIndex(where: { $0.id == id }), favorites[index].path != path else { return }
        favorites[index].path = path
        favorites[index].bookmark = Self.bookmark(for: path)
        save()
    }

    func setDefault(_ id: UUID) {
        guard favorite(id: id) != nil, defaultID != id else { return }
        defaultID = id
        save()
    }

    func delete(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        favorites.removeAll { ids.contains($0.id) }
        if let id = defaultID, ids.contains(id) { defaultID = favorites.first?.id }
        if let id = lastUsedID, ids.contains(id) { lastUsedID = nil }
        save()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.sorted().map { favorites[$0] }
        var remaining = favorites
        for index in source.sorted(by: >) { remaining.remove(at: index) }
        let insertAt = destination - source.filter { $0 < destination }.count
        remaining.insert(contentsOf: moving, at: max(0, min(insertAt, remaining.count)))
        favorites = remaining
        save()
    }

    /// Remembers which favorite was picked (`nil` for "some other folder").
    func markUsed(_ id: UUID?) {
        let id = favorite(id: id)?.id
        guard lastUsedID != id else { return }
        lastUsedID = id
        save()
    }

    // MARK: Moved folders

    /// A favorite whose folder is gone, but whose bookmark points somewhere that exists
    /// (the folder was renamed or moved), follows it. Never mounts anything or shows UI.
    private func findMovedFolders() {
        var changed = false
        for index in favorites.indices where !folderExists(favorites[index].path) {
            guard let bookmark = favorites[index].bookmark else { continue }
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting],
                                     relativeTo: nil, bookmarkDataIsStale: &stale),
                  url.path != favorites[index].path, folderExists(url.path) else { continue }
            favorites[index].path = url.path
            if stale { favorites[index].bookmark = Self.bookmark(for: url.path) }
            changed = true
        }
        if changed { save() }
    }

    private func makeFavorite(path: String, name: String) -> FavoriteDestination {
        FavoriteDestination(name: name, path: path, bookmark: Self.bookmark(for: path))
    }

    private static func bookmark(for path: String) -> Data? {
        try? URL(fileURLWithPath: path, isDirectory: true)
            .bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    nonisolated static func normalized(_ path: String) -> String {
        var result = (path as NSString).standardizingPath
        while result.count > 1 && result.hasSuffix("/") { result.removeLast() }
        return result
    }

    // MARK: Disk

    private func load() {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let stored = try JSONDecoder().decode(Stored.self, from: Data(contentsOf: fileURL))
            favorites = stored.favorites
            defaultID = stored.defaultID.flatMap { id in favorites.contains { $0.id == id } ? id : nil } ?? favorites.first?.id
            lastUsedID = stored.lastUsedID
            loadedSavedList = true
        } catch {
            // Don't migrate on top of a list we couldn't read; just say so.
            loadedSavedList = true
            lastError = "Couldn’t read your favorite destinations: \(error.localizedDescription)"
        }
    }

    private func save() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(Stored(favorites: favorites, defaultID: defaultID, lastUsedID: lastUsedID))
            try data.write(to: fileURL, options: .atomic)
            lastError = nil
        } catch {
            lastError = "Couldn’t save your favorite destinations: \(error.localizedDescription)"
        }
    }
}
