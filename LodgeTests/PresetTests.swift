import XCTest
@testable import Lodge

/// Saved setups ("Drone Day"): saving, editing, switching and applying them.
@MainActor
final class PresetTests: XCTestCase {
    private var folder: URL!
    private var fileURL: URL { folder.appendingPathComponent("presets.json") }

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("lodge-presets-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testSaveRenameDuplicateMoveDeleteAndReload() throws {
        let store = PresetStore(fileURL: fileURL)
        let drone = store.add(OffloadPreset(name: "Drone Day", folderTemplate: "{date}/{camera}", quickDump: true))
        let sony = store.add(OffloadPreset(name: "Sony", shortClipSeconds: 3))
        let again = store.add(OffloadPreset(name: "drone day"))
        XCTAssertEqual(again.name, "drone day 2", "Names stay unique")
        store.rename(again.id, to: "B-Roll")
        store.duplicate(sony.id)
        XCTAssertEqual(store.presets.map(\.name), ["Drone Day", "Sony", "B-Roll", "Sony Copy"])
        store.move(fromOffsets: [3], toOffset: 0)
        XCTAssertEqual(store.presets.map(\.name), ["Sony Copy", "Drone Day", "Sony", "B-Roll"])
        store.markActive(drone.id)
        var edited = try XCTUnwrap(store.preset(id: sony.id))
        edited.fileRules.ignorePatterns.append("*.tmp")
        edited.destinationPath = "/Volumes/SSD"
        store.update(edited)

        let reloaded = PresetStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.presets, store.presets)
        XCTAssertEqual(reloaded.activePreset?.name, "Drone Day")
        XCTAssertEqual(reloaded.preset(id: sony.id)?.fileRules.ignorePatterns.last, "*.tmp")
        XCTAssertEqual(reloaded.preset(id: sony.id)?.destinationPath, "/Volumes/SSD")
        XCTAssertTrue(reloaded.preset(id: drone.id)?.quickDump == true)

