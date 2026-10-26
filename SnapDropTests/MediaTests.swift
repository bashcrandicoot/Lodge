import XCTest
@testable import SnapDrop

final class MediaTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("snapdrop-media-\(UUID().uuidString)")
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

    // MARK: Categories

    func testCategoryClassification() {
        for ext in ["mp4", "mov", "mxf", "braw", "r3d", "crm", "mts", "m2ts", "avi", "mkv", "insv", "lrv", "360"] {
            XCTAssertEqual(MediaCategory.classify(fileName: "A." + ext), .video, ext)
            XCTAssertEqual(MediaCategory.classify(fileName: "A." + ext.uppercased()), .video, ext)
        }
        for ext in ["jpg", "jpeg", "heic", "heif", "png", "tif", "tiff", "dng", "arw", "cr2", "cr3",
                    "nef", "raf", "orf", "rw2", "srw", "pef", "gpr", "insp"] {
            XCTAssertEqual(MediaCategory.classify(fileName: "A." + ext.uppercased()), .photo, ext)
        }
        for ext in ["wav", "mp3", "aac", "m4a", "bwf"] {
            XCTAssertEqual(MediaCategory.classify(fileName: "A." + ext), .audio, ext)
        }
        for name in ["C0001M01.XML", "MEDIAPRO.XML", "README", "clip.lrf", "archive.tar.gz", "STATUS.BIN"] {
            XCTAssertEqual(MediaCategory.classify(fileName: name), .other, name)
        }
        XCTAssertEqual(MediaCategory.classify(fileName: "Mixed.MoV"), .video)
        XCTAssertEqual(MediaCategory.video.tokenValue, "Video")
        XCTAssertEqual(MediaCategory.other.tokenValue, "Other")
        XCTAssertEqual(MediaCategory.photo.countText(120), "120 photo")
        XCTAssertEqual(MediaCategory.allCases.map(\.symbol), ["film", "photo", "waveform", "doc"])
    }

    func testJunkNames() {
        for name in [".DS_Store", "._C0001.MP4", ".Spotlight-V100", ".fseventsd", ".Trashes", ".TemporaryItems",
                     "System Volume Information", "$RECYCLE.BIN", "Thumbs.db", ".hidden.mp4"] {
            XCTAssertTrue(ClipScanner.isJunk(name), name)
        }
        for name in ["C0001.MP4", "DCIM", "PRIVATE", "MEDIAPRO.XML", "empty.dat"] {
            XCTAssertFalse(ClipScanner.isJunk(name), name)
        }
    }

    // MARK: Sidecars

    func testSidecarMatchingExactStemAndSonySuffix() {
        let files = [
            file("PRIVATE/M4ROOT/CLIP/C0001.MP4"),
            file("PRIVATE/M4ROOT/CLIP/C0001M01.XML"),
            file("PRIVATE/M4ROOT/CLIP/c0002.mp4", minutesAfter: 1),
            file("PRIVATE/M4ROOT/CLIP/C0002M01.xml", minutesAfter: 1),
            file("DCIM/100/GX010001.MP4", minutesAfter: 2),
            file("DCIM/100/GX010001.LRF", minutesAfter: 2),
            file("DCIM/100/GX010001.WAV", minutesAfter: 2),
            file("DCIM/100/DSC00001.ARW", minutesAfter: 3),
            file("DCIM/100/DSC00001.XMP", minutesAfter: 3),
            file("OTHER/C0001.XML"),                  // different folder: not a sidecar
            file("PRIVATE/M4ROOT/CLIP/C0001X01.XML"), // not Sony's M suffix
            file("PRIVATE/M4ROOT/MEDIAPRO.XML"),
        ]
        let result = SidecarMatcher.match(Offloader.order(files))
        XCTAssertEqual(result.primary["PRIVATE/M4ROOT/CLIP/C0001M01.XML"], "PRIVATE/M4ROOT/CLIP/C0001.MP4")
        XCTAssertEqual(result.primary["PRIVATE/M4ROOT/CLIP/C0002M01.xml"], "PRIVATE/M4ROOT/CLIP/c0002.mp4")
        XCTAssertEqual(result.primary["DCIM/100/GX010001.LRF"], "DCIM/100/GX010001.MP4")
        XCTAssertEqual(result.primary["DCIM/100/GX010001.WAV"], "DCIM/100/GX010001.MP4")
        XCTAssertEqual(result.primary["DCIM/100/DSC00001.XMP"], "DCIM/100/DSC00001.ARW")
        XCTAssertNil(result.primary["OTHER/C0001.XML"])
        XCTAssertNil(result.primary["PRIVATE/M4ROOT/CLIP/C0001X01.XML"])
        XCTAssertNil(result.primary["PRIVATE/M4ROOT/MEDIAPRO.XML"])
        XCTAssertEqual(result.byPrimary["PRIVATE/M4ROOT/CLIP/C0001.MP4"]?.map(\.suffix), ["M01"])
        XCTAssertEqual(result.byPrimary["DCIM/100/GX010001.MP4"]?.map(\.suffix), ["", ""])
        XCTAssertEqual(SidecarMatcher.sonySuffix(of: "C0001M01"), "M01")
        XCTAssertNil(SidecarMatcher.sonySuffix(of: "M01"))
        XCTAssertNil(SidecarMatcher.sonySuffix(of: "C0001"))
    }

    func testSidecarsShareNameAndDoNotUseSequenceNumbers() {
        let files = [
            file("CLIP/C0001.MP4"), file("CLIP/C0001M01.XML"),
            file("CLIP/C0002.MP4", minutesAfter: 1), file("CLIP/C0002M01.XML", minutesAfter: 1),
            file("CLIP/C0002.WAV", minutesAfter: 1),
            file("CLIP/MEDIAPRO.XML", minutesAfter: 5),   // no partner: gets its own number
            file("CLIP/C0003.MP4", minutesAfter: 6),
        ]
        let plan = OffloadPlanner.plan(files: files, naming: .standard, context: NamingContext(project: "S"),
                                       existingNames: { _ in [] })
        XCTAssertEqual(plan.map(\.fileName), [
            "2026-10-25_S_0001.mp4", "2026-10-25_S_0001M01.xml",
            "2026-10-25_S_0002.mp4", "2026-10-25_S_0002.wav", "2026-10-25_S_0002M01.xml",
            "2026-10-25_S_0003.xml",
            "2026-10-25_S_0004.mp4",
        ])
        XCTAssertEqual(plan.map(\.sidecarOf), [nil, "C0001.MP4", nil, "C0002.MP4", "C0002.MP4", nil, nil])
        XCTAssertTrue(plan.allSatisfy { $0.folder == "2026-10-25/S" })
    }

    func testSidecarFollowsTypeFolderOfItsClipAndAvoidsCollisions() {
        let naming = NamingTemplates(folder: "{type}", file: "{original}")!
        let files = [file("CLIP/C0001.MP4"), file("CLIP/C0001M01.XML")]
        let plan = OffloadPlanner.plan(files: files, naming: naming, context: NamingContext(),
                                       existingNames: { $0 == "Video" ? ["C0001M01.xml"] : [] })
        XCTAssertEqual(plan.map(\.relativePath), ["Video/C0001.mp4", "Video/C0001M01_2.xml"])
    }

    // MARK: Session

    @MainActor
    func testSessionFiltersCategoriesAndSkipsKnownFilesOfAnyType() {
        let card = CardVolume(url: URL(fileURLWithPath: "/Volumes/CARD"), name: "CARD", uuid: "U")
        let files = [file("A/C0001.MP4"), file("A/C0001M01.XML"), file("B/DSC1.JPG"), file("C/Z.WAV"), file("C/notes.txt")]
        let known: Set<String> = [files[1].ledgerKey(volumeIdentity: card.identity)]
        let session = OffloadSession(card: card, clips: files, knownKeys: known)
        XCTAssertEqual(session.newClips.count, 4)
        XCTAssertEqual(session.alreadyOffloadedCount, 1)
        XCTAssertEqual(session.categoryCounts, [.video: 1, .photo: 1, .audio: 1, .other: 1])

        session.includedCategories = [.video, .photo]
        XCTAssertEqual(session.newClips.map(\.relativePath), ["A/C0001.MP4", "B/DSC1.JPG"])
        XCTAssertEqual(session.alreadyOffloadedCount, 0, "The known XML is an 'other' file, now excluded")
    }

    @MainActor
    func testCategorySettingsPersist() throws {
        let suite = "SnapDropTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.includedCategories, Set(MediaCategory.allCases))
        XCTAssertTrue(settings.playSuccessSound)
        settings.setCategory(.other, included: false)
        settings.playSuccessSound = false
        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.includedCategories, [.video, .photo, .audio])
        XCTAssertFalse(reloaded.playSuccessSound)
    }

    // MARK: End to end

    private func write(_ path: String, _ contents: String, card: URL, minutesAfter: Double = 0) throws {
        let url = card.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
        let date = Date(timeIntervalSince1970: 1_761_400_000 + minutesAfter * 60)
        try FileManager.default.setAttributes([.creationDate: date, .modificationDate: date], ofItemAtPath: url.path)
    }

    func testFakeCardWithMixedMediaAndSystemJunk() async throws {
        let card = root.appendingPathComponent("CARD")
        // Real files.
        try write("PRIVATE/M4ROOT/CLIP/C0001.MP4", String(repeating: "v", count: 2_000_000), card: card)
        try write("PRIVATE/M4ROOT/CLIP/C0001M01.XML", "<xml/>", card: card)
        try write("PRIVATE/M4ROOT/CLIP/C0002.MP4", "video two", card: card, minutesAfter: 2)
        try write("PRIVATE/M4ROOT/CLIP/C0002M01.XML", "<xml two/>", card: card, minutesAfter: 2)
        try write("DCIM/100MSDCF/DSC00001.ARW", "raw", card: card, minutesAfter: 1)
        try write("DCIM/100MSDCF/DSC00001.JPG", "jpeg", card: card, minutesAfter: 1)
        try write("AUDIO/ZOOM0001.WAV", "wave", card: card, minutesAfter: 3)
        try write("PRIVATE/M4ROOT/MEDIAPRO.XML", "<db/>", card: card, minutesAfter: 4)
        try write("MISC/empty.dat", "", card: card, minutesAfter: 5)
        // System junk that must never be copied.
        try write(".DS_Store", "junk", card: card)
        try write("PRIVATE/M4ROOT/CLIP/._C0001.MP4", "junk", card: card)
        try write(".Spotlight-V100/Store-V2/store.db", "junk", card: card)
        try write(".fseventsd/0000001", "junk", card: card)
        try write(".Trashes/501/deleted.mp4", "junk", card: card)
        try write(".TemporaryItems/folders.501/x.mov", "junk", card: card)
        try write("System Volume Information/IndexerVolumeGuid", "junk", card: card)
        try write("$RECYCLE.BIN/S-1-5/old.mp4", "junk", card: card)

        let files = ClipScanner.scan(volumeURL: card)
        XCTAssertEqual(files.map(\.relativePath), [
            "AUDIO/ZOOM0001.WAV",
            "DCIM/100MSDCF/DSC00001.ARW",
            "DCIM/100MSDCF/DSC00001.JPG",
            "MISC/empty.dat",
            "PRIVATE/M4ROOT/CLIP/C0001.MP4",
            "PRIVATE/M4ROOT/CLIP/C0001M01.XML",
            "PRIVATE/M4ROOT/CLIP/C0002.MP4",
            "PRIVATE/M4ROOT/CLIP/C0002M01.XML",
            "PRIVATE/M4ROOT/MEDIAPRO.XML",
        ])
        XCTAssertEqual(ClipScanner.scan(volumeURL: card, categories: [.audio]).map(\.relativePath), ["AUDIO/ZOOM0001.WAV"])

        let destination = root.appendingPathComponent("Dest")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let naming = NamingTemplates(folder: "{type}", file: "{date}_{project}_{seq}")!
        let plan = OffloadPlanner.plan(files: files, naming: naming, context: NamingContext(project: "Beach"),
                                       existingNames: OffloadPlanner.diskLister(root: destination))
        let date = Renamer.dateString(for: files[0].captureDate)
        XCTAssertEqual(plan.map(\.relativePath), [
            "Video/\(date)_Beach_0001.mp4",
            "Video/\(date)_Beach_0001M01.xml",
            "Photo/\(date)_Beach_0001.arw",
            "Photo/\(date)_Beach_0002.jpg",
            "Video/\(date)_Beach_0002.mp4",
            "Video/\(date)_Beach_0002M01.xml",
            "Audio/\(date)_Beach_0001.wav",
            "Other/\(date)_Beach_0001.xml",
            "Other/\(date)_Beach_0002.dat",
        ])

        let volume = CardVolume(url: card, name: "CARD", uuid: "CARD-UUID")
        let job = OffloadJob(card: volume, plan: plan, destination: destination, alreadyOffloaded: 0)
        let recorder = EntryRecorder()
        let summary = await Offloader.run(job: job, progress: { _ in }, record: { await recorder.add($0) })
        XCTAssertEqual(summary.copied, plan.count)
        XCTAssertEqual(summary.failed, 0)

        // What was copied is exactly what the preview showed, in the same order.
        let entries = await recorder.entries
        XCTAssertEqual(entries.map(\.sourceRelativePath), plan.map(\.id))
        XCTAssertEqual(entries.map(\.destinationPath),
                       plan.map { destination.appendingPathComponent($0.relativePath).path })
        XCTAssertTrue(entries.allSatisfy { $0.sha256.count == 64 })
        for item in plan {
            XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent(item.relativePath)),
                           try Data(contentsOf: item.clip.url), item.relativePath)
        }
        // Junk stayed behind, and the card is untouched.
        let copied = try FileManager.default.subpathsOfDirectory(atPath: destination.path).filter { !$0.hasSuffix("/") }
        XCTAssertFalse(copied.contains { $0.contains("DS_Store") || $0.contains("Spotlight") || $0.contains("RECYCLE") })
        XCTAssertTrue(FileManager.default.fileExists(atPath: card.appendingPathComponent(".DS_Store").path))

        // A second scan with those entries in the ledger finds nothing new, of any type.
        let card2 = await MainActor.run {
            OffloadSession(card: volume, clips: ClipScanner.scan(volumeURL: card), knownKeys: Set(entries.map(\.sourceKey)))
        }
        let remaining = await MainActor.run { card2.newClips.count }
        XCTAssertEqual(remaining, 0)
    }
}

/// Collects ledger entries from the background offload in a thread-safe way.
private actor EntryRecorder {
    var entries: [LedgerEntry] = []
    func add(_ entry: LedgerEntry) { entries.append(entry) }
}
