import Foundation
import AppKit

/// A memory card (or other removable drive) that is mounted under /Volumes.
struct CardVolume: Identifiable, Hashable, Sendable {
    /// Where the card is mounted, e.g. /Volumes/Untitled
    let url: URL
    /// The card's name as shown in Finder.
    let name: String
    /// The volume's UUID, if the file system has one (FAT/exFAT cards usually do).
    let uuid: String?

    var id: String { url.path }

    /// What we use to recognise this card again later: its UUID, or its name as a fallback.
    var identity: String { uuid ?? name }
}

/// Pure decision logic for "is this mounted volume a card we care about?".
/// Kept separate from `VolumeWatcher` so it can be unit tested.
enum VolumeFilter {
    static func isCandidate(
        path: String,
        isRemovable: Bool,
        isEjectable: Bool,
        isRootFileSystem: Bool,
        destinationPath: String?
    ) -> Bool {
        // Only things mounted in /Volumes (this also excludes the startup disk at "/").
        guard path.hasPrefix("/Volumes/") else { return false }
        guard !isRootFileSystem else { return false }
        // Must be a removable or ejectable drive (SD cards, card readers, USB drives).
        guard isRemovable || isEjectable else { return false }
        // Never treat the drive we copy *to* as a card.
        if let destination = destinationPath {
            let volume = path.hasSuffix("/") ? path : path + "/"
            let dest = destination.hasSuffix("/") ? destination : destination + "/"
            if dest.hasPrefix(volume) { return false }
        }
        return true
    }
}

/// Watches for cards being inserted and removed, using NSWorkspace notifications.
@MainActor
final class VolumeWatcher: ObservableObject {
    /// Cards that are currently mounted.
    @Published private(set) var cards: [CardVolume] = []

    /// Called when a new card shows up (also for cards already inserted at launch).
    var onCardInserted: ((CardVolume) -> Void)?
    /// Called when a card is ejected or pulled out.
    var onCardRemoved: ((CardVolume) -> Void)?
    /// Asked for the destination folder so its volume can be ignored.
    var destinationPathProvider: () -> String? = { nil }

    private var observers: [NSObjectProtocol] = []

    private static let resourceKeys: [URLResourceKey] = [
        .volumeNameKey,
        .volumeUUIDStringKey,
        .volumeIsRemovableKey,
        .volumeIsEjectableKey,
        .volumeIsRootFileSystemKey,
    ]

    /// Starts listening for mount/unmount events and checks what's already plugged in.
    func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter

        observers.append(center.addObserver(
            forName: NSWorkspace.didMountNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            // We asked for the main queue above, so we really are on the main thread.
            MainActor.assumeIsolated { self?.volumeMounted(at: url) }
        })

        observers.append(center.addObserver(
            forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            MainActor.assumeIsolated { self?.volumeUnmounted(at: url) }
        })

        // Cards that were inserted before SnapDrop launched.
        let mounted = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Self.resourceKeys,
            options: [.skipHiddenVolumes]
        ) ?? []
        for url in mounted {
            volumeMounted(at: url)
        }
    }

    /// Re-checks the current card list (call after the destination folder changes).
    func refresh() {
        let destination = destinationPathProvider()
        cards.removeAll { card in
            guard let destination else { return false }
            let volume = card.url.path + "/"
            return (destination + "/").hasPrefix(volume)
        }
        let mounted = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Self.resourceKeys,
            options: [.skipHiddenVolumes]
        ) ?? []
        for url in mounted where !cards.contains(where: { $0.url.path == url.path }) {
            if let card = makeCard(from: url) {
                cards.append(card)
            }
        }
    }

    private func volumeMounted(at url: URL) {
        guard let card = makeCard(from: url) else { return }
        guard !cards.contains(where: { $0.id == card.id }) else { return }
        cards.append(card)
        onCardInserted?(card)
    }

    private func volumeUnmounted(at url: URL) {
        let removed = cards.filter { $0.url.path == url.path }
        cards.removeAll { $0.url.path == url.path }
        removed.forEach { onCardRemoved?($0) }
    }

    /// Reads the volume's properties and returns a `CardVolume` if it qualifies.
    private func makeCard(from url: URL) -> CardVolume? {
        guard let values = try? url.resourceValues(forKeys: Set(Self.resourceKeys)) else { return nil }
        let ok = VolumeFilter.isCandidate(
            path: url.path,
            isRemovable: values.volumeIsRemovable ?? false,
            isEjectable: values.volumeIsEjectable ?? false,
            isRootFileSystem: values.volumeIsRootFileSystem ?? false,
            destinationPath: destinationPathProvider()
        )
        guard ok else { return nil }
        return CardVolume(
            url: url,
            name: values.volumeName ?? url.lastPathComponent,
            uuid: values.volumeUUIDString
        )
    }
}
