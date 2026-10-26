import XCTest
@testable import Lodge

/// Thumbnail grid and Quick Look: cache keys, which files get pictures, selection and preview order.
final class MediaPreviewTests: XCTestCase {
    private let date = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func key(path: String = "/Volumes/A7S/DCIM/C0001.MP4", size: Int64 = 1_000, modified: Date? = nil,
                     points: CGFloat = 160, scale: CGFloat = 2) -> ThumbnailKey {
        ThumbnailKey(path: path, size: size, modified: modified ?? date, points: points, scale: scale)
    }

    // MARK: Cache key

    func testCacheKeyIsStableForTheSameFile() {
        XCTAssertEqual(key().cacheKey, key().cacheKey)
        XCTAssertEqual(key(), key())
    }

    func testCacheKeyChangesWithPathSizeAndModificationTime() {
        let base = key().cacheKey
        XCTAssertNotEqual(key(path: "/Volumes/A7S/DCIM/C0002.MP4").cacheKey, base)
        XCTAssertNotEqual(key(size: 1_001).cacheKey, base)
        XCTAssertNotEqual(key(modified: date.addingTimeInterval(1)).cacheKey, base)
        let undated = ThumbnailKey(path: "/a.mp4", size: 1, modified: nil, points: 100, scale: 1)
        XCTAssertTrue(undated.cacheKey.contains("|-|"))
    }

    func testCacheKeyIsScaleAware() {
        XCTAssertNotEqual(key(scale: 1).cacheKey, key(scale: 2).cacheKey)
        XCTAssertEqual(key(points: 160, scale: 2).pixels, 320)
        // Same pixel size = same picture.
        XCTAssertEqual(key(points: 80, scale: 2).cacheKey, key(points: 160, scale: 1).cacheKey)
        XCTAssertEqual(key(scale: 0).scale, 1, "a missing scale counts as 1×")
    }

    func testCacheKeyFromClip() {
        let clip = Clip(url: URL(fileURLWithPath: "/Volumes/A7S/C0001.MP4"), relativePath: "C0001.MP4",
                        size: 42, creationDate: nil, modificationDate: date)
        XCTAssertEqual(ThumbnailKey(clip: clip, points: 160, scale: 2),
                       ThumbnailKey(path: "/Volumes/A7S/C0001.MP4", size: 42, modified: date, points: 160, scale: 2))
    }

    // MARK: Supported types

    func testThumbnailsForPhotosAndVideosButNotRawVideoOrSidecars() {
        for name in ["C0001.MP4", "clip.mov", "DSC0001.ARW", "IMG_0001.JPG", "photo.heic"] {
            XCTAssertTrue(MediaPreviewSupport.hasThumbnail(fileName: name), name)
        }
        for name in ["A001.braw", "A001_C002.R3D", "CLIP.MXF", "C0001M01.XML", "DSC0001.xmp", "ZOOM0001.WAV", "NOEXT"] {
            XCTAssertFalse(MediaPreviewSupport.hasThumbnail(fileName: name), name)
        }
    }

    func testPreviewIsUnavailableForCameraRawVideoOnly() {
        for name in ["A001.BRAW", "A001.r3d", "CLIP.mxf", "A.crm"] {
            XCTAssertFalse(MediaPreviewSupport.canPreview(fileName: name), name)
        }
        for name in ["C0001.MP4", "DSC0001.ARW", "C0001M01.XML", "ZOOM0001.WAV"] {
            XCTAssertTrue(MediaPreviewSupport.canPreview(fileName: name), name)
        }
        XCTAssertFalse(MediaPreviewSupport.canPreview(fileName: "README"))
    }

    func testFallbackSymbols() {
        XCTAssertEqual(MediaPreviewSupport.fallbackSymbol(fileName: "C0001M01.XML"), "doc.text")
        XCTAssertEqual(MediaPreviewSupport.fallbackSymbol(fileName: "A001.braw"), "film.stack")
        XCTAssertEqual(MediaPreviewSupport.fallbackSymbol(fileName: "ZOOM0001.WAV"), MediaCategory.audio.symbol)
    }

    // MARK: Preview order

    private let order = ["C1.MP4", "C1M01.XML", "C2.BRAW", "D1.ARW", "C3.MP4"]
    private func canPreview(_ id: String) -> Bool { MediaPreviewSupport.canPreview(fileName: id) }

    func testPreviewFollowsTheShownOrderAndSkipsUnpreviewableFiles() {
        let outcome = PreviewQueue.make(order: order, selection: ["D1.ARW"], focus: "D1.ARW", canPreview: canPreview)
        XCTAssertEqual(outcome, .preview(ids: ["C1.MP4", "C1M01.XML", "D1.ARW", "C3.MP4"], start: 2))
    }

