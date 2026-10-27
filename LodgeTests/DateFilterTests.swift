import XCTest
@testable import Lodge

/// "Dates": any date, today, last 7 days, custom ranges (whole days), which date a file is
/// judged by, sidecars following their clip, and the selection, preview and plan that use it.
final class DateFilterTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    /// 2026-10-27 at the given time, New York.
    private func oct(_ day: Int, _ hour: Int = 12, _ minute: Int = 0, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute, second: second))!
    }

    private var now: Date { oct(27, 15, 30) }

    private func clip(_ path: String, created: Date?, modified: Date? = nil, size: Int64 = 100) -> Clip {
        Clip(url: URL(fileURLWithPath: "/Volumes/SD Card/" + path), relativePath: path, size: size,
             creationDate: created, modificationDate: modified ?? created)
    }

    private func passes(_ filter: DateFilter, _ clip: Clip) -> Bool {
        filter.includes(clip, now: now, calendar: calendar)
    }

    // MARK: Modes

    func testAnyDateLetsEverythingThrough() {
        let filter = DateFilter.any
        XCTAssertFalse(filter.isActive)
        XCTAssertNil(filter.interval(now: now, calendar: calendar))
        XCTAssertTrue(passes(filter, clip("A.MP4", created: oct(1))))
        XCTAssertTrue(passes(filter, clip("B.MP4", created: Date.distantPast)))
        XCTAssertTrue(passes(filter, clip("C.MP4", created: nil, modified: nil)), "No date at all is fine with Any date")
    }

    func testToday() {
        let filter = DateFilter(mode: .today)
        XCTAssertEqual(filter.interval(now: now, calendar: calendar), oct(27, 0)..<oct(28, 0))
        XCTAssertTrue(passes(filter, clip("A.MP4", created: oct(27, 0, 0, 0))), "Midnight this morning")
        XCTAssertTrue(passes(filter, clip("B.MP4", created: oct(27, 23, 59, 59))), "Later today")
        XCTAssertFalse(passes(filter, clip("C.MP4", created: oct(26, 23, 59, 59))), "Yesterday")
        XCTAssertFalse(passes(filter, clip("D.MP4", created: oct(28, 0))), "Tomorrow (wrong camera clock)")
    }

    func testLastSevenDaysIsTodayAndTheSixBefore() {
        let filter = DateFilter(mode: .last7Days)
        XCTAssertEqual(filter.interval(now: now, calendar: calendar), oct(21, 0)..<oct(28, 0))
        XCTAssertTrue(passes(filter, clip("A.MP4", created: oct(21, 0))))
        XCTAssertTrue(passes(filter, clip("B.MP4", created: oct(24))))
        XCTAssertTrue(passes(filter, clip("C.MP4", created: oct(27, 23, 59, 59))))
        XCTAssertFalse(passes(filter, clip("D.MP4", created: oct(20, 23, 59, 59))), "Eight days ago")
    }

    func testCustomRangeIncludesTheWholeLastDay() {
        let filter = DateFilter(mode: .custom, from: oct(10, 18), to: oct(12, 6))
        XCTAssertEqual(filter.interval(now: now, calendar: calendar), oct(10, 0)..<oct(13, 0))
        XCTAssertTrue(passes(filter, clip("A.MP4", created: oct(10, 0, 0, 0))), "Start of the first day")
        XCTAssertTrue(passes(filter, clip("B.MP4", created: oct(12, 23, 59, 59))), "End of the last day")
        XCTAssertFalse(passes(filter, clip("C.MP4", created: oct(9, 23, 59, 59))))
        XCTAssertFalse(passes(filter, clip("D.MP4", created: oct(13, 0, 0, 0))))
    }

    func testCustomRangeOfOneDayAndReversedDates() {
        let single = DateFilter(mode: .custom, from: oct(5, 9), to: oct(5, 9))
        XCTAssertEqual(single.interval(now: now, calendar: calendar), oct(5, 0)..<oct(6, 0))
        let reversed = DateFilter(mode: .custom, from: oct(12), to: oct(10))
        XCTAssertEqual(reversed.interval(now: now, calendar: calendar), oct(10, 0)..<oct(13, 0))
    }

    // MARK: Which date

    func testCreationDateWinsOverModificationDate() {
        let filter = DateFilter(mode: .today)
        // Shot last week, touched today (e.g. the camera rewrote metadata): judged by when it was shot.
        let shotEarlier = clip("A.MP4", created: oct(20), modified: oct(27))
        XCTAssertEqual(DateFilter.date(of: shotEarlier), oct(20))
        XCTAssertFalse(passes(filter, shotEarlier))
        let shotToday = clip("B.MP4", created: oct(27, 9), modified: oct(1))
        XCTAssertTrue(passes(filter, shotToday))
    }

    func testFallsBackToModificationDate() {
        let filter = DateFilter(mode: .today)
        let noCreation = clip("A.MP4", created: nil, modified: oct(27, 8))
        XCTAssertEqual(DateFilter.date(of: noCreation), oct(27, 8))
        XCTAssertTrue(passes(filter, noCreation))
        XCTAssertFalse(passes(filter, clip("B.MP4", created: nil, modified: oct(26, 8))))
    }

    func testFileWithoutAnyDateStaysOnTheCardWhenFiltering() {
        let undated = clip("A.MP4", created: nil, modified: nil)
        XCTAssertNil(DateFilter.date(of: undated))
        XCTAssertFalse(passes(DateFilter(mode: .last7Days), undated))
    }

    // MARK: Sidecars and the selection

    func testSidecarsAndProxiesFollowTheirClip() {
        // C0001 shot today; its XML written yesterday (odd camera clock). GoPro clip from last week with
        // an LRV and THM dated today. A lone MEDIAPRO.XML is judged by its own date.
        let today = clip("PRIVATE/M4ROOT/CLIP/C0001.MP4", created: oct(27, 10))
        let todayXML = clip("PRIVATE/M4ROOT/CLIP/C0001M01.XML", created: oct(26, 10))
        let old = clip("DCIM/100GOPRO/GX010001.MP4", created: oct(20, 10))
        let oldLRV = clip("DCIM/100GOPRO/GL010001.LRV", created: oct(27, 10))
        let oldTHM = clip("DCIM/100GOPRO/GX010001.THM", created: oct(27, 10))
        let lone = clip("PRIVATE/M4ROOT/MEDIAPRO.XML", created: oct(27, 11))
        let files = [today, todayXML, old, oldLRV, oldTHM, lone]

        let excluded = DateFilter(mode: .today).excludedIDs(in: files, now: now, calendar: calendar)
        XCTAssertEqual(excluded, [old.relativePath, oldLRV.relativePath, oldTHM.relativePath])
        XCTAssertTrue(DateFilter.any.excludedIDs(in: files, now: now, calendar: calendar).isEmpty)
    }

    func testSelectionCopiesOnlyFilesInRangeAndCountsTheRest() {
        let today = clip("CLIP/C0001.MP4", created: oct(27, 10), size: 1_000)
        let todayXML = clip("CLIP/C0001M01.XML", created: oct(27, 10), size: 10)
        let old = clip("CLIP/C0002.MP4", created: oct(1), size: 5_000)
        let oldXML = clip("CLIP/C0002M01.XML", created: oct(1), size: 10)
        let oldOffloaded = clip("CLIP/C0003.MP4", created: oct(1))
        let todayOffloaded = clip("CLIP/C0004.MP4", created: oct(27, 9))
        let oldMissing = clip("CLIP/C0005.MP4", created: oct(2))
        let inventory = CardInventory(new: [today, todayXML, old, oldXML], offloaded: [todayOffloaded, oldOffloaded],
                                      missing: [oldMissing])

        func select(_ filter: DateFilter, reoffload: ReoffloadMode = .off, picked: Set<String> = []) -> OffloadSelection {
            OffloadSelection.make(inventory: inventory, categories: Set(MediaCategory.allCases),
                                  reoffload: reoffload, reoffloadIDs: picked,
                                  dateFilter: filter, now: now, calendar: calendar)
        }

        let all = select(.any)
        XCTAssertEqual(all.toCopy.map(\.relativePath), [today, todayXML, old, oldXML].map(\.relativePath))
        XCTAssertEqual(all.outsideDates, 0)
        XCTAssertEqual(all.missingKept, 1)

        let filtered = select(DateFilter(mode: .today))
        XCTAssertEqual(filtered.toCopy.map(\.relativePath), [today.relativePath, todayXML.relativePath])
        XCTAssertEqual(filtered.outsideDates, 2, "The old clip and its sidecar stay on the card")
        XCTAssertEqual(filtered.offloadedKept, 2)
        XCTAssertEqual(filtered.missingKept, 0, "A missing copy from another day isn't offered for re-offload")
        XCTAssertFalse(select(DateFilter(mode: .today), reoffload: .missing).toCopy.contains(oldMissing))

        // Re-offload everything still respects the dates; a single picked file always comes along.
        let everything = select(DateFilter(mode: .today), reoffload: .everything)
        XCTAssertEqual(Set(everything.toCopy.map(\.relativePath)),
                       Set([today, todayXML, todayOffloaded].map(\.relativePath)))
        let picked = select(DateFilter(mode: .today), picked: [oldOffloaded.relativePath])
        XCTAssertTrue(picked.toCopy.contains(oldOffloaded))
    }

    func testPlanSizeAndSessionFollowTheFilter() {
        let today = clip("CLIP/C0001.MP4", created: oct(27, 10), size: 1_000)
        let old = clip("CLIP/C0002.MP4", created: nil, modified: oct(3), size: 5_000)
        let inventory = CardInventory(new: [today, old])
        let selection = OffloadSelection.make(inventory: inventory, categories: Set(MediaCategory.allCases),
                                              reoffload: .off, reoffloadIDs: [],
                                              dateFilter: DateFilter(mode: .custom, from: oct(27), to: oct(27)),
                                              now: now, calendar: calendar)
        let plan = OffloadPlanner.plan(files: selection.toCopy, naming: .standard,
                                       context: NamingContext(project: "Coastline"), existingNames: { _ in [] })
        XCTAssertEqual(plan.map(\.originalName), ["C0001.MP4"], "What's planned is what's copied, verified and recorded")
        XCTAssertEqual(plan.reduce(0) { $0 + $1.size }, 1_000)
    }

    @MainActor
    func testSessionRefreshesWhenTheFilterChanges() {
        let recent = clip("CLIP/C0001.MP4", created: Date().addingTimeInterval(-60))
        let old = clip("CLIP/C0002.MP4", created: Date().addingTimeInterval(-30 * 86_400))
        let card = CardVolume(url: URL(fileURLWithPath: "/Volumes/SD"), name: "SD", uuid: "ID")
        let session = OffloadSession(card: card, inventory: CardInventory(new: [recent, old]))
        XCTAssertEqual(session.newClips.count, 2)
        session.dateFilter = DateFilter(mode: .last7Days)
        XCTAssertEqual(session.newClips, [recent])
        XCTAssertEqual(session.outsideDatesCount, 1)
        XCTAssertEqual(session.newBytes, recent.size)
        session.dateFilter = .any
        XCTAssertEqual(session.newClips.count, 2)
        XCTAssertEqual(session.outsideDatesCount, 0)
    }

    func testReadinessExplainsAnEmptyRange() {
        XCTAssertEqual(OffloadReadiness.blocker(hasCard: true, isScanning: false, newFileCount: 0, outsideDates: 3,
                                                project: "", hasDestination: true, requiredBytes: 0, availableBytes: nil),
                       "Nothing new in the chosen dates — choose Any date to see everything")
    }

    // MARK: Settings

    @MainActor
    func testChoiceIsRememberedAndDefaultsToAnyDate() {
        let suite = "DateFilterTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(AppSettings(defaults: defaults).dateFilter, .any)
        let settings = AppSettings(defaults: defaults)
        settings.dateFilter = DateFilter(mode: .custom, from: oct(10), to: oct(12))
        XCTAssertEqual(AppSettings(defaults: defaults).dateFilter, DateFilter(mode: .custom, from: oct(10), to: oct(12)))
    }
}
