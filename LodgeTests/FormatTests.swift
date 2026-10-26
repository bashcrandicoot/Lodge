import XCTest
@testable import Lodge

/// "Ready to format" and the safety checks around Format Card…. No test ever erases anything:
/// diskutil is replaced by `FakeRunner`, which only records what it was asked to run.
final class FormatTests: XCTestCase {
    private let identity = "CARD-UUID"

    private func clip(_ path: String, size: Int64) -> Clip {
        Clip(url: URL(fileURLWithPath: "/Volumes/SD Card/" + path), relativePath: path, size: size,
             creationDate: nil, modificationDate: nil)
    }

    private func entry(for clip: Clip, at destination: String, size: Int64? = nil) -> LedgerEntry {
        LedgerEntry(sourceKey: clip.ledgerKey(volumeIdentity: identity), cardName: "SD Card",
                    sourceRelativePath: clip.relativePath, destinationPath: destination,
                    size: size ?? clip.size, sha256: "x", offloadedAt: Date())
    }

    private func entries(_ list: [LedgerEntry]) -> [String: LedgerEntry] {
        Dictionary(list.map { ($0.sourceKey, $0) }, uniquingKeysWith: { $1 })
    }

    // MARK: Readiness

    func testReadyWhenEveryFileHasAVerifiedCopy() {
        let a = clip("DCIM/C0001.MP4", size: 100)
        let b = clip("DCIM/C0001M01.XML", size: 5)
        let index = entries([entry(for: a, at: "/Footage/Coastline/C0001.MP4"),
                             entry(for: b, at: "/Footage/Coastline/C0001M01.XML")])
        let sizes = ["/Footage/Coastline/C0001.MP4": Int64(100), "/Footage/Coastline/C0001M01.XML": 5]
        let readiness = FormatReadiness.compute(files: [a, b], volumeIdentity: identity, entries: index,
                                                fileSize: { sizes[$0] })
        XCTAssertTrue(readiness.isReady)
        XCTAssertEqual(readiness.fileCount, 2)
        XCTAssertEqual(readiness.totalBytes, 105)
        XCTAssertEqual(readiness.copiesFolder, "/Footage/Coastline")
        XCTAssertNil(readiness.pendingText)
    }

    func testNotReadyWhenACopyIsMissing() {
        let a = clip("DCIM/C0001.MP4", size: 100)
        let index = entries([entry(for: a, at: "/Footage/C0001.MP4")])
        let readiness = FormatReadiness.compute(files: [a], volumeIdentity: identity, entries: index,
                                                fileSize: { _ in nil })
        XCTAssertFalse(readiness.isReady)
        XCTAssertEqual(readiness.missingCopies, 1)
        XCTAssertEqual(readiness.pendingText, "1 copy missing at the destination")
    }

    func testNotReadyWhenTheCopyHasADifferentSize() {
        let a = clip("DCIM/C0001.MP4", size: 100)
        let index = entries([entry(for: a, at: "/Footage/C0001.MP4")])
        let readiness = FormatReadiness.compute(files: [a], volumeIdentity: identity, entries: index,
                                                fileSize: { _ in 99 })
        XCTAssertFalse(readiness.isReady)
        XCTAssertEqual(readiness.missingCopies, 1)
    }

    func testNotReadyWhenATurnedOffTypeWasNeverOffloaded() {
        // Audio was switched off in Settings, so the WAV was skipped — it's still only on the card.
        let video = clip("DCIM/C0001.MP4", size: 100)
        let audio = clip("ZOOM/ZOOM0001.WAV", size: 50)
        let index = entries([entry(for: video, at: "/Footage/C0001.MP4")])
        let readiness = FormatReadiness.compute(files: [video, audio], volumeIdentity: identity, entries: index,
                                                fileSize: { _ in 100 })
        XCTAssertFalse(readiness.isReady)
        XCTAssertEqual(readiness.notOffloaded, 1)
        XCTAssertEqual(readiness.pendingText, "1 file not yet offloaded")
    }

    func testEmptyCardIsNeitherReadyNorPending() {
        let readiness = FormatReadiness.compute(files: [], volumeIdentity: identity, entries: [:], fileSize: { _ in nil })
        XCTAssertTrue(readiness.isEmpty)
        XCTAssertFalse(readiness.isReady)
        XCTAssertNil(readiness.pendingText)
    }

