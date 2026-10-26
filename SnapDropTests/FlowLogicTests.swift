import XCTest
@testable import SnapDrop

final class FlowLogicTests: XCTestCase {
    private func clip(_ name: String, minutesAfter minutes: Double, day: Int = 25, size: Int64 = 100) -> Clip {
        var components = DateComponents()
        components.year = 2026; components.month = 10; components.day = day; components.hour = 10
        let date = Calendar.current.date(from: components)!.addingTimeInterval(minutes * 60)
        return Clip(url: URL(fileURLWithPath: "/Volumes/SD/DCIM/\(name)"), relativePath: "DCIM/\(name)",
                    size: size, creationDate: date, modificationDate: date)
    }

    // MARK: Name preview

    func testPreviewNumbersInShootOrder() {
        let clips = [clip("C0002.MOV", minutesAfter: 5), clip("C0001.MP4", minutesAfter: 0)]
        let items = NamePreview.preview(clips: clips, shootName: "BeachShoot")
        XCTAssertEqual(items.map(\.originalName), ["C0001.MP4", "C0002.MOV"])
        XCTAssertEqual(items.map(\.newName), ["2026-10-25_BeachShoot_0001.mp4", "2026-10-25_BeachShoot_0002.mov"])
        XCTAssertEqual(items.map(\.folder), ["2026-10-25/BeachShoot", "2026-10-25/BeachShoot"])
    }

    func testPreviewContinuesAfterExistingAndSplitsByDate() {
        let clips = [clip("A.MP4", minutesAfter: 0, day: 25), clip("B.MP4", minutesAfter: 0, day: 26)]
        let items = NamePreview.preview(clips: clips, shootName: "Trip", highestExisting: ["2026-10-25/Trip": 9])
        XCTAssertEqual(items.map(\.newName), ["2026-10-25_Trip_0010.mp4", "2026-10-26_Trip_0001.mp4"])
        XCTAssertEqual(NamePreview.folders(for: items), ["2026-10-25/Trip", "2026-10-26/Trip"])
    }

    func testPreviewMatchesRealOffloadOrder() {
        let clips = [clip("Z.MP4", minutesAfter: 0), clip("A.MP4", minutesAfter: 0), clip("M.MP4", minutesAfter: -3)]
        let previewOrder = NamePreview.preview(clips: clips, shootName: "X").map(\.originalName)
        XCTAssertEqual(previewOrder, Offloader.order(clips).map { $0.url.lastPathComponent })
        XCTAssertEqual(previewOrder, ["M.MP4", "A.MP4", "Z.MP4"])
    }

    func testHighestExistingReadsDestination() throws {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("snapdrop-preview-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: destination) }
        let clips = [clip("A.MP4", minutesAfter: 0)]
        let date = Renamer.dateString(for: clips[0].captureDate)
        let folder = Renamer.folderURL(destination: destination, dateString: date, shootName: "Trip")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: folder.appendingPathComponent("\(date)_Trip_0004.mp4").path, contents: Data())
        XCTAssertEqual(NamePreview.highestExisting(destination: destination, clips: clips, shootName: "Trip"), ["\(date)/Trip": 4])
        XCTAssertEqual(NamePreview.highestExisting(destination: nil, clips: clips, shootName: "Trip"), [:])
    }

    // MARK: Readiness

    func testBlockerReasons() {
        func blocker(card: Bool = true, scanning: Bool = false, clips: Int = 3, name: String = "Shoot",
                     destination: Bool = true, required: Int64 = 10, available: Int64? = 100) -> String? {
            OffloadReadiness.blocker(hasCard: card, isScanning: scanning, newClipCount: clips, shootName: name,
                                     hasDestination: destination, requiredBytes: required, availableBytes: available)
        }
        XCTAssertNil(blocker())
        XCTAssertNil(blocker(available: nil))
        XCTAssertEqual(blocker(card: false), "Insert a card to begin")
        XCTAssertEqual(blocker(scanning: true), "Scanning card…")
        XCTAssertEqual(blocker(clips: 0), "All clips on this card are already offloaded")
        XCTAssertEqual(blocker(name: ""), "Enter a shoot name")
        XCTAssertEqual(blocker(destination: false), "Choose a destination folder")
        XCTAssertTrue(blocker(required: 500, available: 100)?.hasPrefix("Not enough space") == true)
    }

    // MARK: Formatting

    func testClipCountAndButtonTitle() {
        XCTAssertEqual(OffloadFormatting.clipCount(1), "1 Clip")
        XCTAssertEqual(OffloadFormatting.clipCount(12), "12 Clips")
        XCTAssertEqual(OffloadFormatting.offloadButtonTitle(clipCount: 0), "Offload Clips")
        XCTAssertEqual(OffloadFormatting.offloadButtonTitle(clipCount: 1), "Offload 1 Clip")
        XCTAssertEqual(OffloadFormatting.offloadButtonTitle(clipCount: 18), "Offload 18 Clips")
    }

    func testByteFormatting() {
        let expected = ByteCountFormatter.string(fromByteCount: 1_500_000_000, countStyle: .file)
        XCTAssertEqual(OffloadFormatting.bytes(1_500_000_000), expected)
        XCTAssertEqual(OffloadFormatting.bytesProgress(done: 1_500_000_000, total: 1_500_000_000), "\(expected) of \(expected)")
    }

    func testEstimatedSecondsRemaining() {
        XCTAssertNil(OffloadFormatting.estimatedSecondsRemaining(bytesDone: 0, bytesTotal: 100, elapsed: 10))
        XCTAssertNil(OffloadFormatting.estimatedSecondsRemaining(bytesDone: 50, bytesTotal: 100, elapsed: 1))
        XCTAssertNil(OffloadFormatting.estimatedSecondsRemaining(bytesDone: 0, bytesTotal: 0, elapsed: 10))
        XCTAssertEqual(OffloadFormatting.estimatedSecondsRemaining(bytesDone: 100, bytesTotal: 100, elapsed: 10), 0)
        XCTAssertEqual(OffloadFormatting.estimatedSecondsRemaining(bytesDone: 25, bytesTotal: 100, elapsed: 10)!, 30, accuracy: 0.001)
    }

    func testEtaText() {
        XCTAssertEqual(OffloadFormatting.etaText(nil), "Estimating time…")
        XCTAssertEqual(OffloadFormatting.etaText(0), "Almost done")
        XCTAssertEqual(OffloadFormatting.etaText(42), "Less than a minute left")
        XCTAssertEqual(OffloadFormatting.etaText(61), "About 2 min left")
        XCTAssertEqual(OffloadFormatting.etaText(600), "About 10 min left")
        XCTAssertEqual(OffloadFormatting.etaText(3600), "About 1 hr left")
        XCTAssertEqual(OffloadFormatting.etaText(3600 + 25 * 60), "About 1 hr 25 min left")
    }

    func testSummaryLine() {
        XCTAssertEqual(OffloadFormatting.summaryLine(OffloadSummary(copied: 3, skipped: 1, failed: 0)),
                       "3 copied · 1 skipped · 0 failed")
    }
}
