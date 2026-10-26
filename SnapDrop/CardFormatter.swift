import Foundation

// "Ready to format" and the Format Card… command.
// Everything that decides *whether* a card may be erased is pure and unit tested;
// the only side effect (running diskutil) goes through `CommandRunning`, so tests
// inject a fake and never erase anything.

// MARK: - Ready to format

/// Whether every file on a card has a verified copy that still exists at the destination.
struct FormatReadiness: Equatable, Sendable {
    /// Files on the card (junk excluded, all types — the include toggles don't matter here).
    var fileCount = 0
    var totalBytes: Int64 = 0
    /// Files the ledger has no verified copy of.
    var notOffloaded = 0
    /// Files that were offloaded, but whose copy is gone or has a different size now.
    var missingCopies = 0
    /// The folder that holds all the verified copies (their deepest common folder).
    var copiesFolder: String?

    /// Nothing pending, and there's something on the card.
    var isReady: Bool { fileCount > 0 && pending == 0 }
    var isEmpty: Bool { fileCount == 0 }
    var pending: Int { notOffloaded + missingCopies }

    /// "3 files not yet offloaded" / "1 copy missing at the destination"; `nil` when ready or empty.
    var pendingText: String? {
        guard !isReady, !isEmpty else { return nil }
        if notOffloaded > 0 {
            return notOffloaded == 1 ? "1 file not yet offloaded" : "\(notOffloaded) files not yet offloaded"
        }
        return missingCopies == 1 ? "1 copy missing at the destination" : "\(missingCopies) copies missing at the destination"
    }

    /// Checks `files` against the ledger. `fileSize` returns the size of a regular file at a
    /// path, or `nil` if there is none (cheap: no checksums are recomputed).
    static func compute(files: [Clip], volumeIdentity: String, entries: [String: LedgerEntry],
                        fileSize: (String) -> Int64?) -> FormatReadiness {
        FormatReadiness(inventory: CardInventory.classify(files: files, volumeIdentity: volumeIdentity,
                                                          entries: entries, fileSize: fileSize))
    }

    init(fileCount: Int = 0, totalBytes: Int64 = 0, notOffloaded: Int = 0, missingCopies: Int = 0,
         copiesFolder: String? = nil) {
        self.fileCount = fileCount
        self.totalBytes = totalBytes
        self.notOffloaded = notOffloaded
        self.missingCopies = missingCopies
        self.copiesFolder = copiesFolder
    }

    init(inventory: CardInventory) {
        self.init(fileCount: inventory.fileCount,
                  totalBytes: inventory.all.reduce(0) { $0 + $1.size },
                  notOffloaded: inventory.new.count,
                  missingCopies: inventory.missing.count,
                  copiesFolder: inventory.copiesFolder)
    }

    /// The real file system: size of a regular file, `nil` if it's missing or a folder.
    static func diskFileSize(_ path: String) -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber else { return nil }
        return size.int64Value
    }

    /// "/a/b/c" + "/a/b/d" -> "/a/b"
    static func commonFolder(_ folders: [String]) -> String? {
        guard var common = folders.first.map({ ($0 as NSString).pathComponents }) else { return nil }
        for folder in folders.dropFirst() {
            let parts = (folder as NSString).pathComponents
            common = Array(zip(common, parts).prefix { $0 == $1 }.map(\.0))
        }
        return common.isEmpty ? nil : NSString.path(withComponents: common)
    }
}

// MARK: - Running commands

struct CommandResult: Sendable, Equatable {
    var status: Int32
    var output: Data
    var errorOutput: String
}

/// Runs a command line tool. The real one uses `Process`; tests use a fake.
protocol CommandRunning: Sendable {
    func run(_ executable: String, _ arguments: [String]) async throws -> CommandResult
}

