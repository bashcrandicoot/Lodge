import XCTest
@testable import Lodge

/// "Skip short videos": the threshold, unknown lengths, sidecars, readiness and the duration scan.
final class ShortClipTests: XCTestCase {
    private let identity = "CARD-UUID"
    private let start = Date(timeIntervalSince1970: 1_761_400_000)

    private func clip(_ path: String, size: Int64 = 100, minutesAfter minutes: Double = 0) -> Clip {
        let date = start.addingTimeInterval(minutes * 60)
        return Clip(url: URL(fileURLWithPath: "/Volumes/SD Card/" + path), relativePath: path, size: size,
                    creationDate: date, modificationDate: date)
    }

    // C0001 is 2 s (with an XML sidecar), C0002 is 30 s, C0003.BRAW has no known length,
    // C0004 is exactly 5 s, and a photo.
    private lazy var short = clip("CLIP/C0001.MP4", minutesAfter: 0)
    private lazy var shortXML = clip("CLIP/C0001M01.XML", size: 5, minutesAfter: 0)
    private lazy var long = clip("CLIP/C0002.MP4", minutesAfter: 1)
    private lazy var braw = clip("CLIP/C0003.BRAW", minutesAfter: 2)
    private lazy var exact = clip("CLIP/C0004.MP4", minutesAfter: 3)
    private lazy var photo = clip("DCIM/DSC00001.ARW", minutesAfter: 4)
    private var files: [Clip] { [short, shortXML, long, braw, exact, photo] }
    private var durations: [String: Double] {
        [short.relativePath: 2, long.relativePath: 30, exact.relativePath: 5]
    }

    private func select(rule: ShortClipRule = ShortClipRule(), included: Set<String> = [], all: Bool = false,
                        inventory: CardInventory? = nil, reoffload: ReoffloadMode = .off) -> OffloadSelection {
        OffloadSelection.make(inventory: inventory ?? CardInventory(new: files),
                              categories: Set(MediaCategory.allCases), reoffload: reoffload, reoffloadIDs: [],
                              shortRule: rule, durations: durations, includedShortIDs: included,
                              includeAllShort: all)
    }

    func testThreshold() {
        let rule = ShortClipRule(isEnabled: true, threshold: 5)
        XCTAssertTrue(rule.isShort(0.4))
        XCTAssertTrue(rule.isShort(4.99))
        XCTAssertFalse(rule.isShort(5))
        XCTAssertFalse(rule.isShort(60))
        XCTAssertFalse(ShortClipRule.off.isShort(1))
        XCTAssertTrue(ShortClipRule(isEnabled: true, threshold: 60).isShort(59))
        XCTAssertEqual(ShortClipRule().threshold, 5)
        XCTAssertTrue(ShortClipRule().isEnabled)
    }

    func testUnknownLengthIsNeverSkipped() {
        let rule = ShortClipRule(isEnabled: true, threshold: 60)
        XCTAssertFalse(rule.isShort(nil))
        XCTAssertFalse(rule.isShort(.nan))
        XCTAssertFalse(rule.isShort(-1))
        let selection = select(rule: rule)
        XCTAssertTrue(selection.toCopy.contains(braw))
        XCTAssertFalse(selection.skippedShort.ids.contains(braw.relativePath))
        XCTAssertFalse(AVDurationReader.canRead(braw.url))
        XCTAssertFalse(AVDurationReader.canRead(URL(fileURLWithPath: "/A/B001.R3D")))
        XCTAssertTrue(AVDurationReader.canRead(long.url))
    }

    func testShortClipsAndTheirSidecarsAreNotCopied() {
        let selection = select()
        XCTAssertEqual(selection.skippedShort.clips, [short])
        XCTAssertEqual(selection.skippedShort.ids, [short.relativePath, shortXML.relativePath])
        XCTAssertEqual(selection.skippedShort.sidecarCounts[short.relativePath], 1)
        XCTAssertEqual(Set(selection.toCopy.map(\.relativePath)),
                       [long.relativePath, braw.relativePath, exact.relativePath, photo.relativePath])
    }

