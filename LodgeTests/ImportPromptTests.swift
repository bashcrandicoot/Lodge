import XCTest
@testable import Lodge

final class ImportPromptPolicyTests: XCTestCase {
    private func card(_ path: String = "/Volumes/A7SIII", removable: Bool = true, ejectable: Bool = true,
                      isInternal: Bool? = false) -> VolumeTraits {
        var traits = VolumeTraits(path: path)
        traits.isRemovable = removable
        traits.isEjectable = ejectable
        traits.isInternal = isInternal
        return traits
    }

    private func verdict(_ traits: VolumeTraits, media: Bool = true, destinations: [String] = [],
                         ignored: Set<String> = []) -> ImportPromptPolicy.Verdict {
        ImportPromptPolicy.verdict(for: traits, identity: "UUID-1", looksLikeCameraMedia: media,
                                   destinationPaths: destinations, ignored: ignored)
    }

    func testCameraCardPrompts() {
        XCTAssertEqual(verdict(card()), .prompt)
        // Thunderbolt SSDs are ejectable but not removable; USB card readers may be the reverse.
        XCTAssertEqual(verdict(card(removable: false)), .prompt)
        XCTAssertEqual(verdict(card(ejectable: false)), .prompt)
        XCTAssertEqual(verdict(card(isInternal: nil)), .prompt)
    }

    func testSystemAndInternalVolumesAreSkipped() {
        XCTAssertEqual(verdict(card("/")), .skip(.system))
        XCTAssertEqual(verdict(card("/System/Volumes/Data")), .skip(.system))
        var root = card()
        root.isRootFileSystem = true
        XCTAssertEqual(verdict(root), .skip(.system))
        XCTAssertEqual(verdict(card(removable: false, ejectable: false)), .skip(.notExternal))
    }

    // What macOS reports for each kind of drive (`diskutil info` / URL resource values).

    func testBuiltInSDCardReaderPrompts() {
        // A MacBook Pro's SD slot: Protocol Secure Digital, Device Location Internal, Removable.
        let sd = card("/Volumes/SD Card", removable: true, ejectable: true, isInternal: true)
        XCTAssertTrue(ImportPromptPolicy.isPluggableMedia(sd))
        XCTAssertEqual(verdict(sd), .prompt)
    }

    func testUSBCardReaderPrompts() {
        XCTAssertEqual(verdict(card("/Volumes/Untitled", removable: true, ejectable: true, isInternal: false)), .prompt)
    }

    func testExternalSSDWithMediaPrompts() {
        // Thunderbolt/USB SSDs: external and ejectable, not "removable media".
        let ssd = card("/Volumes/T7", removable: false, ejectable: true, isInternal: false)
        XCTAssertEqual(verdict(ssd), .prompt)
        XCTAssertEqual(verdict(ssd, media: false), .skip(.notCameraMedia))
    }

    func testFixedInternalVolumesAreSkipped() {
        // A second APFS volume or partition on the built-in SSD (e.g. /Volumes/Recovery, /Volumes/Data).
        XCTAssertEqual(verdict(card("/Volumes/Recovery", removable: false, ejectable: false, isInternal: true)),
                       .skip(.notExternal))
        // Internal but ejectable (rare, e.g. some internal bays) is still treated as fixed.
        XCTAssertEqual(verdict(card("/Volumes/Bay", removable: false, ejectable: true, isInternal: true)),
                       .skip(.notExternal))
    }

    /// Reads a real mounted volume (never writes to it). Run with
    /// `TEST_RUNNER_LODGE_REAL_VOLUME='/Volumes/SD Card' xcodebuild test …`; skipped otherwise.
    func testRealVolumeFromEnvironment() throws {
        guard let path = ProcessInfo.processInfo.environment["LODGE_REAL_VOLUME"] else {
            throw XCTSkip("set TEST_RUNNER_LODGE_REAL_VOLUME to check a real card")
        }
        try XCTSkipUnless(FileManager.default.fileExists(atPath: path), "\(path) isn't mounted")
        let traits = VolumeTraits.read(URL(fileURLWithPath: path))
        let media = CameraMedia.looksLikeCameraMedia(root: path)
        let result = ImportPromptPolicy.verdict(for: traits, identity: "real", looksLikeCameraMedia: media,
                                                destinationPaths: [], ignored: [])
        print("LODGE_REAL_VOLUME \(path): \(traits) cameraMedia=\(media) verdict=\(result)")
        XCTAssertEqual(result, .prompt)
    }

    func testNetworkDiskImagesAndBackupsAreSkipped() {
        var share = card("/Volumes/Studio")
        share.isLocal = false
        XCTAssertEqual(verdict(share), .skip(.network))
        var dmg = card("/Volumes/Lodge 1.2")
        dmg.isDiskImage = true
        XCTAssertEqual(verdict(dmg), .skip(.diskImage))
        var backup = card("/Volumes/Time Machine")
        backup.isBackup = true
        XCTAssertEqual(verdict(backup), .skip(.backup))
    }

    func testDestinationAndFavoriteDrivesAreSkipped() {
        let drive = card("/Volumes/T7")
        XCTAssertEqual(verdict(drive, destinations: ["/Volumes/T7/Footage"]), .skip(.destination))
        XCTAssertEqual(verdict(drive, destinations: ["/Volumes/T7"]), .skip(.destination))
        // A similarly named volume isn't the same drive.
        XCTAssertEqual(verdict(drive, destinations: ["/Volumes/T7 Shield/Footage"]), .prompt)
        XCTAssertEqual(verdict(drive, destinations: ["/Users/me/Movies"]), .prompt)
    }

