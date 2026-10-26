import XCTest
@testable import SnapDrop

/// Missing copies, Re-offload (missing / everything / one file) and forgetting history.
final class ReoffloadTests: XCTestCase {
    private let identity = "CARD-UUID"
    private let start = Date(timeIntervalSince1970: 1_761_400_000)

    private func clip(_ path: String, size: Int64 = 100, minutesAfter minutes: Double = 0) -> Clip {
        let date = start.addingTimeInterval(minutes * 60)
        return Clip(url: URL(fileURLWithPath: "/Volumes/SD Card/" + path), relativePath: path, size: size,
                    creationDate: date, modificationDate: date)
    }

    private func entry(for clip: Clip, at destination: String, card: String? = nil,
                       at date: Date = Date()) -> LedgerEntry {
        LedgerEntry(sourceKey: clip.ledgerKey(volumeIdentity: card ?? identity), cardName: "SD Card",
                    sourceRelativePath: clip.relativePath, destinationPath: destination,
                    size: clip.size, sha256: "x", offloadedAt: date)
    }

    private func index(_ list: [LedgerEntry]) -> [String: LedgerEntry] {
        Dictionary(list.map { ($0.sourceKey, $0) }, uniquingKeysWith: { $1 })
    }

    /// new.MP4 (never offloaded), kept.MP4 (copy present), gone.MP4 (copy deleted),
    /// shrunk.MP4 (copy has the wrong size), and gone.MP4's sidecar goneM01.XML (copy deleted).
    private func sampleInventory() -> CardInventory {
        let new = clip("CLIP/new.MP4", minutesAfter: 0)
        let kept = clip("CLIP/kept.MP4", minutesAfter: 1)
        let gone = clip("CLIP/gone.MP4", minutesAfter: 2)
        let goneXML = clip("CLIP/goneM01.XML", size: 5, minutesAfter: 2)
        let shrunk = clip("CLIP/shrunk.MP4", minutesAfter: 3)
        let entries = index([entry(for: kept, at: "/Out/kept.mp4"), entry(for: gone, at: "/Out/gone.mp4"),
                             entry(for: goneXML, at: "/Out/goneM01.xml"), entry(for: shrunk, at: "/Out/shrunk.mp4")])
        let disk: [String: Int64] = ["/Out/kept.mp4": 100, "/Out/shrunk.mp4": 40]
        return CardInventory.classify(files: [new, kept, gone, goneXML, shrunk], volumeIdentity: identity,
                                      entries: entries, fileSize: { disk[$0] })
    }

    private func paths(_ clips: [Clip]) -> [String] { clips.map(\.relativePath).sorted() }

    // MARK: Classification

    func testMissingOrResizedCopyIsMissingNotOffloaded() {
        let inventory = sampleInventory()
        XCTAssertEqual(paths(inventory.new), ["CLIP/new.MP4"])
        XCTAssertEqual(paths(inventory.offloaded), ["CLIP/kept.MP4"])
        XCTAssertEqual(paths(inventory.missing), ["CLIP/gone.MP4", "CLIP/goneM01.XML", "CLIP/shrunk.MP4"])
        XCTAssertEqual(inventory.copiesFolder, "/Out")
        XCTAssertEqual(inventory.fileCount, 5)
    }

    func testMissingCopiesAreNotCopiedAutomatically() {
        let selection = OffloadSelection.make(inventory: sampleInventory(), categories: Set(MediaCategory.allCases),
                                              reoffload: .off, reoffloadIDs: [])
        XCTAssertEqual(paths(selection.toCopy), ["CLIP/new.MP4"])
        XCTAssertEqual(selection.missingKept, 3)
        XCTAssertEqual(selection.offloadedKept, 1)
        XCTAssertTrue(selection.reoffloading.isEmpty)
    }

    func testMissingCopiesMeanNotReadyToFormat() {
        let inventory = sampleInventory()
        var allOffloaded = inventory
        allOffloaded.new = []
        let readiness = FormatReadiness(inventory: allOffloaded)
        XCTAssertFalse(readiness.isReady)
        XCTAssertEqual(readiness.missingCopies, 3)
        XCTAssertEqual(readiness.pendingText, "3 copies missing at the destination")
    }

