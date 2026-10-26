import Foundation
import DiskArbitration

/// What Lodge knows about a freshly mounted volume, read once when it mounts.
/// Plain values, so the "should we ask to import?" rules can be unit tested.
struct VolumeTraits: Equatable, Sendable {
    var path: String
    var isRemovable = false
    var isEjectable = false
    /// `nil` when macOS doesn't say (older file systems).
    var isInternal: Bool?
    /// False for network shares (SMB, AFP, NFS…).
    var isLocal = true
    var isRootFileSystem = false
    /// A mounted .dmg / .sparsebundle.
    var isDiskImage = false
    /// A Time Machine (or other backup) volume.
    var isBackup = false

    var logDescription: String {
        "removable \(isRemovable), ejectable \(isEjectable), internal \(isInternal.map(String.init) ?? "unknown"), "
            + "local \(isLocal), root \(isRootFileSystem), disk image \(isDiskImage), backup \(isBackup)"
    }
}

/// A card the user said "Don't ask for this card" about (Settings ▸ General ▸ Menu Bar lists them).
struct IgnoredImportCard: Codable, Hashable, Identifiable, Sendable {
    /// `CardVolume.identity`: the volume UUID, or its name when it has none.
    var identity: String
    /// Shown in Settings.
    var name: String
    var id: String { identity }
}

/// The rules for "A7S III card connected · Import with Lodge?".
enum ImportPromptPolicy {
    enum Verdict: Equatable {
        case prompt
        case skip(Reason)
    }

    enum Reason: Equatable {
        /// The startup disk or anything outside /Volumes.
        case system
        case network
        case diskImage
        /// A fixed internal disk, or a drive that's neither removable nor ejectable.
        case notExternal
        case backup
        /// The current destination drive or a favorite destination's drive.
        case destination
        /// "Don't ask for this card".
        case ignored
        /// No DCIM, PRIVATE/M4ROOT, … and no photos, video or audio near the top.
        case notCameraMedia
    }

    static func verdict(for traits: VolumeTraits, identity: String, looksLikeCameraMedia: Bool,
                        destinationPaths: [String], ignored: Set<String>) -> Verdict {
        guard traits.path.hasPrefix("/Volumes/"), !traits.isRootFileSystem else { return .skip(.system) }
        guard traits.isLocal else { return .skip(.network) }
        guard !traits.isDiskImage else { return .skip(.diskImage) }
        guard isPluggableMedia(traits) else { return .skip(.notExternal) }
        guard !traits.isBackup else { return .skip(.backup) }
        if destinationPaths.contains(where: { isPath($0, onVolume: traits.path) }) { return .skip(.destination) }
        guard !ignored.contains(identity) else { return .skip(.ignored) }
        guard looksLikeCameraMedia else { return .skip(.notCameraMedia) }
        return .prompt
    }

    /// Removable media counts wherever the reader is: a Mac's built-in SD slot reports its
    /// cards as internal *and* removable. Other drives count when they're external and ejectable
    /// (USB and Thunderbolt SSDs). Fixed internal disks never do.
    static func isPluggableMedia(_ traits: VolumeTraits) -> Bool {
        traits.isRemovable || (traits.isInternal != true && traits.isEjectable)
    }

    /// True when `path` is the volume itself or something inside it.
    static func isPath(_ path: String, onVolume volume: String) -> Bool {
        let volume = volume.hasSuffix("/") ? volume : volume + "/"
        let path = path.hasSuffix("/") ? path : path + "/"
        return path.hasPrefix(volume)
    }
}

/// Holds back a second prompt for the same card when it mounts twice in a row
/// (card readers and exFAT repairs often unmount and remount within seconds).
struct MountDebouncer {
    var interval: TimeInterval = 20
    private var lastPrompt: [String: Date] = [:]

    init(interval: TimeInterval = 20) { self.interval = interval }

    /// True (and remembered) when `identity` hasn't been prompted for within `interval`.
    mutating func shouldPrompt(_ identity: String, now: Date = Date()) -> Bool {
        if let last = lastPrompt[identity], now.timeIntervalSince(last) < interval { return false }
        lastPrompt[identity] = now
        return true
    }
}

