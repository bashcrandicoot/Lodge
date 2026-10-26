import XCTest
@testable import Lodge

/// Proxies (.LRV/.LRF) and sidecars (.THM/.XML/.SRT) in their own folders, and the ignore list.
final class FileRulesTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("lodge-rules-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func file(_ path: String, minutesAfter minutes: Double = 0) -> Clip {
        var components = DateComponents()
        components.year = 2026; components.month = 10; components.day = 25; components.hour = 10
        let date = Calendar.current.date(from: components)!.addingTimeInterval(minutes * 60)
        return Clip(url: URL(fileURLWithPath: "/Volumes/CARD/" + path), relativePath: path,
                    size: 1, creationDate: date, modificationDate: date)
    }

    // MARK: Roles

    func testRolesFromExtensions() {
        let rules = FileRules.standard
        XCTAssertEqual(rules.role(of: "GL010001.LRV"), .proxy)
        XCTAssertEqual(rules.role(of: "DJI_0001.lrf"), .proxy)
        XCTAssertEqual(rules.role(of: "GX010001.THM"), .sidecar)
        XCTAssertEqual(rules.role(of: "C0001M01.XML"), .sidecar)
        XCTAssertEqual(rules.role(of: "DJI_0001.SRT"), .sidecar)
        XCTAssertEqual(rules.role(of: "GX010001.MP4"), .main)
        XCTAssertEqual(rules.role(of: "ZOOM0001.WAV"), .main)
        XCTAssertEqual(rules.role(of: "README"), .main)
        XCTAssertEqual(FileRules.keepTogether.role(of: "GL010001.LRV"), .main)
        XCTAssertEqual(MediaCategory.classify(fileName: "GL010001.LRV"), .other, "A proxy is never main video")
        XCTAssertEqual(FileRole.proxy.folderName, "Proxies")
        XCTAssertEqual(FileRole.sidecar.folderName, "Sidecars")
        XCTAssertNil(FileRole.main.folderName)
    }

    func testExtensionsAreCleanedUp() {
        XCTAssertEqual(FileRules.cleanExtension(".LRV"), "lrv")
        XCTAssertEqual(FileRules.cleanExtension("*.Thm"), "thm")
        XCTAssertEqual(FileRules.cleanExtension("  srt "), "srt")
        XCTAssertNil(FileRules.cleanExtension(""))
        XCTAssertNil(FileRules.cleanExtension("tar.gz"))
        XCTAssertNil(FileRules.cleanExtension("a b"))
        let rules = FileRules(proxyExtensions: ["LRV", ".lrv", "", "lrf"], sidecarExtensions: ["*.THM"],
                              ignorePatterns: [" .DS_Store ", ".ds_store", "", "a/b", "._*"])
        XCTAssertEqual(rules.proxyExtensions, ["lrv", "lrf"])
        XCTAssertEqual(rules.sidecarExtensions, ["thm"])
        XCTAssertEqual(rules.ignorePatterns, [".DS_Store", "._*"])
    }

    func testRulesRoundTripThroughJSON() throws {
        let rules = FileRules(proxyExtensions: ["lrv"], sidecarExtensions: ["thm", "xml"], ignorePatterns: ["*.tmp"])
        let data = try JSONEncoder().encode(rules)
        XCTAssertEqual(try JSONDecoder().decode(FileRules.self, from: data), rules)
    }

    // MARK: Ignore list

    func testIgnorePatterns() {
        let rules = FileRules.standard
        for name in [".DS_Store", ".ds_store", "._C0001.MP4", ".Spotlight-V100", ".Trashes", ".fseventsd",
                     ".TemporaryItems", "Thumbs.db"] {
            XCTAssertTrue(rules.isIgnored(name), name)
        }
        for name in ["C0001.MP4", "DS_Store", "_C0001.MP4", "MEDIAPRO.XML", "Trashes"] {
            XCTAssertFalse(rules.isIgnored(name), name)
        }
        // Extensions and patterns.
        XCTAssertTrue(FileRules.matches("GX010001.THM", pattern: ".thm"))
        XCTAssertTrue(FileRules.matches("GX010001.THM", pattern: "*.thm"))
        XCTAssertFalse(FileRules.matches(".thm", pattern: "*.lrv"))
        XCTAssertTrue(FileRules.matches("IMG_0001.JPG", pattern: "IMG_????.jpg"))
        XCTAssertFalse(FileRules.matches("IMG_00001.JPG", pattern: "IMG_????.jpg"))
        XCTAssertTrue(FileRules.matches("STATUS.BIN", pattern: "status.bin"))
        XCTAssertFalse(FileRules.matches("STATUS.BIN.bak", pattern: "status.bin"))
        XCTAssertFalse(FileRules.matches("anything", pattern: ""))
    }

    func testWarnsWhenAPatternHidesFootage() {
        XCTAssertTrue(FileRules.ignoresMainMedia("*.mp4"))
        XCTAssertTrue(FileRules.ignoresMainMedia(".MOV"))
        XCTAssertTrue(FileRules.ignoresMainMedia("*"))
        XCTAssertTrue(FileRules.ignoresMainMedia("C*"))
        XCTAssertFalse(FileRules.ignoresMainMedia(".DS_Store"))
        XCTAssertFalse(FileRules.ignoresMainMedia("._*"))
        XCTAssertFalse(FileRules.ignoresMainMedia("*.thm"))
    }

    private func write(_ path: String, card: URL) throws {
        let url = card.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url)
    }

    func testScanReportsIgnoredItemsAndSkipsThem() throws {
        let card = root.appendingPathComponent("CARD")
        try write("DCIM/100GOPRO/GX010001.MP4", card: card)
        try write("DCIM/100GOPRO/GL010001.LRV", card: card)
        try write("DCIM/100GOPRO/GX010001.THM", card: card)
        try write("DCIM/100GOPRO/Thumbs.db", card: card)
        try write("DCIM/100GOPRO/notes.tmp", card: card)
        try write(".DS_Store", card: card)
        try write(".Spotlight-V100/Store-V2/store.db", card: card)
        try write(".fseventsd/0000001", card: card)
        try write("Cache/a.bin", card: card)

        var rules = FileRules.standard
        rules.ignorePatterns += ["*.tmp", "Cache"]
        let report = ClipScanner.scanReport(volumeURL: card, rules: rules)
        XCTAssertEqual(report.files.map(\.relativePath), [
            "DCIM/100GOPRO/GL010001.LRV", "DCIM/100GOPRO/GX010001.MP4", "DCIM/100GOPRO/GX010001.THM",
        ])
        XCTAssertEqual(report.ignored, [
            ".DS_Store", ".Spotlight-V100", ".fseventsd", "Cache", "DCIM/100GOPRO/Thumbs.db",
            "DCIM/100GOPRO/notes.tmp",
        ], "A folder counts once; nothing inside it is listed")
        XCTAssertEqual(ClipScanner.scan(volumeURL: card).count, 5, "Without the extra patterns, notes.tmp and Cache/a.bin are files")
    }

    func testIgnoredFilesNeverBlockReadyToFormat() {
        let clip = file("DCIM/GX010001.MP4")
        var inventory = CardInventory(new: [], offloaded: [clip])
        inventory.ignored = [".DS_Store", ".Spotlight-V100", "DCIM/._GX010001.MP4"]
        let readiness = FormatReadiness(inventory: inventory)
        XCTAssertTrue(readiness.isReady)
        XCTAssertEqual(readiness.ignoredItems, 3)
        XCTAssertEqual(readiness.fileCount, 1)
        XCTAssertTrue(FormatReadiness.stillReady(inventory: inventory, volumeIdentity: "ID", discarding: []))
        let text = FormatAlert.text(cardName: "GoPro", readiness: readiness).message
        XCTAssertTrue(text.contains("3 ignored items"), text)
        XCTAssertFalse(FormatAlert.text(cardName: "GoPro", readiness: FormatReadiness(inventory: CardInventory(offloaded: [clip])))
            .message.contains("ignored"))
    }

    // MARK: Routing

    func testGoProProxiesAndThumbnailsGoIntoTheirOwnFolders() {
        let files = [
            file("DCIM/100GOPRO/GX010001.MP4"), file("DCIM/100GOPRO/GL010001.LRV"), file("DCIM/100GOPRO/GX010001.THM"),
            file("DCIM/100GOPRO/GX020001.MP4", minutesAfter: 1), file("DCIM/100GOPRO/GL020001.LRV", minutesAfter: 1),
            file("DCIM/100GOPRO/GX020001.THM", minutesAfter: 1),
        ]
        let plan = OffloadPlanner.plan(files: files, naming: .standard, context: NamingContext(project: "Surf"),
                                       existingNames: { _ in [] })
        XCTAssertEqual(plan.map(\.relativePath), [
            "2026-10-25/Surf/2026-10-25_Surf_0001.mp4",
            "2026-10-25/Surf/Proxies/2026-10-25_Surf_0001.lrv",
            "2026-10-25/Surf/Sidecars/2026-10-25_Surf_0001.thm",
            "2026-10-25/Surf/2026-10-25_Surf_0002.mp4",
            "2026-10-25/Surf/Proxies/2026-10-25_Surf_0002.lrv",
            "2026-10-25/Surf/Sidecars/2026-10-25_Surf_0002.thm",
        ])
        XCTAssertEqual(plan.map(\.role), [.main, .proxy, .sidecar, .main, .proxy, .sidecar])
        XCTAssertEqual(plan[1].sidecarOf, "GX010001.MP4")
    }

    func testDJIProxyTelemetryAndSonyXMLAreRouted() {
        let files = [
            file("DCIM/DJI_001/DJI_0001.MP4"), file("DCIM/DJI_001/DJI_0001.LRF"), file("DCIM/DJI_001/DJI_0001.SRT"),
            file("CLIP/C0001.MP4", minutesAfter: 1), file("CLIP/C0001M01.XML", minutesAfter: 1),
            file("CLIP/C0001.WAV", minutesAfter: 1),                  // audio partner: stays next to the clip
            file("MEDIAPRO.XML", minutesAfter: 2),                    // no partner: own name, no number
            file("DCIM/DJI_001/DJI_0009.LRF", minutesAfter: 3),       // proxy without its clip
            file("CLIP/C0002.MP4", minutesAfter: 4),
        ]
        let plan = OffloadPlanner.plan(files: files, naming: NamingTemplates(folder: "{date}", file: "{date}_{seq}")!,
                                       context: NamingContext(), existingNames: { _ in [] })
        XCTAssertEqual(plan.map(\.relativePath), [
            "2026-10-25/2026-10-25_0001.mp4",
            "2026-10-25/Proxies/2026-10-25_0001.lrf",
            "2026-10-25/Sidecars/2026-10-25_0001.srt",
            "2026-10-25/2026-10-25_0002.mp4",
            "2026-10-25/2026-10-25_0002.wav",
            "2026-10-25/Sidecars/2026-10-25_0002M01.xml",
            "2026-10-25/Sidecars/MEDIAPRO.xml",
            "2026-10-25/Proxies/DJI_0009.lrf",
            "2026-10-25/2026-10-25_0003.mp4",
        ], "Proxies and sidecars never use up a sequence number")
    }

    func testEditedListsChangeTheRouting() {
        let files = [file("DCIM/GX010001.MP4"), file("DCIM/GL010001.LRV"), file("DCIM/GX010001.THM")]
        let rules = FileRules(proxyExtensions: ["lrv", "thm"], sidecarExtensions: [], ignorePatterns: [])
        let plan = OffloadPlanner.plan(files: files, naming: NamingTemplates(folder: "", file: "{original}")!,
                                       context: NamingContext(), rules: rules, existingNames: { _ in [] })
        XCTAssertEqual(plan.map(\.relativePath), ["GX010001.mp4", "Proxies/GX010001.lrv", "Proxies/GX010001.thm"])
        let together = OffloadPlanner.plan(files: files, naming: NamingTemplates(folder: "", file: "{original}")!,
                                           context: NamingContext(), rules: .keepTogether, existingNames: { _ in [] })
        XCTAssertEqual(together.map(\.relativePath), ["GX010001.mp4", "GX010001.lrv", "GX010001.thm"])
    }

    func testProxiesAreNeverSkippedAsShortClipsAndStayWithTheirClip() {
        let short = file("DCIM/GX010001.MP4"), proxy = file("DCIM/GL010001.LRV"), thumb = file("DCIM/GX010001.THM")
        let long = file("DCIM/GX020001.MP4", minutesAfter: 1), longProxy = file("DCIM/GL020001.LRV", minutesAfter: 1)
        let files = [short, proxy, thumb, long, longProxy]
        let durations = [short.relativePath: 2.0, long.relativePath: 40.0,
                         // Even if a proxy's length were known, it isn't footage.
                         proxy.relativePath: 1.0, longProxy.relativePath: 1.0]
        let skip = ShortClipSkip.find(candidates: files, files: files, durations: durations,
                                      rule: ShortClipRule(isEnabled: true, threshold: 5), included: [], includeAll: false)
        XCTAssertEqual(skip.clips, [short])
        XCTAssertEqual(skip.ids, Set([short.relativePath, proxy.relativePath, thumb.relativePath]),
                       "A skipped clip's proxy and thumbnail stay on the card with it")
        XCTAssertFalse(skip.ids.contains(longProxy.relativePath))

        // Re-offloading a clip brings its proxy along.
        XCTAssertEqual(OffloadSelection.withSidecars([long.relativePath], files: files),
                       Set([long.relativePath, longProxy.relativePath]))
    }

    @MainActor
    func testSessionTreatsProxiesAsPartOfTheirClip() {
        let card = CardVolume(url: URL(fileURLWithPath: "/Volumes/GOPRO"), name: "GOPRO", uuid: "G")
        let short = file("DCIM/GX010001.MP4"), proxy = file("DCIM/GL010001.LRV")
        let session = OffloadSession(card: card, inventory: CardInventory(new: [short, proxy]),
                                     durations: [short.relativePath: 1, proxy.relativePath: 1])
        session.shortRule = ShortClipRule(isEnabled: true, threshold: 5)
        XCTAssertTrue(session.isShortClip(short))
        XCTAssertFalse(session.isShortClip(proxy))
        XCTAssertEqual(session.newClips, [], "The proxy stays behind with its short clip")
        session.toggleIncludeShort(short)
        XCTAssertEqual(Set(session.newClips.map(\.relativePath)), Set([proxy.relativePath, short.relativePath]))
    }

    @MainActor
    func testFileRulesPersist() throws {
        let suite = "LodgeTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.fileRules, .standard)
        settings.fileRules.ignorePatterns.append("*.tmp")
        settings.fileRules.proxyExtensions = ["lrv"]
        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.fileRules.ignorePatterns.last, "*.tmp")
        XCTAssertEqual(reloaded.fileRules.proxyExtensions, ["lrv"])
    }
}