    func testReadyAgainAfterMissingCopiesAreReoffloaded() {
        let gone = clip("CLIP/gone.MP4")
        let old = entry(for: gone, at: "/Out/gone.mp4", at: start)
        let fresh = entry(for: gone, at: "/Out/gone_2.mp4", at: start.addingTimeInterval(60))
        // The newest entry wins, and its copy is there.
        let inventory = CardInventory.classify(files: [gone], volumeIdentity: identity,
                                               entries: index([old, fresh]),
                                               fileSize: { $0 == "/Out/gone_2.mp4" ? 100 : nil })
        XCTAssertTrue(FormatReadiness(inventory: inventory).isReady)
    }

    // MARK: Re-offload modes

    func testReoffloadMissingCopies() {
        let selection = OffloadSelection.make(inventory: sampleInventory(), categories: Set(MediaCategory.allCases),
                                              reoffload: .missing, reoffloadIDs: [])
        XCTAssertEqual(paths(selection.toCopy), ["CLIP/gone.MP4", "CLIP/goneM01.XML", "CLIP/new.MP4", "CLIP/shrunk.MP4"])
        XCTAssertEqual(selection.reoffloading, ["CLIP/gone.MP4", "CLIP/goneM01.XML", "CLIP/shrunk.MP4"])
        XCTAssertEqual(selection.missingKept, 0)
        XCTAssertEqual(selection.offloadedKept, 1)
    }

    func testReoffloadEverything() {
        let selection = OffloadSelection.make(inventory: sampleInventory(), categories: Set(MediaCategory.allCases),
                                              reoffload: .everything, reoffloadIDs: [])
        XCTAssertEqual(selection.toCopy.count, 5)
        XCTAssertEqual(selection.reoffloading.count, 4)
        XCTAssertEqual(selection.missingKept + selection.offloadedKept, 0)
    }

    func testReoffloadOneFileBringsItsSidecar() {
        let selection = OffloadSelection.make(inventory: sampleInventory(), categories: Set(MediaCategory.allCases),
                                              reoffload: .off, reoffloadIDs: ["CLIP/gone.MP4"])
        XCTAssertEqual(paths(selection.toCopy), ["CLIP/gone.MP4", "CLIP/goneM01.XML", "CLIP/new.MP4"])
        XCTAssertEqual(selection.missingKept, 1)   // shrunk.MP4
    }

    func testReoffloadRespectsTurnedOffTypes() {
        let selection = OffloadSelection.make(inventory: sampleInventory(), categories: [.video],
                                              reoffload: .everything, reoffloadIDs: [])
        XCTAssertFalse(selection.toCopy.contains { $0.category == .other })
        XCTAssertEqual(selection.toCopy.count, 4)
    }

    func testReoffloadNeverReusesAnExistingName() {
        // kept.MP4 was offloaded as ..._0001.mp4, which is still there: the new copy gets 0002.
        let kept = clip("CLIP/kept.MP4")
        let date = Renamer.dateString(for: kept.captureDate)
        let existing = ["\(date)/Trip": ["\(date)_Trip_0001.mp4"]]
        let plan = OffloadPlanner.plan(files: [kept], naming: .standard, context: NamingContext(project: "Trip"),
                                       existingNames: { existing[$0] ?? [] })
        XCTAssertEqual(plan.map(\.fileName), ["\(date)_Trip_0002.mp4"])
    }

    @MainActor
    func testSessionCountsAndSingleFileToggle() {
        let card = CardVolume(url: URL(fileURLWithPath: "/Volumes/SD Card"), name: "SD Card", uuid: identity)
        let session = OffloadSession(card: card, inventory: sampleInventory())
        XCTAssertEqual(session.newClips.count, 1)
        XCTAssertEqual(session.missingCopyCount, 3)
        XCTAssertEqual(session.alreadyOffloadedCount, 1)
        XCTAssertEqual(session.offloadedStatus(of: clip("CLIP/gone.MP4")), true)
        XCTAssertEqual(session.offloadedStatus(of: clip("CLIP/kept.MP4")), false)
        XCTAssertNil(session.offloadedStatus(of: clip("CLIP/new.MP4")))

        session.toggleReoffload(clip("CLIP/kept.MP4"))
        XCTAssertEqual(session.newClips.count, 2)
        XCTAssertEqual(session.reoffloadingIDs, ["CLIP/kept.MP4"])
        XCTAssertEqual(session.alreadyOffloadedCount, 0)
        session.toggleReoffload(clip("CLIP/kept.MP4"))
        XCTAssertEqual(session.newClips.count, 1)

        session.reoffloadMode = .missing
        XCTAssertEqual(session.missingCopyCount, 0)
        XCTAssertEqual(session.missingCopiesInView, 3)
    }