    func testIncludeAnywayAndIncludeAll() {
        let one = select(included: [short.relativePath])
        XCTAssertTrue(one.skippedShort.isEmpty)
        XCTAssertTrue(one.toCopy.contains(short))
        XCTAssertTrue(one.toCopy.contains(shortXML))

        let all = select(rule: ShortClipRule(isEnabled: true, threshold: 40), all: true)
        XCTAssertTrue(all.skippedShort.isEmpty)
        XCTAssertEqual(all.toCopy.count, files.count)

        let off = select(rule: .off)
        XCTAssertEqual(off.toCopy.count, files.count)
    }

    func testRaisingTheThresholdSkipsMore() {
        let selection = select(rule: ShortClipRule(isEnabled: true, threshold: 31))
        XCTAssertEqual(Set(selection.skippedShort.clips), [short, long, exact])
        XCTAssertTrue(selection.toCopy.contains(braw))
    }

    func testReoffloadsIgnoreTheRule() {
        // An offloaded short clip whose copy went missing is still copied when re-offloading.
        let inventory = CardInventory(new: [long], missing: [short, shortXML])
        let selection = select(inventory: inventory, reoffload: .missing)
        XCTAssertTrue(selection.skippedShort.isEmpty)
        XCTAssertTrue(selection.toCopy.contains(short))
    }

    func testReadinessCountsSkippedClipsSeparately() {
        let skip = select().skippedShort
        // Everything else was offloaded.
        let inventory = CardInventory(new: [short, shortXML], offloaded: [long, braw, exact, photo])
        let readiness = FormatReadiness(inventory: inventory, skipped: skip)
        XCTAssertFalse(readiness.isReady)
        XCTAssertTrue(readiness.isReadyExceptShortClips)
        XCTAssertEqual(readiness.notOffloaded, 0)
        XCTAssertEqual(readiness.shortSkippedFiles, 2)
        XCTAssertEqual(readiness.shortSkippedClips, 1)
        XCTAssertEqual(readiness.offloadedFiles, 4)
        XCTAssertEqual(readiness.pendingText, "1 short clip not offloaded")
        XCTAssertEqual(FormatAlert.formatTitle(readiness), "Format and Discard 1 Short Clip")
        XCTAssertTrue(FormatAlert.text(cardName: "SD", readiness: readiness).message.contains("will be lost"))

        // Other files still pending: not ready, and the pending files come first.
        let pending = FormatReadiness(inventory: CardInventory(new: [short, shortXML, long], offloaded: [photo]),
                                      skipped: skip)
        XCTAssertFalse(pending.isReady)
        XCTAssertFalse(pending.isReadyExceptShortClips)
        XCTAssertEqual(pending.pendingText, "1 file not yet offloaded")

        // Without skipped clips, nothing changes.
        let ready = FormatReadiness(inventory: CardInventory(offloaded: files))
        XCTAssertTrue(ready.isReady)
        XCTAssertEqual(FormatAlert.formatTitle(ready), "Format")
    }

    func testFormatRecheckOnlyAllowsTheAgreedFiles() {
        let agreed = Set([short, shortXML].map { $0.ledgerKey(volumeIdentity: identity) })
        XCTAssertTrue(FormatReadiness.stillReady(
            inventory: CardInventory(new: [short, shortXML], offloaded: [long]), volumeIdentity: identity,
            discarding: agreed))
        // A new file appeared, or the short clip changed: refuse.
        XCTAssertFalse(FormatReadiness.stillReady(
            inventory: CardInventory(new: [short, shortXML, exact], offloaded: [long]), volumeIdentity: identity,
            discarding: agreed))
        let changed = clip("CLIP/C0001.MP4", size: 999)
        XCTAssertFalse(FormatReadiness.stillReady(
            inventory: CardInventory(new: [changed, shortXML], offloaded: [long]), volumeIdentity: identity,
            discarding: agreed))
        XCTAssertFalse(FormatReadiness.stillReady(
            inventory: CardInventory(offloaded: [long], missing: [photo]), volumeIdentity: identity, discarding: []))
        XCTAssertFalse(FormatReadiness.stillReady(inventory: CardInventory(), volumeIdentity: identity, discarding: []))
    }

