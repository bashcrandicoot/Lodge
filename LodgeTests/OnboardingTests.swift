import XCTest
@testable import Lodge

/// First-launch setup ("Set up your first preset"): steps, resuming, who sees it, and that
/// every choice lands in the real settings, favorites and presets.
@MainActor
final class OnboardingTests: XCTestCase {
    private var folder: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("lodge-onboarding-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        suiteName = "lodge-onboarding-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeModel(destinations: DestinationStore? = nil, presets: PresetStore? = nil,
                           ledger: Ledger? = nil) -> AppModel {
        AppModel(settings: AppSettings(defaults: nil),
                 ledger: ledger ?? Ledger(fileURL: folder.appendingPathComponent("ledger.json")),
                 cameras: CameraStore(fileURL: nil),
                 destinations: destinations ?? DestinationStore(fileURL: nil, folderExists: { _ in true }),
                 presets: presets ?? PresetStore(fileURL: nil), startWatching: false)
    }

    private func destinationFolder() throws -> String {
        let url = folder.appendingPathComponent("Projects", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.path
    }

    // MARK: Steps

    func testStepsRunSplashToDoneAndOnlyFiveAreNumbered() {
        XCTAssertEqual(OnboardingStep.allCases.first, .splash)
        XCTAssertEqual(OnboardingStep.allCases.last, .done)
        XCTAssertEqual(OnboardingStep.numbered.map(\.number), [1, 2, 3, 4, 5])
        XCTAssertNil(OnboardingStep.splash.number)
        XCTAssertNil(OnboardingStep.done.number)
        XCTAssertEqual(OnboardingStep.destination.next, .folders)
        XCTAssertEqual(OnboardingStep.destination.previous, .template)
        XCTAssertNil(OnboardingStep.done.next)
        XCTAssertNil(OnboardingStep.splash.previous)
        XCTAssertEqual(OnboardingStep.allCases.filter(\.forcesDarkAppearance), [.splash, .done],
                       "Only the night-scene screens are forced dark")
    }

    func testCantLeaveDestinationWithoutAFolderOrSaveABrokenTemplate() throws {
        let store = OnboardingStore(defaults: nil)
        store.go(to: .destination)
        store.goForward()
        XCTAssertEqual(store.step, .destination, "A destination is required")
        store.draft.destinationPath = try destinationFolder()
        store.goForward()
        XCTAssertEqual(store.step, .folders)

        store.draft.folderTemplate = "{project}/{nope}"
        XCTAssertFalse(store.draft.canLeave(.folders))
        XCTAssertFalse(store.draft.folderIssues.isEmpty)
        store.goForward()
        XCTAssertEqual(store.step, .folders)
        store.draft.folderTemplate = "{project}/{date}"
        store.goForward()
        XCTAssertEqual(store.step, .naming)

        store.draft.fileTemplate = ""
        XCTAssertFalse(store.draft.canLeave(.naming))
        store.draft.renameFiles = false
        XCTAssertEqual(store.draft.effectiveFileTemplate, "{original}", "Rename off keeps the camera's names")
        XCTAssertTrue(store.draft.canLeave(.naming))

        store.goBack()
        XCTAssertEqual(store.step, .folders)
    }

    func testSidebarOnlyJumpsBackwards() {
        let store = OnboardingStore(defaults: nil)
        store.go(to: .folders)
        XCTAssertTrue(store.canJump(to: .template))
        XCTAssertTrue(store.canJump(to: .folders))
        XCTAssertFalse(store.canJump(to: .naming))
        XCTAssertFalse(store.canJump(to: .splash))
    }

    // MARK: Starters

    func testEveryStarterIsARealNamingExample() {
        for starter in OnboardingStarter.allCases {
            let preset = starter.namingPreset
            XCTAssertTrue(NamingPreset.all.contains(preset), "\(starter) uses a Settings ▸ Naming example")
            XCTAssertNotNil(NamingTemplates(folder: preset.folder, file: preset.file), "\(starter) is valid")
        }
        XCTAssertEqual(OnboardingStarter.filmShoot.namingPreset.folder, "{project}/{date}/{camera}")
        XCTAssertEqual(OnboardingStarter.dailyArchive.namingPreset.folder, "{year}/{month}/{day}")
        XCTAssertEqual(OnboardingStarter.blank.namingPreset.folder, "")
    }

    func testChoosingAStarterKeepsATypedName() {
        var draft = OnboardingDraft()
        draft.choose(.podcast)
        XCTAssertEqual(draft.presetName, "Podcast")
        XCTAssertEqual(draft.folderTemplate, "{project}/{type}/{date}")
        draft.presetName = "Morning Show"
        draft.nameEdited = true
        draft.choose(.photoSession)
        XCTAssertEqual(draft.presetName, "Morning Show")
        XCTAssertEqual(draft.folderTemplate, NamingTemplates.defaultFolder)
    }

    // MARK: Resuming

    func testProgressIsSavedAndResumes() throws {
        let path = try destinationFolder()
        let first = OnboardingStore(defaults: defaults)
        first.go(to: .naming)
        first.draft.destinationPath = path
        first.draft.choose(.dailyArchive)
        first.draft.ejectAfterOffload = true

        let again = OnboardingStore(defaults: defaults)
        XCTAssertEqual(again.step, .naming)
        XCTAssertEqual(again.draft, first.draft)
        XCTAssertFalse(again.isFinished)
    }

    func testSkippingChangesNothingAndNeverShowsAgain() {
        let model = makeModel()
        let settingsBefore = (model.settings.folderTemplate, model.settings.fileTemplate, model.settings.ejectAfterOffload,
                              model.settings.playSuccessSound, model.settings.askToImport)
        let store = OnboardingStore(defaults: defaults)
        XCTAssertTrue(store.shouldShow(for: model))
        store.go(to: .folders)
        store.draft.choose(.podcast)
        store.skip()

        XCTAssertTrue(model.presets.presets.isEmpty)
        XCTAssertTrue(model.destinations.favorites.isEmpty)
        XCTAssertEqual(model.settings.folderTemplate, settingsBefore.0)
        XCTAssertEqual(model.settings.fileTemplate, settingsBefore.1)
        XCTAssertEqual(model.settings.ejectAfterOffload, settingsBefore.2)
        XCTAssertEqual(model.settings.playSuccessSound, settingsBefore.3)
        XCTAssertEqual(model.settings.askToImport, settingsBefore.4)

        let next = OnboardingStore(defaults: defaults)
        XCTAssertFalse(next.shouldShow(for: model))
        XCTAssertNil(defaults.object(forKey: OnboardingStore.Key.draft), "The draft is thrown away")
    }

    func testRestartStartsOverFromTheSplash() {
        let store = OnboardingStore(defaults: defaults)
        store.go(to: .review)
        store.markFinished()
        store.restart()
        XCTAssertFalse(store.isFinished)
        XCTAssertEqual(store.step, .splash)
        XCTAssertEqual(store.draft, OnboardingDraft())
        XCTAssertFalse(defaults.bool(forKey: OnboardingStore.Key.finished))
    }

    // MARK: Who sees it

    func testExistingUsersNeverSeeSetup() throws {
        let path = try destinationFolder()
        let withFavorite = makeModel(destinations: DestinationStore(fileURL: nil, folderExists: { _ in true }))
        withFavorite.destinations.add(path: path)
        let store = OnboardingStore(defaults: defaults)
        XCTAssertFalse(store.shouldShow(for: withFavorite))
        XCTAssertTrue(store.isFinished, "Marked as done so an update never greets them with it")

        let presets = PresetStore(fileURL: nil)
        presets.add(OffloadPreset(name: "Drone"))
        XCTAssertFalse(OnboardingStore(defaults: nil).shouldShow(for: makeModel(presets: presets)))

        let ledger = Ledger(fileURL: folder.appendingPathComponent("used.json"))
        ledger.add(LedgerEntry(sourceKey: "k", cardName: "A001", sourceRelativePath: "C0001.MP4",
                               destinationPath: path + "/C0001.MP4", size: 1, sha256: "00", offloadedAt: Date()))
        XCTAssertFalse(OnboardingStore(defaults: nil).shouldShow(for: makeModel(ledger: ledger)))

        XCTAssertTrue(OnboardingStore(defaults: nil).shouldShow(for: makeModel()), "A brand-new user sees it")
    }

    // MARK: Saving

    func testSavingCreatesThePresetFavoriteAndSettings() throws {
        let path = try destinationFolder()
        let model = makeModel()
        let store = OnboardingStore(defaults: defaults)
        store.draft.choose(.filmShoot)
        store.draft.destinationPath = path
        store.draft.fileTemplate = "{date}_{camera}_{seq}"
        store.draft.skipShortClips = true
        store.draft.shortClipSeconds = 3
        store.draft.ejectAfterOffload = true
        store.draft.playSuccessSound = false
        store.draft.askToImport = false
        store.go(to: .review)

        let preset = try XCTUnwrap(store.save(into: model))
        XCTAssertEqual(store.step, .done)
        XCTAssertEqual(store.savedPreset, preset)

        XCTAssertEqual(model.presets.presets.map(\.name), ["Film Shoot"])
        XCTAssertEqual(preset.destinationPath, path)
        XCTAssertEqual(preset.folderTemplate, "{project}/{date}/{camera}")
        XCTAssertEqual(preset.fileTemplate, "{date}_{camera}_{seq}")
        XCTAssertTrue(preset.skipShortClips)
        XCTAssertEqual(preset.shortClipSeconds, 3)
        XCTAssertFalse(preset.quickDump)
        XCTAssertEqual(model.presets.activeID, preset.id, "Switch to this preset now")

        let favorite = try XCTUnwrap(model.destinations.favorite(forPath: path))
        XCTAssertEqual(model.destinations.defaultID, favorite.id)
        XCTAssertEqual(model.settings.destinationPath, path)
        XCTAssertEqual(model.settings.folderTemplate, "{project}/{date}/{camera}")
        XCTAssertEqual(model.settings.fileTemplate, "{date}_{camera}_{seq}")
        XCTAssertEqual(model.settings.shortClipSeconds, 3)
        XCTAssertTrue(model.settings.ejectAfterOffload)
        XCTAssertFalse(model.settings.playSuccessSound)
        XCTAssertFalse(model.settings.askToImport)
    }

    func testSavingWithoutUsingItNowLeavesTheCurrentSetupAlone() throws {
        let path = try destinationFolder()
        let other = folder.appendingPathComponent("Other").path
        try FileManager.default.createDirectory(atPath: other, withIntermediateDirectories: true)
        let model = makeModel()
        let existing = model.destinations.add(path: other)
        let templateBefore = model.settings.folderTemplate

        var draft = OnboardingDraft()
        draft.choose(.podcast)
        draft.destinationPath = path
        draft.makeDefaultDestination = false
        draft.useNow = false
        draft.renameFiles = false
        let preset = OnboardingApplier.apply(draft, to: model)

        XCTAssertEqual(preset.fileTemplate, "{original}")
        XCTAssertNil(model.presets.activeID)
        XCTAssertEqual(model.settings.folderTemplate, templateBefore)
        XCTAssertEqual(model.destinations.defaultID, existing.id, "The default stays")
        XCTAssertNotNil(model.destinations.favorite(forPath: path), "…but the folder is still a favorite")
    }

    func testCantSaveWithoutADestination() {
        let model = makeModel()
        let store = OnboardingStore(defaults: nil)
        store.go(to: .review)
        XCTAssertNil(store.save(into: model))
        XCTAssertEqual(store.step, .review)
        XCTAssertTrue(model.presets.presets.isEmpty)
    }

    // MARK: Previews

    func testSamplePreviewUsesTheRealPlanner() throws {
        var draft = OnboardingDraft()
        draft.choose(.filmShoot)
        let plan = OnboardingSamples.plan(draft)
        XCTAssertEqual(plan.count, OnboardingSamples.clips().count)
        let mxf = try XCTUnwrap(plan.first { $0.originalName == "A001C003_230914_R2EK.MXF" })
        XCTAssertEqual(mxf.folder, "Northwind/2026-10-26/FX6/MXF", "One folder per type inside the last level")
        XCTAssertEqual(mxf.fileName, "2026-10-26_Northwind_FX6_0001.mxf")

        draft.renameFiles = false
        XCTAssertTrue(OnboardingSamples.plan(draft).contains { $0.fileName == "A001C003_230914_R2EK.mxf" || $0.fileName == "A001C003_230914_R2EK.MXF" })

        let rows = PreviewTree.rows(root: "Projects", plan: plan, filesPerFolder: 1)
        XCTAssertEqual(rows.first?.kind, .root)
        XCTAssertEqual(rows.filter { $0.kind == .folder }.map(\.name), ["Northwind", "2026-10-26", "FX6", "ARW", "MXF", "WAV"])
        XCTAssertTrue(rows.contains { $0.kind == .more && $0.name == "… 2 more" })
    }

    func testTemplatePiecesSplitTokensForThePills() {
        XCTAssertEqual(TemplatePieces.split("{date}_{project}_{seq:3}"), [
            .token("{date}", .date), .literal("_"), .token("{project}", .project), .literal("_"), .token("{seq:3}", .seq),
        ])
        XCTAssertEqual(TemplatePieces.split("{shoot}/raw"), [.token("{shoot}", .project), .literal("/raw")])
        XCTAssertEqual(TemplatePieces.split("{oops"), [.literal("{oops")])
    }
}