    func testIgnoredCardsAndOrdinaryDrivesAreSkipped() {
        XCTAssertEqual(verdict(card(), ignored: ["UUID-1"]), .skip(.ignored))
        XCTAssertEqual(verdict(card(), ignored: ["UUID-2"]), .prompt)
        XCTAssertEqual(verdict(card(), media: false), .skip(.notCameraMedia))
    }

    func testDebounceHoldsBackQuickRemounts() {
        var debouncer = MountDebouncer(interval: 20)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(debouncer.shouldPrompt("A", now: start))
        XCTAssertFalse(debouncer.shouldPrompt("A", now: start.addingTimeInterval(5)))
        XCTAssertTrue(debouncer.shouldPrompt("B", now: start.addingTimeInterval(5)))
        XCTAssertTrue(debouncer.shouldPrompt("A", now: start.addingTimeInterval(21)))
    }
}

final class CameraMediaTests: XCTestCase {
    private func lister(_ tree: [String: [String]]) -> CameraMedia.Lister {
        { tree[$0] }
    }

    func testCameraFoldersCount() {
        XCTAssertTrue(CameraMedia.looksLikeCameraMedia(root: "/V", list: lister(["/V": ["DCIM", "MISC"]])))
        XCTAssertTrue(CameraMedia.looksLikeCameraMedia(root: "/V", list: lister(["/V": ["dcim"]])))
        XCTAssertTrue(CameraMedia.looksLikeCameraMedia(
            root: "/V", list: lister(["/V": ["PRIVATE"], "/V/PRIVATE": ["M4ROOT", "SONY"]])))
        XCTAssertTrue(CameraMedia.looksLikeCameraMedia(root: "/V", list: lister(["/V": ["CONTENTS", "LASTCLIP.TXT"]])))
        // PRIVATE alone (without a camera folder inside) isn't enough.
        XCTAssertFalse(CameraMedia.looksLikeCameraMedia(
            root: "/V", list: lister(["/V": ["PRIVATE"], "/V/PRIVATE": ["notes"]])))
    }

    func testClipsAtTheRootOrOneFolderDown() {
        // Blackmagic writes BRAW straight to the root; audio recorders use a folder.
        XCTAssertTrue(CameraMedia.looksLikeCameraMedia(root: "/V", list: lister(["/V": ["A001_C001.braw"]])))
        XCTAssertTrue(CameraMedia.looksLikeCameraMedia(
            root: "/V", list: lister(["/V": ["FOLDER01"], "/V/FOLDER01": ["ZOOM0001.WAV"]])))
        XCTAssertFalse(CameraMedia.looksLikeCameraMedia(
            root: "/V", list: lister(["/V": ["Projects"], "/V/Projects": ["a", "b"], "/V/Projects/a": ["x.mov"]])))
    }

    func testOrdinaryDrivesDontCount() {
        XCTAssertFalse(CameraMedia.looksLikeCameraMedia(
            root: "/V", list: lister(["/V": ["Documents", "Invoice.pdf", ".Spotlight-V100"], "/V/Documents": ["a.pages"]])))
        XCTAssertFalse(CameraMedia.looksLikeCameraMedia(root: "/V", list: lister(["/V": []])))
        XCTAssertFalse(CameraMedia.looksLikeCameraMedia(root: "/V", list: lister([:])))
        // Hidden files (like ._ resource forks) don't count.
        XCTAssertFalse(CameraMedia.looksLikeCameraMedia(root: "/V", list: lister(["/V": ["._clip.mov"]])))
    }
}

@MainActor
final class MenuBarSettingsTests: XCTestCase {
    func testDefaults() {
        let settings = AppSettings(defaults: nil)
        XCTAssertFalse(settings.keepRunningInMenuBar)
        XCTAssertTrue(settings.askToImport)
        XCTAssertTrue(settings.showMenuBarIcon)
        XCTAssertFalse(settings.menuBarIconVisible)
        XCTAssertTrue(settings.ignoredImportCards.isEmpty)
    }

    func testIconNeedsMenuBarMode() {
        let settings = AppSettings(defaults: nil)
        settings.keepRunningInMenuBar = true
        XCTAssertTrue(settings.menuBarIconVisible)
        settings.showMenuBarIcon = false
        XCTAssertFalse(settings.menuBarIconVisible)
    }

    func testSettingsAreSaved() throws {
        let suite = "lodge-menubar-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.keepRunningInMenuBar = true
        settings.askToImport = false
        settings.showMenuBarIcon = false
        let card = CardVolume(url: URL(fileURLWithPath: "/Volumes/A7SIII"), name: "A7SIII", uuid: "UUID-1")
        settings.ignoreImports(from: card)
        settings.ignoreImports(from: card)   // no duplicates

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertTrue(reloaded.keepRunningInMenuBar)
        XCTAssertFalse(reloaded.askToImport)
        XCTAssertFalse(reloaded.showMenuBarIcon)
        XCTAssertEqual(reloaded.ignoredImportCards, [IgnoredImportCard(identity: "UUID-1", name: "A7SIII")])
        reloaded.stopIgnoringImports("UUID-1")
        XCTAssertTrue(AppSettings(defaults: defaults).ignoredImportCards.isEmpty)
    }
}