struct ProcessRunner: CommandRunning {
    func run(_ executable: String, _ arguments: [String]) async throws -> CommandResult {
        // `waitUntilExit` blocks, so run it on a background thread.
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let out = Pipe()
            let err = Pipe()
            process.standardOutput = out
            process.standardError = err
            try process.run()
            // Read before waiting so a full pipe can't stall the tool.
            let output = out.fileHandleForReading.readDataToEndOfFile()
            let errors = err.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return CommandResult(status: process.terminationStatus, output: output,
                                 errorOutput: String(decoding: errors, as: UTF8.self))
        }.value
    }
}

// MARK: - Disk facts and safety rules

/// What `diskutil info -plist` says about a volume (only the fields we use).
struct DiskFacts: Equatable, Sendable {
    var deviceIdentifier: String      // "disk4s1"
    var parentWholeDisk: String?      // "disk4"
    var mountPoint: String?           // "/Volumes/SD Card"
    var volumeName: String?
    var filesystemType: String?       // "exfat", "msdos", "apfs"…
    var filesystemName: String?       // "ExFAT", "MS-DOS FAT32"…
    var isInternal = false
    var isOSInternal = false
    var isRemovable = false
    var isEjectable = false
    var isRemovableOrExternal = false

    init(deviceIdentifier: String, parentWholeDisk: String? = nil, mountPoint: String? = nil,
         volumeName: String? = nil, filesystemType: String? = nil, filesystemName: String? = nil,
         isInternal: Bool = false, isOSInternal: Bool = false, isRemovable: Bool = false,
         isEjectable: Bool = false, isRemovableOrExternal: Bool = false) {
        self.deviceIdentifier = deviceIdentifier
        self.parentWholeDisk = parentWholeDisk
        self.mountPoint = mountPoint
        self.volumeName = volumeName
        self.filesystemType = filesystemType
        self.filesystemName = filesystemName
        self.isInternal = isInternal
        self.isOSInternal = isOSInternal
        self.isRemovable = isRemovable
        self.isEjectable = isEjectable
        self.isRemovableOrExternal = isRemovableOrExternal
    }

    /// Parses the property list printed by `diskutil info -plist <volume>`.
    init?(plist data: Data) {
        guard let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let info = object as? [String: Any],
              let device = info["DeviceIdentifier"] as? String, !device.isEmpty else { return nil }
        func flag(_ key: String) -> Bool { info[key] as? Bool ?? false }
        self.init(
            deviceIdentifier: device,
            parentWholeDisk: info["ParentWholeDisk"] as? String,
            mountPoint: info["MountPoint"] as? String,
            volumeName: info["VolumeName"] as? String,
            filesystemType: info["FilesystemType"] as? String,
            filesystemName: (info["FilesystemName"] as? String) ?? (info["FilesystemPersonality"] as? String),
            isInternal: flag("Internal"),
            isOSInternal: flag("OSInternalMedia"),
            isRemovable: flag("Removable") || flag("RemovableMedia"),
            isEjectable: flag("Ejectable"),
            isRemovableOrExternal: flag("RemovableMediaOrExternalDevice"))
    }
}

/// The file systems SnapDrop can re-create, and diskutil's names for them.
enum CardFileSystem: Equatable, Sendable {
    case exFAT, fat32, fat16

    /// The format argument for `diskutil eraseVolume`.
    var diskutilName: String {
        switch self {
        case .exFAT: return "ExFAT"
        case .fat32: return "MS-DOS FAT32"
        case .fat16: return "MS-DOS FAT16"
        }
    }

    var displayName: String {
        switch self {
        case .exFAT: return "exFAT"
        case .fat32: return "FAT32"
        case .fat16: return "FAT16"
        }
    }