    func testPreviewFollowsTheFilter() {
        // Photos filter: only the photo is shown, so only it is previewed.
        let videos = order.filter { $0.hasSuffix(".MP4") }
        XCTAssertEqual(PreviewQueue.make(order: videos, selection: ["C3.MP4"], focus: "C3.MP4", canPreview: canPreview),
                       .preview(ids: ["C1.MP4", "C3.MP4"], start: 1))
        let reversed = Array(videos.reversed())
        XCTAssertEqual(PreviewQueue.make(order: reversed, selection: [], focus: nil, canPreview: canPreview),
                       .preview(ids: ["C3.MP4", "C1.MP4"], start: 0))
    }

    func testMultipleSelectionLimitsPreviewToTheSelectionInShownOrder() {
        let outcome = PreviewQueue.make(order: order, selection: ["C3.MP4", "C1.MP4", "C2.BRAW"], focus: "C3.MP4",
                                        canPreview: canPreview)
        XCTAssertEqual(outcome, .preview(ids: ["C1.MP4", "C3.MP4"], start: 1))
        // Focus on the BRAW in a multi-selection: preview the others instead of complaining.
        XCTAssertEqual(PreviewQueue.make(order: order, selection: ["C3.MP4", "C2.BRAW"], focus: "C2.BRAW",
                                         canPreview: canPreview),
                       .preview(ids: ["C3.MP4"], start: 0))
    }

    func testUnsupportedFileSaysSo() {
        XCTAssertEqual(PreviewQueue.make(order: order, selection: ["C2.BRAW"], focus: "C2.BRAW", canPreview: canPreview),
                       .unsupported(id: "C2.BRAW"))
        XCTAssertEqual(PreviewQueue.make(order: ["A.BRAW", "B.R3D"], selection: [], focus: nil, canPreview: canPreview),
                       .unsupported(id: "A.BRAW"))
        XCTAssertEqual(PreviewQueue.make(order: [], selection: [], focus: nil, canPreview: canPreview), .nothing)
    }

    func testFocusThatIsNoLongerShownStartsAtTheTop() {
        XCTAssertEqual(PreviewQueue.make(order: ["C1.MP4", "C3.MP4"], selection: ["D1.ARW"], focus: "D1.ARW",
                                         canPreview: canPreview),
                       .preview(ids: ["C1.MP4", "C3.MP4"], start: 0))
    }

    // MARK: Selection

    func testClickToggleAndShiftRange() {
        var selection = MediaSelection()
        selection.click("C1M01.XML", modifier: .none, order: order)
        XCTAssertEqual(selection.selected, ["C1M01.XML"])
        selection.click("C3.MP4", modifier: .extend, order: order)
        XCTAssertEqual(selection.ordered(in: order), ["C1M01.XML", "C2.BRAW", "D1.ARW", "C3.MP4"])
        XCTAssertEqual(selection.focus, "C3.MP4")
        selection.click("C2.BRAW", modifier: .toggle, order: order)
        XCTAssertEqual(selection.ordered(in: order), ["C1M01.XML", "D1.ARW", "C3.MP4"])
        selection.click("C1.MP4", modifier: .toggle, order: order)
        XCTAssertTrue(selection.contains("C1.MP4"))
        XCTAssertEqual(selection.focus, "C1.MP4")
        selection.click("D1.ARW", modifier: .none, order: order)
        XCTAssertEqual(selection.selected, ["D1.ARW"])
        // ⇧-click with nothing to start from acts like a plain click.
        var fresh = MediaSelection()
        fresh.click("C2.BRAW", modifier: .extend, order: order)
        XCTAssertEqual(fresh.selected, ["C2.BRAW"])
    }

    func testArrowKeysMoveInShownOrderAndStopAtTheEnds() {
        var selection = MediaSelection()
        selection.move(by: 1, order: order)
        XCTAssertEqual(selection.selected, ["C1.MP4"])
        selection.move(by: 3, order: order)
        XCTAssertEqual(selection.selected, ["D1.ARW"])
        selection.move(by: 5, order: order)
        XCTAssertEqual(selection.selected, ["C3.MP4"])
        selection.move(by: -10, order: order)
        XCTAssertEqual(selection.selected, ["C1.MP4"])
        var fromEnd = MediaSelection()
        fromEnd.move(by: -1, order: order)
        XCTAssertEqual(fromEnd.selected, ["C3.MP4"])
    }

