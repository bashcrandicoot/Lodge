import XCTest
@testable import Lodge

/// Lodge was SnapDrop: its first launch copies SnapDrop's files and settings.
final class LegacyMigrationTests: XCTestCase {
    private var root: URL!
    private var legacy: URL!
    private var current: URL!
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("lodge-migration-\(UUID().uuidString)")
        legacy = root.appendingPathComponent("SnapDrop", isDirectory: true)
        current = root.appendingPathComponent("Lodge", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        suite = "LodgeMigrationTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suite)
    }

    private func write(_ text: String, _ name: String, in folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: folder.appendingPathComponent(name))
    }

    private func read(_ name: String, in folder: URL) -> String? {
        (try? Data(contentsOf: folder.appendingPathComponent(name))).flatMap { String(data: $0, encoding: .utf8) }
    }

    func testCopiesEveryFileAndLeavesTheOriginals() throws {
        try write("ledger", "ledger.json", in: legacy)
        try write("destinations", "destinations.json", in: legacy)
        try write("cameras", "cameras.json", in: legacy)
        try write("presets", "presets.json", in: legacy)
        try write("junk", ".DS_Store", in: legacy)

        let outcome = LegacyMigration.runIfNeeded(defaults: defaults, legacySettings: [:],
                                                  legacyFolder: legacy, folder: current)

        XCTAssertEqual(outcome?.copiedFiles, ["cameras.json", "destinations.json", "ledger.json", "presets.json"])
        XCTAssertEqual(read("ledger.json", in: current), "ledger")
        XCTAssertEqual(read("destinations.json", in: current), "destinations")
        XCTAssertNil(read(".DS_Store", in: current), "Finder's files aren't copied")
        // Copied, not moved: SnapDrop's folder is untouched.
        XCTAssertEqual(read("ledger.json", in: legacy), "ledger")
        XCTAssertEqual(read("presets.json", in: legacy), "presets")
    }

    func testNeverOverwritesLodgeData() throws {
        try write("old", "ledger.json", in: legacy)
        try write("old", "destinations.json", in: legacy)
        try write("new", "ledger.json", in: current)

        let outcome = LegacyMigration.runIfNeeded(defaults: defaults, legacySettings: [:],
                                                  legacyFolder: legacy, folder: current)

        XCTAssertEqual(outcome?.copiedFiles, ["destinations.json"])
        XCTAssertEqual(read("ledger.json", in: current), "new")
    }

    @MainActor
    func testCopiesSettingsButNotSystemKeysOrDemoFlags() {
        let legacySettings: [String: Any] = [
            "theme": "aurora",
            "appearance": "light",
            "fileTemplate": "{date}_{project}_{camera}_{seq}",
            "recentProjects": ["Offload"],
            "skipShortClips": true,
            "shortClipSeconds": 5,
            "NSWindow Frame main": "244 142 1240 800 0 0 1728 1084 ",
            "NSOSPLastRootDirectory": Data([1, 2]),
            "SnapDropDemo": true,
        ]
        defaults.set("ember", forKey: "theme") // Lodge's own value wins.

        let outcome = LegacyMigration.runIfNeeded(defaults: defaults, legacySettings: legacySettings,
                                                  legacyFolder: legacy, folder: current)

        XCTAssertEqual(outcome?.copiedSettings,
                       ["appearance", "fileTemplate", "recentProjects", "shortClipSeconds", "skipShortClips"])
        XCTAssertEqual(defaults.string(forKey: "theme"), "ember")
        XCTAssertEqual(defaults.string(forKey: "appearance"), "light")
        XCTAssertEqual(defaults.stringArray(forKey: "recentProjects"), ["Offload"])
        XCTAssertEqual(defaults.integer(forKey: "shortClipSeconds"), 5)
        XCTAssertNil(defaults.object(forKey: "NSWindow Frame main"))
        XCTAssertNil(defaults.object(forKey: "SnapDropDemo"))

        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.fileTemplate, "{date}_{project}_{camera}_{seq}")
        XCTAssertEqual(settings.themeID, .ember)
    }

    func testRunsOnlyOnce() throws {
        try write("ledger", "ledger.json", in: legacy)
        XCTAssertNotNil(LegacyMigration.runIfNeeded(defaults: defaults, legacySettings: ["theme": "ocean"],
                                                    legacyFolder: legacy, folder: current))
        XCTAssertTrue(defaults.bool(forKey: LegacyMigration.doneKey))

        try FileManager.default.removeItem(at: current.appendingPathComponent("ledger.json"))
        defaults.removeObject(forKey: "theme")
        XCTAssertNil(LegacyMigration.runIfNeeded(defaults: defaults, legacySettings: ["theme": "ocean"],
                                                 legacyFolder: legacy, folder: current))
        XCTAssertNil(read("ledger.json", in: current), "A second launch doesn't copy again")
        XCTAssertNil(defaults.string(forKey: "theme"))
    }

    func testNothingToMigrateIsFine() {
        let missing = root.appendingPathComponent("nothing-here")
        let outcome = LegacyMigration.runIfNeeded(defaults: defaults, legacySettings: [:],
                                                  legacyFolder: missing, folder: current)
        XCTAssertEqual(outcome, LegacyMigration.Outcome())
        XCTAssertFalse(FileManager.default.fileExists(atPath: current.path), "No empty folder is created")
    }

    func testReadsAUserDefaultsDomain() {
        defaults.set("twilight", forKey: "theme")
        defaults.synchronize()
        let read = LegacyMigration.readLegacySettings(domain: suite)
        XCTAssertEqual(read["theme"] as? String, "twilight")
        XCTAssertTrue(LegacyMigration.readLegacySettings(domain: "com.example.nothing-\(UUID().uuidString)").isEmpty)
    }

    @MainActor
    func testMigratedDataLoadsInLodgeStores() throws {
        let ledgerURL = legacy.appendingPathComponent("ledger.json")
        let source = Ledger(fileURL: ledgerURL)
        XCTAssertTrue(source.entries.isEmpty)
        try write("[]", "cameras.json", in: legacy)
        _ = LegacyMigration.copyFiles(from: legacy, to: current)
        XCTAssertEqual(read("cameras.json", in: current), "[]")
    }

    func testOldUnfinishedCopiesStillReserveTheirNumbers() {
        XCTAssertEqual(LegacyMigration.withoutPartialSuffix("A_0003.mp4.snapdrop-partial"), "A_0003.mp4")
        XCTAssertEqual(LegacyMigration.withoutPartialSuffix("A_0004.mp4\(Copier.partialSuffix)"), "A_0004.mp4")
        XCTAssertEqual(LegacyMigration.withoutPartialSuffix("A_0005.mp4"), "A_0005.mp4")
    }
}