    /// Keeps the card's current file system. `nil` for anything else (APFS, HFS+, NTFS…).
    static func detect(type: String?, name: String?) -> CardFileSystem? {
        let type = (type ?? "").lowercased()
        let name = (name ?? "").lowercased()
        if type == "exfat" || name == "exfat" { return .exFAT }
        if type == "msdos" || name.hasPrefix("ms-dos") || name.contains("fat32") || name.contains("fat16") {
            if name.contains("fat16") { return .fat16 }
            if name.contains("fat12") { return nil }
            return .fat32
        }
        return nil
    }

    /// The volume name to give the erased card: the same name, made legal for the file system.
    func volumeName(from original: String) -> String {
        switch self {
        case .exFAT: return CardFileSystem.exFATName(original)
        case .fat32, .fat16: return CardFileSystem.fatName(original)
        }
    }

    /// FAT labels: upper case, at most 11 characters, no punctuation FAT forbids.
    static func fatName(_ raw: String) -> String {
        let forbidden = Set("\"*+,./:;<=>?[\\]|")
        var result = ""
        for character in raw.uppercased() {
            guard character.isASCII, !forbidden.contains(character),
                  character.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { continue }
            result.append(character)
        }
        result = String(result.trimmingCharacters(in: .whitespaces).prefix(11)).trimmingCharacters(in: .whitespaces)
        return result.isEmpty ? "UNTITLED" : result
    }

    /// exFAT labels: at most 15 characters, without the characters exFAT forbids.
    static func exFATName(_ raw: String) -> String {
        let forbidden = Set("\"*/:<>?\\|")
        let cleaned = String(raw.filter { character in
            !forbidden.contains(character)
                && character.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
        })
        let result = String(cleaned.trimmingCharacters(in: .whitespaces).prefix(15)).trimmingCharacters(in: .whitespaces)
        return result.isEmpty ? "Untitled" : result
    }

    /// `diskutil eraseVolume ExFAT "SD Card" disk4s1`
    static func eraseArguments(fileSystem: CardFileSystem, name: String, device: String) -> [String] {
        ["eraseVolume", fileSystem.diskutilName, name, device]
    }
}

/// The checks that keep Format away from anything that isn't a memory card.
enum FormatGuard {
    /// Returns why `card` must not be erased, or `nil` if it's safe.
    /// - `expectedMountPoint`: where SnapDrop sees the card (must match what diskutil reports).
    /// - `boot` / `destination`: diskutil facts for "/" and for the destination's volume.
    static func refusal(card: DiskFacts, expectedMountPoint: String, boot: DiskFacts?, destination: DiskFacts?,
                        destinationPath: String?) -> String? {
        let mount = card.mountPoint ?? ""
        // 1. It's the card we think it is, mounted under /Volumes, and not the startup disk.
        guard !mount.isEmpty, standardized(mount) == standardized(expectedMountPoint) else {
            return "The card’s location changed. Reinsert it and try again."
        }
        guard mount != "/", mount.hasPrefix("/Volumes/") else { return "SnapDrop only formats memory cards." }
        guard isPartition(card.deviceIdentifier) else { return "SnapDrop only formats memory cards." }
        if let boot {
            if boot.deviceIdentifier == card.deviceIdentifier { return "That’s your startup disk." }
            if let bootDisk = boot.parentWholeDisk, bootDisk == card.parentWholeDisk { return "That’s your startup disk." }
        }
        // 2. Removable media: an SD card in the built-in reader or a USB card reader.
        //    (The built-in SD slot reports "Internal", so that flag alone isn't enough.)
        guard !card.isOSInternal else { return "This drive is part of your Mac, so SnapDrop won’t format it." }
        guard card.isRemovable || card.isEjectable || card.isRemovableOrExternal else {
            return "SnapDrop only formats removable cards."
        }
        if card.isInternal && !card.isRemovable { return "This drive is part of your Mac, so SnapDrop won’t format it." }
        // 3. Never the drive SnapDrop copies to.
        if let destinationPath {
            let volume = standardized(mount) + "/"
            if (standardized(destinationPath) + "/").hasPrefix(volume) {
                return "Your destination folder is on this card."
            }
        }
        if let destination {
            if destination.deviceIdentifier == card.deviceIdentifier { return "Your destination folder is on this card." }
            if let disk = destination.parentWholeDisk, disk == card.parentWholeDisk {
                return "Your destination folder is on the same drive as this card."
            }
        }
        return nil
    }