        reloaded.delete([drone.id])
        XCTAssertNil(reloaded.activeID, "Deleting the active preset leaves none active")
        XCTAssertEqual(PresetStore(fileURL: fileURL).presets.count, 3)
        reloaded.markActive(UUID())
        XCTAssertNil(reloaded.activeID, "Unknown ids aren't remembered")
    }

    func testAnUnreadableFileIsReportedNotOverwritten() throws {
        try Data("nope".utf8).write(to: fileURL)
        let store = PresetStore(fileURL: fileURL)
        XCTAssertTrue(store.presets.isEmpty)
        XCTAssertNotNil(store.lastError)
    }

    func testSummaryAndDescriptions() {
        XCTAssertEqual(OffloadPreset(name: "A").summary, "Date / Project · Skips < 5 s")
        XCTAssertEqual(OffloadPreset(name: "B", quickDump: true).summary, "Date · Quick dump · Skips < 5 s")
        XCTAssertEqual(OffloadPreset(name: "C", folderTemplate: "", skipShortClips: false).summary, "No folders · Keeps short clips")
        XCTAssertEqual(TemplateDescription.levels("{year}/{date}_{camera}/Clients"), "Year / Date_Camera / Clients")
        XCTAssertEqual(OffloadPreset(name: "  ").displayName, "Untitled Preset")
        let a = OffloadPreset(name: "A"), b = OffloadPreset(name: "B")
        XCTAssertTrue(a.sameSettings(as: b))
        XCTAssertFalse(a.sameSettings(as: OffloadPreset(name: "A", shortClipSeconds: 6)))
    }

    private func makeModel(settings: AppSettings, destinations: DestinationStore, cameras: CameraStore? = nil,
                           presets: PresetStore) -> AppModel {
        let cameras = cameras ?? CameraStore(fileURL: nil)
        return AppModel(settings: settings, ledger: Ledger(fileURL: folder.appendingPathComponent("ledger.json")),
                 cameras: cameras, destinations: destinations, presets: presets, startWatching: false)
    }

    func testSavingAndApplyingAPresetTakesEffectImmediately() throws {
        let movies = folder.appendingPathComponent("Movies", isDirectory: true)
        let drone = folder.appendingPathComponent("Drone", isDirectory: true)
        try FileManager.default.createDirectory(at: movies, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: drone, withIntermediateDirectories: true)
        let settings = AppSettings(defaults: nil)
        let destinations = DestinationStore(fileURL: nil)
        let moviesFavorite = destinations.add(path: movies.path)
        let droneFavorite = destinations.add(path: drone.path)
        let cameras = CameraStore(fileURL: nil)
        let mavic = cameras.add(name: "Mavic 3", code: "M3")
        let presets = PresetStore(fileURL: nil)
        let model = makeModel(settings: settings, destinations: destinations, cameras: cameras, presets: presets)
        XCTAssertEqual(settings.destinationPath, movies.path)

        // Save the current setup.
        let standard = model.saveCurrentSetupAsPreset(named: "  Everyday ")
        XCTAssertEqual(standard.name, "Everyday")
        XCTAssertEqual(standard.destinationPath, movies.path)
        XCTAssertEqual(presets.activeID, standard.id)
        XCTAssertFalse(model.activePresetIsEdited)

        // A drone preset: different folder, names, camera, threshold, quick dump and rules.
        var rules = FileRules.standard
        rules.sidecarExtensions.append("json")
        let dronePreset = presets.add(OffloadPreset(
            name: "Drone Day", destinationPath: drone.path, folderTemplate: "{date}/{camera}",
            fileTemplate: "{date}_{camera}_{seq}", cameraID: mavic.id, skipShortClips: true, shortClipSeconds: 2,
            quickDump: true, fileRules: rules))

        let card = CardVolume(url: URL(fileURLWithPath: "/Volumes/DJI"), name: "DJI", uuid: "D")
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let clip = Clip(url: URL(fileURLWithPath: "/Volumes/DJI/DCIM/DJI_0001.MP4"), relativePath: "DCIM/DJI_0001.MP4",
                        size: 1, creationDate: date, modificationDate: date)
        model.installDemo(card: card, session: OffloadSession(card: card, clips: [clip], knownKeys: []))
        let session = try XCTUnwrap(model.session)

        model.applyPreset(dronePreset)
        XCTAssertEqual(settings.destinationPath, drone.path)
        XCTAssertEqual(destinations.lastUsedID, droneFavorite.id)
        XCTAssertEqual(settings.folderTemplate, "{date}/{camera}")
        XCTAssertEqual(settings.fileTemplate, "{date}_{camera}_{seq}")
        XCTAssertEqual(settings.shortClipSeconds, 2)
        XCTAssertTrue(settings.quickDump)
        XCTAssertEqual(settings.fileRules, rules)
        XCTAssertEqual(session.cameraID, mavic.id)
        XCTAssertEqual(session.shortRule, ShortClipRule(isEnabled: true, threshold: 2), "The open card updates at once")
        XCTAssertEqual(session.fileRules, rules)
        XCTAssertEqual(presets.activeID, dronePreset.id)
        XCTAssertFalse(model.activePresetIsEdited)
        let planned = model.previewPlan(for: session).first?.relativePath ?? "no plan"
        XCTAssertTrue(planned.contains("/M3/") && planned.hasSuffix("_M3_0001.mp4"), planned)

        // Changing a setting marks it edited; "Update" saves it into the preset.
        settings.shortClipSliderSeconds = 8
        XCTAssertTrue(model.activePresetIsEdited)
        model.updateActivePresetFromCurrentSetup()
        XCTAssertEqual(presets.activePreset?.shortClipSeconds, 8)
        XCTAssertEqual(presets.activePreset?.name, "Drone Day")
        XCTAssertFalse(model.activePresetIsEdited)

        // Switching back restores everything.
        model.applyPreset(standard)
        XCTAssertEqual(settings.destinationPath, movies.path)
        XCTAssertEqual(destinations.lastUsedID, moviesFavorite.id)
        XCTAssertEqual(settings.folderTemplate, NamingTemplates.defaultFolder)
        XCTAssertFalse(settings.quickDump)
        XCTAssertEqual(settings.fileRules, .standard)
        XCTAssertEqual(session.fileRules, .standard)
        XCTAssertEqual(settings.shortClipSeconds, 5)
    }

    func testAPresetWithADisconnectedDestinationStillAppliesTheRest() {
        let settings = AppSettings(defaults: nil)
        settings.destinationPath = folder.path
        let presets = PresetStore(fileURL: nil)
        let model = makeModel(settings: settings, destinations: DestinationStore(fileURL: nil), presets: presets)
        let gone = presets.add(OffloadPreset(name: "Gone", destinationPath: "/Volumes/Unplugged-\(UUID())",
                                             folderTemplate: "{year}/{month}", quickDump: true))
        model.applyPreset(gone)
        XCTAssertEqual(settings.destinationPath, folder.path, "Keeps the current folder")
        XCTAssertEqual(settings.folderTemplate, "{year}/{month}")
        XCTAssertTrue(settings.quickDump)
        XCTAssertTrue(model.activePresetIsEdited, "Shown as edited, since files won't go to the preset's folder")
    }

    func testEditedDetection() {
        let settings = AppSettings(defaults: nil)
        let preset = settings.makePreset(name: "P", destinationPath: nil, cameraID: nil)
        XCTAssertFalse(AppModel.preset(preset, differsFrom: settings, destinationPath: "/Anywhere"),
                       "A preset without a destination doesn't care where files go")
        settings.skipShortClips = false
        XCTAssertTrue(AppModel.preset(preset, differsFrom: settings, destinationPath: nil))
        settings.skipShortClips = true
        settings.fileRules.proxyExtensions = ["lrv"]
        XCTAssertTrue(AppModel.preset(preset, differsFrom: settings, destinationPath: nil))
        var withFolder = preset
        withFolder.destinationPath = "/Movies"
        settings.fileRules = .standard
        XCTAssertFalse(AppModel.preset(withFolder, differsFrom: settings, destinationPath: "/Movies/"))
        XCTAssertTrue(AppModel.preset(withFolder, differsFrom: settings, destinationPath: "/Other"))
    }

    func testShortClipSlider() {
        let settings = AppSettings(defaults: nil)
        XCTAssertEqual(settings.shortClipSliderSeconds, 5, "Default stays 5 s")
        settings.shortClipSliderSeconds = 0
        XCTAssertFalse(settings.skipShortClips)
        XCTAssertEqual(settings.shortClipSeconds, 5, "Off keeps the last threshold for the stepper")
        XCTAssertEqual(settings.shortClipSliderSeconds, 0)
        settings.shortClipSliderSeconds = 12
        XCTAssertTrue(settings.skipShortClips)
        XCTAssertEqual(settings.shortClipSeconds, 12)
        XCTAssertEqual(settings.shortClipRule, ShortClipRule(isEnabled: true, threshold: 12))
        settings.shortClipSliderSeconds = 30
        XCTAssertEqual(settings.shortClipSliderSeconds, 30)
    }
}
