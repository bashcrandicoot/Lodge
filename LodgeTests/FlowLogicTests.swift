import XCTest
import AppKit
@testable import Lodge

final class FlowLogicTests: XCTestCase {
    private func clip(_ name: String, minutesAfter minutes: Double, day: Int = 25, size: Int64 = 100) -> Clip {
        var components = DateComponents()
        components.year = 2026; components.month = 10; components.day = day; components.hour = 10
        let date = Calendar.current.date(from: components)!.addingTimeInterval(minutes * 60)
        return Clip(url: URL(fileURLWithPath: "/Volumes/SD/DCIM/\(name)"), relativePath: "DCIM/\(name)",
                    size: size, creationDate: date, modificationDate: date)
    }

    // MARK: Name preview (planner)

    private func preview(_ clips: [Clip], project: String, existing: [String: [String]] = [:]) -> [PlannedFile] {
        OffloadPlanner.plan(files: clips, naming: .standard, context: NamingContext(project: project),
                            existingNames: { existing[$0] ?? [] })
    }

    func testPreviewNumbersInCopyOrder() {
        let clips = [clip("C0002.MOV", minutesAfter: 5), clip("C0001.MP4", minutesAfter: 0)]
        let items = preview(clips, project: "BeachShoot")
        XCTAssertEqual(items.map(\.originalName), ["C0001.MP4", "C0002.MOV"])
        XCTAssertEqual(items.map(\.fileName), ["2026-10-25_BeachShoot_0001.mp4", "2026-10-25_BeachShoot_0002.mov"])
        XCTAssertEqual(items.map(\.folder), ["2026-10-25/BeachShoot", "2026-10-25/BeachShoot"])
    }

    func testPreviewContinuesAfterExistingAndSplitsByDate() {
        let clips = [clip("A.MP4", minutesAfter: 0, day: 25), clip("B.MP4", minutesAfter: 0, day: 26)]
        let items = preview(clips, project: "Trip", existing: ["2026-10-25/Trip": ["2026-10-25_Trip_0009.mov"]])
        XCTAssertEqual(items.map(\.fileName), ["2026-10-25_Trip_0010.mp4", "2026-10-26_Trip_0001.mp4"])
        XCTAssertEqual(PlanLayout.folders(items), ["2026-10-25/Trip", "2026-10-26/Trip"])
    }

    func testPreviewMatchesRealOffloadOrder() {
        let clips = [clip("Z.MP4", minutesAfter: 0), clip("A.MP4", minutesAfter: 0), clip("M.MP4", minutesAfter: -3)]
        let previewOrder = preview(clips, project: "X").map(\.originalName)
        XCTAssertEqual(previewOrder, Offloader.order(clips).map { $0.url.lastPathComponent })
        XCTAssertEqual(previewOrder, ["M.MP4", "A.MP4", "Z.MP4"])
    }

    func testDiskListerReadsDestination() throws {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("lodge-preview-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: destination) }
        let clips = [clip("A.MP4", minutesAfter: 0)]
        let date = Renamer.dateString(for: clips[0].captureDate)
        let folder = destination.appendingPathComponent("\(date)/Trip")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: folder.appendingPathComponent("\(date)_Trip_0004.mp4").path, contents: Data())
        let onDisk = OffloadPlanner.plan(files: clips, naming: .standard, context: NamingContext(project: "Trip"),
                                         existingNames: OffloadPlanner.diskLister(root: destination))
        XCTAssertEqual(onDisk.map(\.fileName), ["\(date)_Trip_0005.mp4"])
        let noDestination = OffloadPlanner.plan(files: clips, naming: .standard, context: NamingContext(project: "Trip"),
                                                existingNames: OffloadPlanner.diskLister(root: nil))
        XCTAssertEqual(noDestination.map(\.fileName), ["\(date)_Trip_0001.mp4"])
    }

    // MARK: Readiness