    /// "disk4s1" (a volume on a disk), not "disk4" (the whole disk).
    static func isPartition(_ identifier: String) -> Bool {
        identifier.range(of: #"^disk[0-9]+s[0-9]+$"#, options: .regularExpression) != nil
    }

    private static func standardized(_ path: String) -> String {
        var result = (path as NSString).standardizingPath
        while result.count > 1 && result.hasSuffix("/") { result.removeLast() }
        return result
    }
}

// MARK: - Formatting

enum FormatOutcome: Equatable, Sendable {
    /// Erased. `mountPoint` is where the empty card is mounted now (if diskutil says).
    case formatted(name: String, mountPoint: String?)
    /// Not erased, with a friendly reason.
    case refused(String)
    /// diskutil ran and failed.
    case failed(String)
}

/// Formats a card with `diskutil eraseVolume`, keeping its file system and name.
struct CardFormatter: Sendable {
    static let diskutil = "/usr/sbin/diskutil"
    let runner: CommandRunning

    init(runner: CommandRunning = ProcessRunner()) {
        self.runner = runner
    }

    /// Looks up a volume (mount point or device). `nil` if diskutil doesn't know it.
    func facts(for volume: String) async -> DiskFacts? {
        guard let result = try? await runner.run(Self.diskutil, ["info", "-plist", volume]), result.status == 0 else {
            return nil
        }
        return DiskFacts(plist: result.output)
    }

    /// Runs every check, re-checks the card is still ready, then erases it.
    /// - `destinationVolume`: mount point of the volume the destination folder is on.
    /// - `stillReady`: re-scans the card and checks the ledger right before erasing.
    func format(card: CardVolume, destinationPath: String?, destinationVolume: String?,
                stillReady: @Sendable () async -> Bool) async -> FormatOutcome {
        guard let facts = await facts(for: card.url.path) else {
            return .refused("SnapDrop couldn’t read information about \(card.name).")
        }
        let boot = await self.facts(for: "/")
        guard boot != nil else { return .refused("SnapDrop couldn’t check your startup disk, so it won’t format anything.") }
        var destination: DiskFacts?
        if let destinationVolume { destination = await self.facts(for: destinationVolume) }
        if let refusal = FormatGuard.refusal(card: facts, expectedMountPoint: card.url.path, boot: boot,
                                             destination: destination, destinationPath: destinationPath) {
            return .refused(refusal)
        }
        guard let fileSystem = CardFileSystem.detect(type: facts.filesystemType, name: facts.filesystemName) else {
            let current = facts.filesystemName ?? facts.filesystemType ?? "this format"
            return .refused("\(card.name) uses \(current). SnapDrop formats exFAT and FAT32 cards only — format it in your camera instead.")
        }
        guard await stillReady() else {
            return .refused("Something on \(card.name) changed and isn’t offloaded yet, so it wasn’t formatted.")
        }
        let name = fileSystem.volumeName(from: facts.volumeName ?? card.name)
        let arguments = CardFileSystem.eraseArguments(fileSystem: fileSystem, name: name, device: facts.deviceIdentifier)
        do {
            let result = try await runner.run(Self.diskutil, arguments)
            guard result.status == 0 else {
                let message = result.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                return .failed(message.isEmpty ? "diskutil couldn’t format \(card.name)." : message)
            }
        } catch {
            return .failed("Couldn’t run diskutil: \(error.localizedDescription)")
        }
        let after = await self.facts(for: facts.deviceIdentifier)
        return .formatted(name: name, mountPoint: after?.mountPoint)
    }
}