    func testFollowingQuickLookKeepsAMultiSelection() {
        var selection = MediaSelection()
        selection.click("C1.MP4", modifier: .none, order: order)
        selection.click("C3.MP4", modifier: .toggle, order: order)
        selection.follow("C1.MP4")
        XCTAssertEqual(selection.selected, ["C1.MP4", "C3.MP4"])
        XCTAssertEqual(selection.focus, "C1.MP4")
        selection.follow("D1.ARW")
        XCTAssertEqual(selection.selected, ["D1.ARW"])
    }

    func testPruneDropsFilesTheFilterHides() {
        var selection = MediaSelection()
        selection.click("C1.MP4", modifier: .none, order: order)
        selection.click("D1.ARW", modifier: .toggle, order: order)
        selection.prune(to: ["C1.MP4", "C3.MP4"])
        XCTAssertEqual(selection.selected, ["C1.MP4"])
        XCTAssertEqual(selection.focus, "C1.MP4")
        selection.clear()
        XCTAssertTrue(selection.isEmpty)
    }

    // MARK: Grid tiles

    func testSidecarsFoldIntoTheirClipsTile() {
        let ids = ["C1.MP4", "C1M01.XML", "C2.MP4", "C2M01.XML", "ORPHAN.XML"]
        let primaryOf = ["C1M01.XML": "C1.MP4", "C2M01.XML": "C2.MP4", "ORPHAN.XML": "GONE.MP4"]
        XCTAssertEqual(TileFolding.fold(ids, primaryOf: primaryOf), [
            .init(id: "C1.MP4", sidecars: ["C1M01.XML"]),
            .init(id: "C2.MP4", sidecars: ["C2M01.XML"]),
            .init(id: "ORPHAN.XML", sidecars: []),
        ])
        // "Other" filter: the clips aren't shown, so their sidecars get tiles.
        XCTAssertEqual(TileFolding.fold(["C1M01.XML"], primaryOf: primaryOf).map(\.id), ["C1M01.XML"])
    }

    // MARK: Concurrency limit

    @MainActor
    func testLimiterQueuesBeyondItsLimitAndCanBeCancelled() async {
        let limiter = AsyncLimiter(limit: 1)
        let first = await limiter.acquire()
        XCTAssertTrue(first)
        let waiter = Task { @MainActor in await limiter.acquire() }
        await Task.yield()
        while limiter.waitingCount == 0 { await Task.yield() }
        XCTAssertEqual(limiter.running, 1)
        limiter.release()
        let second = await waiter.value
        XCTAssertTrue(second)
        XCTAssertEqual(limiter.running, 1)

        let cancelled = Task { @MainActor in await limiter.acquire() }
        while limiter.waitingCount == 0 { await Task.yield() }
        limiter.cancelWaiting()
        let gotSlot = await cancelled.value
        XCTAssertFalse(gotSlot)
        limiter.release()
        XCTAssertEqual(limiter.running, 0)
    }

    @MainActor
    func testRaisingTheLimitLetsWaitersIn() async {
        let limiter = AsyncLimiter(limit: 1)
        _ = await limiter.acquire()
        let waiter = Task { @MainActor in await limiter.acquire() }
        while limiter.waitingCount == 0 { await Task.yield() }
        limiter.limit = 2
        let admitted = await waiter.value
        XCTAssertTrue(admitted)
        XCTAssertEqual(limiter.running, 2)
    }

    @MainActor
    func testThrottlingWhileCopying() {
        let provider = ThumbnailProvider()
        XCTAssertFalse(provider.isThrottled)
        provider.isThrottled = true
        XCTAssertTrue(provider.isThrottled)
        XCTAssertLessThan(ThumbnailProvider.maxConcurrentWhileCopying, ThumbnailProvider.maxConcurrent)
        XCTAssertEqual(ThumbnailProvider.maxConcurrent, 4)
    }

    @MainActor
    func testUnsupportedFilesNeverAskQuickLook() async {
        let provider = ThumbnailProvider()
        let clip = Clip(url: URL(fileURLWithPath: "/nonexistent/A001.braw"), relativePath: "A001.braw",
                        size: 1, creationDate: nil, modificationDate: nil)
        let image = await provider.image(for: clip, key: ThumbnailKey(clip: clip, points: 100, scale: 2))
        XCTAssertNil(image)
    }

    // MARK: Settings

    @MainActor
    func testLayoutAndListThumbnailsPersist() throws {
        let suite = "LodgeTests.media.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.mediaLayout, .list)
        XCTAssertFalse(settings.showListThumbnails)
        settings.mediaLayout = .grid
        settings.showListThumbnails = true
        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.mediaLayout, .grid)
        XCTAssertTrue(reloaded.showListThumbnails)
    }
}