    func testBlockerReasons() {
        func blocker(card: Bool = true, scanning: Bool = false, files: Int = 3, valid: Bool = true,
                     needs: NamingNeeds = NamingNeeds(project: true), project: String = "Doc",
                     camera: Bool = false, destination: Bool = true,
                     required: Int64 = 10, available: Int64? = 100) -> String? {
            OffloadReadiness.blocker(hasCard: card, isScanning: scanning, newFileCount: files, namingIsValid: valid,
                                     needs: needs, project: project, hasCamera: camera,
                                     hasDestination: destination, requiredBytes: required, availableBytes: available)
        }
        XCTAssertNil(blocker())
        XCTAssertNil(blocker(available: nil))
        XCTAssertEqual(blocker(card: false), "Insert a card to begin")
        XCTAssertEqual(blocker(scanning: true), "Scanning card…")
        XCTAssertEqual(blocker(files: 0), "Everything on this card is already offloaded")
        XCTAssertEqual(blocker(valid: false), "Fix the naming template in Settings")
        XCTAssertEqual(blocker(project: ""), "Enter a project name")
        XCTAssertEqual(blocker(destination: false), "Choose a destination folder")
        XCTAssertTrue(blocker(required: 500, available: 100)?.hasPrefix("Not enough space") == true)
        // Fields are only required when the templates use them.
        XCTAssertNil(blocker(needs: NamingNeeds(), project: ""))
        XCTAssertEqual(blocker(needs: NamingNeeds(project: true, camera: true), project: ""), "Enter a project name")
        XCTAssertEqual(blocker(needs: NamingNeeds(camera: true), project: ""), "Choose a camera")
        XCTAssertNil(blocker(needs: NamingNeeds(camera: true), project: "", camera: true))
    }

    func testNamingNeedsFollowTemplates() {
        XCTAssertEqual(NamingNeeds(.standard), NamingNeeds(project: true))
        XCTAssertEqual(NamingNeeds(NamingTemplates(folder: "{project}/{date}/{camera}", file: "{date}_{project}_{camera}_{seq}")),
                       NamingNeeds(project: true, camera: true))
        XCTAssertEqual(NamingNeeds(NamingTemplates(folder: "", file: "{original}")), NamingNeeds())
        XCTAssertEqual(NamingNeeds(nil), NamingNeeds(project: true), "Invalid templates fall back to the default")
    }

    // MARK: Formatting

    func testFileCountAndButtonTitle() {
        XCTAssertEqual(OffloadFormatting.fileCount(1), "1 File")
        XCTAssertEqual(OffloadFormatting.fileCount(12), "12 Files")
        XCTAssertEqual(OffloadFormatting.offloadButtonTitle(fileCount: 0), "Offload Files")
        XCTAssertEqual(OffloadFormatting.offloadButtonTitle(fileCount: 1), "Offload 1 File")
        XCTAssertEqual(OffloadFormatting.offloadButtonTitle(fileCount: 18), "Offload 18 Files")
    }

    func testCardDetail() {
        XCTAssertEqual(OffloadFormatting.cardDetail(newFiles: 54, copied: nil, ignored: 5), "54 new files · 5 ignored")
        XCTAssertEqual(OffloadFormatting.cardDetail(newFiles: 1, copied: nil, ignored: 0), "1 new file")
        XCTAssertEqual(OffloadFormatting.cardDetail(newFiles: 0, copied: nil, ignored: 0), "No new files")
        XCTAssertEqual(OffloadFormatting.cardDetail(newFiles: 57, copied: 57, ignored: 5), "57 copied · 5 ignored",
                       "A finished card says what was copied, not how many files are new")
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

    func testSuccessFeedbackOnlyAfterCleanOffload() {
        let clean = OffloadSummary(copied: 5, skipped: 2, failed: 0)
        XCTAssertTrue(OffloadFeedback.isCleanSuccess(clean))
        XCTAssertTrue(OffloadFeedback.shouldPlaySuccessSound(clean, enabled: true))
        XCTAssertFalse(OffloadFeedback.shouldPlaySuccessSound(clean, enabled: false))
        XCTAssertFalse(OffloadFeedback.shouldPlaySuccessSound(OffloadSummary(copied: 4, failed: 1), enabled: true))
        XCTAssertFalse(OffloadFeedback.shouldPlaySuccessSound(OffloadSummary(copied: 2, cancelled: true), enabled: true))
        XCTAssertFalse(OffloadFeedback.shouldPlaySuccessSound(OffloadSummary(copied: 0), enabled: true))
        XCTAssertNotNil(NSSound(named: "Glass"), "The system sound used on success exists")
    }
}