    func testOffloadBlockerWhenOnlyShortClipsAreLeft() {
        XCTAssertEqual(OffloadReadiness.blocker(hasCard: true, isScanning: false, newFileCount: 0, shortClipsSkipped: 2,
                                                project: "A", hasDestination: true, requiredBytes: 0, availableBytes: nil),
                       "Only short clips are left — choose Include All Short Clips to offload them")
    }

    func testDurationFormatting() {
        XCTAssertEqual(DurationFormatting.short(3.7), "0:03")
        XCTAssertEqual(DurationFormatting.short(75), "1:15")
        XCTAssertEqual(DurationFormatting.short(3_725), "1:02:05")
        XCTAssertEqual(DurationFormatting.threshold(1), "1 second")
        XCTAssertEqual(DurationFormatting.threshold(5), "5 seconds")
    }

    func testDurationScanUsesTheCacheAndOnlyReadsVideos() async {
        let reader = FakeReader(values: [long.url.path: 30])
        let cached = [short.ledgerKey(volumeIdentity: identity): Optional(2.0)]
        let result = await DurationScanner.read(files, volumeIdentity: identity, cache: cached, reader: reader)
        XCTAssertEqual(result.byPath[short.relativePath], 2)
        XCTAssertEqual(result.byPath[long.relativePath], 30)
        XCTAssertNil(result.byPath[braw.relativePath])
        // short came from the cache; the photo and XML aren't videos.
        let read = await reader.readPaths()
        XCTAssertEqual(Set(read), [long.url.path, braw.url.path, exact.url.path])
        XCTAssertEqual(result.fresh.count, 3)
        XCTAssertEqual(result.fresh[braw.ledgerKey(volumeIdentity: identity)], .some(nil))
    }

    @MainActor
    func testSessionSkipsAndIncludes() {
        let card = CardVolume(url: URL(fileURLWithPath: "/Volumes/SD Card"), name: "SD Card", uuid: identity)
        let session = OffloadSession(card: card, inventory: CardInventory(new: files), durations: durations)
        XCTAssertTrue(session.skippedShort.isEmpty)   // the rule is off until the app sets it
        session.shortRule = ShortClipRule()
        XCTAssertEqual(session.skippedShort.clips, [short])
        XCTAssertFalse(session.newClips.contains(short))
        XCTAssertEqual(session.duration(of: short), 2)
        session.toggleIncludeShort(short)
        XCTAssertTrue(session.newClips.contains(short))
        XCTAssertTrue(session.isIncludedShortClip(short))
        session.toggleIncludeShort(short)
        XCTAssertFalse(session.newClips.contains(short))
        session.includeAllShort = true
        XCTAssertTrue(session.skippedShort.isEmpty)
        session.toggleIncludeShort(short)   // skip one again from "all"
        XCTAssertFalse(session.includeAllShort)
        XCTAssertEqual(session.skippedShort.clips, [short])
    }

    @MainActor
    func testSettingsDefaultsAndClamping() {
        let settings = AppSettings(defaults: nil)
        XCTAssertTrue(settings.skipShortClips)
        XCTAssertEqual(settings.shortClipSeconds, 5)
        settings.shortClipSeconds = 99
        XCTAssertEqual(settings.shortClipSeconds, 60)
        settings.shortClipSeconds = 0
        XCTAssertEqual(settings.shortClipSeconds, 1)
        settings.skipShortClips = false
        XCTAssertEqual(settings.shortClipRule, .off.with(threshold: 1))
    }
}

private extension ShortClipRule {
    func with(threshold: Double) -> ShortClipRule {
        var copy = self
        copy.threshold = threshold
        return copy
    }
}

private actor FakeReader: DurationReading {
    let values: [String: Double]
    private var paths: [String] = []

    init(values: [String: Double]) { self.values = values }

    func duration(of url: URL) async -> Double? {
        paths.append(url.path)
        return values[url.path]
    }

    func readPaths() -> [String] { paths }
}