/// "Does this look like it came out of a camera?", from the folders cameras write.
enum CameraMedia {
    /// Folders cameras and recorders create, relative to the card's root (compared case-insensitively).
    static let markerFolders: [String] = [
        "DCIM",               // stills and most cameras/drones/phones (DCF)
        "PRIVATE/M4ROOT",     // Sony XAVC
        "PRIVATE/AVCHD", "AVCHD",
        "XDROOT", "PRIVATE/XDROOT", // Sony XDCAM
        "BPAV",               // Sony XDCAM EX
        "CONTENTS",           // Panasonic P2
        "MP_ROOT",            // Sony stills/video (older)
        "CLIPS001",           // Canon Cinema RAW Light / XF-AVC
        "XFAVC",
        "PRIVATE/PANA_GRP",   // Panasonic
        "PRIVATE/CANON",
        "BLACKMAGIC",
    ]

    /// Lists a folder's entries (names only), or `nil` if it can't be read. Tests swap in a fake.
    typealias Lister = (_ path: String) -> [String]?

    /// A camera folder at the root, or photo/video/audio files at the root or one folder down
    /// (Blackmagic, Atomos and audio recorders write clips straight into the root or a folder).
    static func looksLikeCameraMedia(root: String, list: Lister = diskList) -> Bool {
        guard let top = list(root) else { return false }
        let visible = top.filter { !$0.hasPrefix(".") }
        let upper = Set(visible.map { $0.uppercased() })
        for marker in markerFolders {
            let parts = marker.split(separator: "/").map(String.init)
            if parts.count == 1 {
                if upper.contains(marker) { return true }
            } else if let first = visible.first(where: { $0.uppercased() == parts[0] }),
                      let inner = list(root + "/" + first),
                      inner.contains(where: { $0.uppercased() == parts[1] }) {
                return true
            }
        }
        if visible.prefix(300).contains(where: isMedia) { return true }
        // One level down, a few folders only (so a big ordinary drive stays quick).
        for folder in visible.prefix(12) where (folder as NSString).pathExtension.isEmpty {
            guard let inner = list(root + "/" + folder) else { continue }
            if inner.prefix(300).contains(where: { !$0.hasPrefix(".") && isMedia($0) }) { return true }
        }
        return false
    }

    static func isMedia(_ name: String) -> Bool {
        MediaCategory.classify(fileName: name) != .other
    }

    static let diskList: Lister = { path in
        try? FileManager.default.contentsOfDirectory(atPath: path)
    }
}

extension VolumeTraits {
    /// Reads a mounted volume's traits from the file system and Disk Arbitration.
    static func read(_ url: URL) -> VolumeTraits {
        let keys: Set<URLResourceKey> = [.volumeIsRemovableKey, .volumeIsEjectableKey, .volumeIsInternalKey,
                                         .volumeIsLocalKey, .volumeIsRootFileSystemKey]
        let values = try? url.resourceValues(forKeys: keys)
        var traits = VolumeTraits(path: url.path)
        traits.isRemovable = values?.volumeIsRemovable ?? false
        traits.isEjectable = values?.volumeIsEjectable ?? false
        traits.isInternal = values?.volumeIsInternal
        traits.isLocal = values?.volumeIsLocal ?? true
        traits.isRootFileSystem = values?.volumeIsRootFileSystem ?? false
        traits.isDiskImage = isDiskImage(url)
        traits.isBackup = isBackup(url)
        return traits
    }

    /// Disk images report "Disk Image" as their device model (and protocol, on newer macOS).
    private static func isDiskImage(_ url: URL) -> Bool {
        guard let session = DASessionCreate(kCFAllocatorDefault),
              let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, url as CFURL),
              let description = DADiskCopyDescription(disk) as? [CFString: Any] else { return false }
        let model = (description[kDADiskDescriptionDeviceModelKey] as? String ?? "").trimmingCharacters(in: .whitespaces)
        let proto = description[kDADiskDescriptionDeviceProtocolKey] as? String ?? ""
        return model == "Disk Image" || proto == "Disk Image" || proto == "Virtual Interface"
    }

    /// Time Machine marks its volumes; older HFS+ backups keep a Backups.backupdb folder.
    private static func isBackup(_ url: URL) -> Bool {
        let fm = FileManager.default
        return [".com.apple.timemachine.donotpresent", "Backups.backupdb", ".com.apple.TMCheckpoint"]
            .contains { fm.fileExists(atPath: url.appendingPathComponent($0).path) }
    }
}