    func testDiskFileSizeReadsRealFilesOnly() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lodge-format-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("a.bin")
        try Data(count: 42).write(to: file)
        XCTAssertEqual(FormatReadiness.diskFileSize(file.path), 42)
        XCTAssertNil(FormatReadiness.diskFileSize(folder.path))
        XCTAssertNil(FormatReadiness.diskFileSize(folder.appendingPathComponent("missing").path))
    }

    @MainActor
    func testLedgerIndexKeepsTheNewestEntry() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lodge-ledger-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let a = clip("DCIM/C0001.MP4", size: 100)
        let ledger = Ledger(fileURL: url)
        ledger.add(entry(for: a, at: "/old/C0001.MP4"))
        ledger.add(entry(for: a, at: "/new/C0001.MP4"))
        XCTAssertEqual(ledger.entriesByKey()[a.ledgerKey(volumeIdentity: identity)]?.destinationPath, "/new/C0001.MP4")
    }

    // MARK: File systems and names

    func testFileSystemMapping() {
        XCTAssertEqual(CardFileSystem.detect(type: "exfat", name: "ExFAT"), .exFAT)
        XCTAssertEqual(CardFileSystem.detect(type: "msdos", name: "MS-DOS FAT32"), .fat32)
        XCTAssertEqual(CardFileSystem.detect(type: "msdos", name: "MS-DOS"), .fat32)
        XCTAssertEqual(CardFileSystem.detect(type: "msdos", name: "MS-DOS FAT16"), .fat16)
        XCTAssertNil(CardFileSystem.detect(type: "msdos", name: "MS-DOS FAT12"))
        XCTAssertNil(CardFileSystem.detect(type: "apfs", name: "APFS"))
        XCTAssertNil(CardFileSystem.detect(type: "hfs", name: "Mac OS Extended (Journaled)"))
        XCTAssertNil(CardFileSystem.detect(type: nil, name: nil))

        XCTAssertEqual(CardFileSystem.eraseArguments(fileSystem: .exFAT, name: "SD Card", device: "disk4s1"),
                       ["eraseVolume", "ExFAT", "SD Card", "disk4s1"])
        XCTAssertEqual(CardFileSystem.eraseArguments(fileSystem: .fat32, name: "UNTITLED", device: "disk5s1"),
                       ["eraseVolume", "MS-DOS FAT32", "UNTITLED", "disk5s1"])
    }

    func testFATNamesAreUppercaseShortAndLegal() {
        XCTAssertEqual(CardFileSystem.fatName("SD Card"), "SD CARD")
        XCTAssertEqual(CardFileSystem.fatName("Untitled"), "UNTITLED")
        XCTAssertEqual(CardFileSystem.fatName("A7S III Card B"), "A7S III CAR")
        XCTAssertEqual(CardFileSystem.fatName("cam/a:b*c?"), "CAMABC")
        XCTAssertEqual(CardFileSystem.fatName("Café"), "CAF")
        XCTAssertEqual(CardFileSystem.fatName("???"), "UNTITLED")
        XCTAssertEqual(CardFileSystem.fatName("  "), "UNTITLED")
        XCTAssertLessThanOrEqual(CardFileSystem.fatName(String(repeating: "X", count: 40)).count, 11)
    }

    func testExFATNamesKeepCaseButStayLegal() {
        XCTAssertEqual(CardFileSystem.exFATName("SD Card"), "SD Card")
        XCTAssertEqual(CardFileSystem.exFATName("Card: A/B"), "Card AB")
        XCTAssertEqual(CardFileSystem.exFATName("A Very Long Card Name"), "A Very Long Car")
        XCTAssertEqual(CardFileSystem.exFATName("\"*\""), "Untitled")
    }

    // MARK: Volume guard

    /// Modeled on a real SD card in a Mac's built-in reader (which reports "Internal").
    private let card = DiskFacts(deviceIdentifier: "disk4s1", parentWholeDisk: "disk4", mountPoint: "/Volumes/SD Card",
                                 volumeName: "SD Card", filesystemType: "exfat", filesystemName: "ExFAT",
                                 isInternal: true, isOSInternal: false, isRemovable: true, isEjectable: true,
                                 isRemovableOrExternal: true)
    private let boot = DiskFacts(deviceIdentifier: "disk3s3s1", parentWholeDisk: "disk3", mountPoint: "/",
                                 volumeName: "Macintosh HD", filesystemType: "apfs", isInternal: true, isOSInternal: true)
    private let externalSSD = DiskFacts(deviceIdentifier: "disk6s2", parentWholeDisk: "disk6", mountPoint: "/Volumes/Footage",
                                        filesystemType: "apfs", isEjectable: true, isRemovableOrExternal: true)

    private func refusal(_ card: DiskFacts, mount: String = "/Volumes/SD Card", destination: DiskFacts? = nil,
                         destinationPath: String? = "/Users/me/Movies") -> String? {
        FormatGuard.refusal(card: card, expectedMountPoint: mount, boot: boot, destination: destination ?? boot,
                            destinationPath: destinationPath)
    }

    func testGuardAllowsARemovableCard() {
        XCTAssertNil(refusal(card))
        XCTAssertNil(refusal(card, mount: "/Volumes/SD Card/", destination: externalSSD, destinationPath: "/Volumes/Footage/Jobs"))
    }

    func testGuardRefusesTheStartupDisk() {
        var startup = boot
        startup.isOSInternal = false
        startup.isRemovable = true
        XCTAssertNotNil(FormatGuard.refusal(card: startup, expectedMountPoint: "/", boot: boot, destination: nil,
                                            destinationPath: nil))
        var sameDisk = card
        sameDisk.parentWholeDisk = "disk3"
        XCTAssertNotNil(refusal(sameDisk))
    }

    func testGuardRefusesInternalAndFixedDrives() {
        var onBoard = card
        onBoard.isOSInternal = true
        XCTAssertNotNil(refusal(onBoard))
        var fixed = card
        fixed.isRemovable = false
        fixed.isEjectable = false
        fixed.isRemovableOrExternal = false
        XCTAssertNotNil(refusal(fixed))
        var internalNotRemovable = card
        internalNotRemovable.isRemovable = false
        XCTAssertNotNil(refusal(internalNotRemovable))
    }

    func testGuardRefusesTheDestinationDrive() {
        XCTAssertNotNil(refusal(card, destinationPath: "/Volumes/SD Card/Backup"))
        var destinationOnCard = externalSSD
        destinationOnCard.parentWholeDisk = "disk4"
        XCTAssertNotNil(refusal(card, destination: destinationOnCard, destinationPath: "/Volumes/Other"))
        var sameVolume = externalSSD
        sameVolume.deviceIdentifier = "disk4s1"
        XCTAssertNotNil(refusal(card, destination: sameVolume, destinationPath: "/Volumes/Other"))
    }

    func testGuardRefusesWholeDisksAndUnexpectedMounts() {
        var whole = card
        whole.deviceIdentifier = "disk4"
        XCTAssertNotNil(refusal(whole))
        XCTAssertNotNil(refusal(card, mount: "/Volumes/Other Card"))
        var unmounted = card
        unmounted.mountPoint = nil
        XCTAssertNotNil(refusal(unmounted))
        var outside = card
        outside.mountPoint = "/private/var/card"
        XCTAssertNotNil(refusal(outside, mount: "/private/var/card"))
        XCTAssertTrue(FormatGuard.isPartition("disk12s3"))
        XCTAssertFalse(FormatGuard.isPartition("disk3s3s1x"))
        XCTAssertFalse(FormatGuard.isPartition("/dev/disk4s1"))
    }

    func testDiskFactsParsesDiskutilPlist() throws {
        let data = try plist(card: true)
        let facts = try XCTUnwrap(DiskFacts(plist: data))
        XCTAssertEqual(facts, card)
        XCTAssertNil(DiskFacts(plist: Data("nope".utf8)))
    }

    // MARK: Formatter (fake diskutil)

    private func plist(card isCard: Bool, filesystem: String = "exfat", name: String = "ExFAT") throws -> Data {
        let info: [String: Any] = isCard ? [
            "DeviceIdentifier": "disk4s1", "ParentWholeDisk": "disk4", "MountPoint": "/Volumes/SD Card",
            "VolumeName": "SD Card", "FilesystemType": filesystem, "FilesystemName": name,
            "Internal": true, "OSInternalMedia": false, "RemovableMedia": true, "Removable": true,
            "Ejectable": true, "RemovableMediaOrExternalDevice": true, "WholeDisk": false,
        ] : [
            "DeviceIdentifier": "disk3s3s1", "ParentWholeDisk": "disk3", "MountPoint": "/",
            "VolumeName": "Macintosh HD", "FilesystemType": "apfs", "Internal": true, "OSInternalMedia": true,
            "RemovableMedia": false, "Ejectable": false,
        ]
        return try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    }

    private func runner(filesystem: String = "exfat", name: String = "ExFAT") throws -> FakeRunner {
        FakeRunner(cardInfo: try plist(card: true, filesystem: filesystem, name: name), bootInfo: try plist(card: false))
    }

    private let sdCard = CardVolume(url: URL(fileURLWithPath: "/Volumes/SD Card", isDirectory: true), name: "SD Card", uuid: "U")

    func testFormatterErasesWithTheSameFileSystemAndName() async throws {
        let fake = try runner()
        let outcome = await CardFormatter(runner: fake).format(
            card: sdCard, destinationPath: "/Users/me/Movies", destinationVolume: "/", stillReady: { true })
        XCTAssertEqual(outcome, .formatted(name: "SD Card", mountPoint: "/Volumes/SD Card"))
        XCTAssertEqual(fake.erases, [["eraseVolume", "ExFAT", "SD Card", "disk4s1"]])
    }

    func testFormatterKeepsFAT32AndUppercasesTheName() async throws {
        let fake = try runner(filesystem: "msdos", name: "MS-DOS FAT32")
        _ = await CardFormatter(runner: fake).format(
            card: sdCard, destinationPath: nil, destinationVolume: nil, stillReady: { true })
        XCTAssertEqual(fake.erases, [["eraseVolume", "MS-DOS FAT32", "SD CARD", "disk4s1"]])
    }

    func testFormatterRefusesUnsupportedFileSystems() async throws {
        let fake = try runner(filesystem: "apfs", name: "APFS")
        let outcome = await CardFormatter(runner: fake).format(
            card: sdCard, destinationPath: nil, destinationVolume: nil, stillReady: { true })
        guard case .refused = outcome else { return XCTFail("expected a refusal, got \(outcome)") }
        XCTAssertTrue(fake.erases.isEmpty)
    }

    func testFormatterRechecksReadinessBeforeErasing() async throws {
        let fake = try runner()
        let outcome = await CardFormatter(runner: fake).format(
            card: sdCard, destinationPath: nil, destinationVolume: nil, stillReady: { false })
        guard case .refused = outcome else { return XCTFail("expected a refusal, got \(outcome)") }
        XCTAssertTrue(fake.erases.isEmpty)
    }

    func testFormatterRefusesWhenTheDestinationIsOnTheCard() async throws {
        let fake = try runner()
        let outcome = await CardFormatter(runner: fake).format(
            card: sdCard, destinationPath: "/Volumes/SD Card/Copies", destinationVolume: "/Volumes/SD Card",
            stillReady: { true })
        guard case .refused = outcome else { return XCTFail("expected a refusal, got \(outcome)") }
        XCTAssertTrue(fake.erases.isEmpty)
    }

    func testFormatterRefusesWhenDiskutilCantDescribeTheCard() async {
        let fake = FakeRunner(cardInfo: nil, bootInfo: nil)
        let outcome = await CardFormatter(runner: fake).format(
            card: sdCard, destinationPath: nil, destinationVolume: nil, stillReady: { true })
        guard case .refused = outcome else { return XCTFail("expected a refusal, got \(outcome)") }
        XCTAssertTrue(fake.erases.isEmpty)
    }

    func testFormatterReportsDiskutilFailure() async throws {
        let fake = try runner()
        fake.eraseStatus = 1
        let outcome = await CardFormatter(runner: fake).format(
            card: sdCard, destinationPath: nil, destinationVolume: nil, stillReady: { true })
        XCTAssertEqual(outcome, .failed("Resource busy"))
    }

    // MARK: Confirmation text

    func testAlertNamesTheCardAndWhereTheCopiesAre() {
        let readiness = FormatReadiness(fileCount: 54, totalBytes: 2_000_000_000, copiesFolder: "/Footage/Coastline")
        let (title, message) = FormatAlert.text(cardName: "A7S III", readiness: readiness)
        XCTAssertEqual(title, "Format “A7S III”?")
        XCTAssertTrue(message.contains("All 54 files"))
        XCTAssertTrue(message.contains("verified"))
        XCTAssertTrue(message.contains("/Footage/Coastline"))
        XCTAssertTrue(message.contains("erases everything"))
        XCTAssertTrue(message.contains("camera"))
    }
}