    func testBlockerPointsAtReoffloadWhenOnlyCopiesAreMissing() {
        func blocker(new: Int, missing: Int) -> String? {
            OffloadReadiness.blocker(hasCard: true, isScanning: false, newFileCount: new, missingCopies: missing,
                                     project: "P", hasDestination: true, requiredBytes: 0, availableBytes: nil)
        }
        XCTAssertEqual(blocker(new: 0, missing: 2), "2 copies are missing at the destination — choose Re-offload")
        XCTAssertEqual(blocker(new: 0, missing: 1), "1 copy is missing at the destination — choose Re-offload")
        XCTAssertEqual(blocker(new: 0, missing: 0), "Everything on this card is already offloaded")
        XCTAssertNil(blocker(new: 1, missing: 2))
    }

    func testConfirmationWording() {
        let everything = ReoffloadAlert.everythingText(cardName: "A7S", fileCount: 12)
        XCTAssertEqual(everything.title, "Re-offload everything on “A7S”?")
        XCTAssertTrue(everything.message.contains("All 12 files"))
        XCTAssertTrue(everything.message.contains("never overwritten"))
        let forget = ReoffloadAlert.forgetText(cardName: "A7S", entryCount: 1)
        XCTAssertTrue(forget.message.contains("the 1 file"))
        XCTAssertTrue(forget.message.contains("aren’t touched"))
    }

    // MARK: Forgetting

    @MainActor
    private func tempLedger() -> Ledger {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("snapdrop-reoffload-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return Ledger(fileURL: url)
    }

    @MainActor
    func testForgetCardRemovesOnlyThatCard() {
        let ledger = tempLedger()
        let a = clip("CLIP/a.MP4"), b = clip("CLIP/b.MP4")
        ledger.add(entry(for: a, at: "/Out/a.mp4"))
        ledger.add(entry(for: b, at: "/Out/b.mp4"))
        ledger.add(entry(for: a, at: "/Out/other-a.mp4", card: "OTHER-CARD"))
        // A card whose identity starts with this one's must not be touched.
        ledger.add(entry(for: a, at: "/Out/longer-a.mp4", card: identity + "-2"))
        XCTAssertEqual(ledger.entryCount(forVolume: identity), 2)

        XCTAssertEqual(ledger.forget(volumeIdentity: identity), 2)
        XCTAssertEqual(ledger.entries.count, 2)
        XCTAssertFalse(ledger.contains(key: a.ledgerKey(volumeIdentity: identity)))
        XCTAssertTrue(ledger.contains(key: a.ledgerKey(volumeIdentity: "OTHER-CARD")))

        // Saved to disk right away.
        let reloaded = Ledger(fileURL: ledger.fileURL)
        XCTAssertEqual(reloaded.entries.map(\.destinationPath).sorted(), ["/Out/longer-a.mp4", "/Out/other-a.mp4"])
    }

    @MainActor
    func testForgetOneCopyKeepsTheOlderOne() {
        let ledger = tempLedger()
        let a = clip("CLIP/a.MP4")
        let first = entry(for: a, at: "/Out/a.mp4", at: start)
        let second = entry(for: a, at: "/Out/a_2.mp4", at: start.addingTimeInterval(60))
        ledger.add(first)
        ledger.add(second)
        XCTAssertNotEqual(first.id, second.id)   // each copy is its own row in Recent Offloads

        ledger.forget(second)
        XCTAssertEqual(ledger.entries, [first])
        XCTAssertEqual(ledger.entriesByKey()[a.ledgerKey(volumeIdentity: identity)]?.destinationPath, "/Out/a.mp4")
        XCTAssertTrue(ledger.contains(key: a.ledgerKey(volumeIdentity: identity)))

        ledger.forget(first)
        XCTAssertTrue(ledger.entries.isEmpty)
        XCTAssertFalse(ledger.contains(key: a.ledgerKey(volumeIdentity: identity)))
    }
}