/// Pretends to be diskutil. `info` answers from fixtures; `eraseVolume` is only recorded.
private final class FakeRunner: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private let cardInfo: Data?
    private let bootInfo: Data?
    private var _erases: [[String]] = []
    private var _eraseStatus: Int32 = 0

    init(cardInfo: Data?, bootInfo: Data?) {
        self.cardInfo = cardInfo
        self.bootInfo = bootInfo
    }

    var erases: [[String]] { lock.withLock { _erases } }
    var eraseStatus: Int32 {
        get { lock.withLock { _eraseStatus } }
        set { lock.withLock { _eraseStatus = newValue } }
    }

    func run(_ executable: String, _ arguments: [String]) async throws -> CommandResult {
        XCTAssertEqual(executable, "/usr/sbin/diskutil")
        if arguments.first == "eraseVolume" {
            let status: Int32 = lock.withLock {
                _erases.append(arguments)
                return _eraseStatus
            }
            return CommandResult(status: status, output: Data(), errorOutput: status == 0 ? "" : "Resource busy\n")
        }
        guard arguments.count == 3, arguments[0] == "info", arguments[1] == "-plist" else {
            return CommandResult(status: 1, output: Data(), errorOutput: "unexpected")
        }
        let target = arguments[2]
        let data = (target == "/") ? bootInfo : (["/Volumes/SD Card", "disk4s1"].contains(target) ? cardInfo : nil)
        guard let data else { return CommandResult(status: 1, output: Data(), errorOutput: "Could not find disk") }
        return CommandResult(status: 0, output: data, errorOutput: "")
    }
}
