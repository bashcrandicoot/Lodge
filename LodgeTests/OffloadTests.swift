import XCTest
@testable import Lodge

/// End-to-end check of scan -> rename -> copy -> verify using a fake card folder.
final class OffloadTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("lodge-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeFakeCard() throws -> URL {
        let card = root.appendingPathComponent("FakeCard")
        let dcim = card.appendingPathComponent("DCIM/100MEDIA")
        try FileManager.default.createDirectory(at: dcim, withIntermediateDirectories: true)
        let bytes = Data((0..<(3 * 1024 * 1024)).map { UInt8($0 % 251) })
        try bytes.write(to: dcim.appendingPathComponent("C0001.MP4"))
        try Data("second".utf8).write(to: dcim.appendingPathComponent("C0002.mov"))
        try Data("junk".utf8).write(to: dcim.appendingPathComponent("._C0001.MP4"))
        try Data("photo".utf8).write(to: dcim.appendingPathComponent("IMG_0001.JPG"))
        // Give both clips a fixed date so the folder name is predictable.
        let date = Date(timeIntervalSince1970: 1_761_400_000)
        for name in ["C0001.MP4", "C0002.mov"] {
            try FileManager.default.setAttributes(
                [.creationDate: date, .modificationDate: date],
                ofItemAtPath: dcim.appendingPathComponent(name).path)
        }
        return card
    }

    func testScannerFindsOnlyClips() throws {
        let card = try makeFakeCard()
        let clips = ClipScanner.scan(volumeURL: card, categories: [.video])
        XCTAssertEqual(clips.map(\.relativePath), ["DCIM/100MEDIA/C0001.MP4", "DCIM/100MEDIA/C0002.mov"])
        XCTAssertEqual(ClipScanner.scan(volumeURL: card).map(\.relativePath),
                       ["DCIM/100MEDIA/C0001.MP4", "DCIM/100MEDIA/C0002.mov", "DCIM/100MEDIA/IMG_0001.JPG"])
    }

    func testScannerFallsBackToRecursiveSearch() throws {
        let card = root.appendingPathComponent("OddCard/Footage/Day1")
        try FileManager.default.createDirectory(at: card, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: card.appendingPathComponent("A001.braw"))
        let clips = ClipScanner.scan(volumeURL: root.appendingPathComponent("OddCard"))
        XCTAssertEqual(clips.map(\.relativePath), ["Footage/Day1/A001.braw"])
    }

    func testCopyVerifyAndRename() async throws {
        let card = try makeFakeCard()
        let destination = root.appendingPathComponent("Destination")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let cardFolder = card.appendingPathComponent("DCIM/100MEDIA").path
        let cardBefore = try FileManager.default.contentsOfDirectory(atPath: cardFolder).sorted()
        let clips = ClipScanner.scan(volumeURL: card, categories: [.video])
        let date = Renamer.dateString(for: clips[0].captureDate)
        let folder = destination.appendingPathComponent(date).appendingPathComponent("BeachShoot")

        // Pretend an earlier offload already produced number 0003 in this folder.
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: folder.appendingPathComponent("\(date)_BeachShoot_0003.mp4"))

        let volume = CardVolume(url: card, name: "FakeCard", uuid: "TEST-UUID")
        let job = OffloadJob(card: volume, clips: clips, project: "BeachShoot", destination: destination, alreadyOffloaded: 0)
        let recorder = Recorder()

        let summary = await Offloader.run(job: job, progress: { _ in }, record: { await recorder.add($0) })
        XCTAssertEqual(summary.copied, 2)
        XCTAssertEqual(summary.failed, 0)
        XCTAssertFalse(summary.cancelled)

        // Numbering carries on from the older file in the shoot folder, across the format folders.
        let names = try FileManager.default.subpathsOfDirectory(atPath: folder.path).sorted()
        XCTAssertEqual(names, [
            "\(date)_BeachShoot_0003.mp4",
            "MOV", "MOV/\(date)_BeachShoot_0005.mov",
            "MP4", "MP4/\(date)_BeachShoot_0004.mp4",
        ])

        // Copy is byte-identical to the source and the old file is untouched.
        let copied = folder.appendingPathComponent("MP4/\(date)_BeachShoot_0004.mp4")
        XCTAssertEqual(try Copier.sha256(of: copied), try Copier.sha256(of: clips[0].url))
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("\(date)_BeachShoot_0003.mp4")), Data("old".utf8))

        // Ledger entries were produced with the right keys and hashes.
        let entries = await recorder.entries
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].sourceKey, clips[0].ledgerKey(volumeIdentity: "TEST-UUID"))
        XCTAssertEqual(entries[0].sha256, try Copier.sha256(of: copied))

        // The card itself is unchanged.
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: cardFolder).sorted(), cardBefore)
        XCTAssertEqual(try Copier.sha256(of: clips[0].url), entries[0].sha256)
    }

    func testCopierRefusesToOverwrite() async throws {
        let source = root.appendingPathComponent("a.mp4")
        let target = root.appendingPathComponent("b.mp4")
        try Data("new".utf8).write(to: source)
        try Data("keep me".utf8).write(to: target)
        do {
            try await Copier.copyAndVerify(source: source, to: target)
            XCTFail("Should have refused to overwrite")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: target), Data("keep me".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: Copier.partialURL(for: target).path))
    }

    @MainActor
    func testLedgerPersistsAndSkipsKnownClips() throws {
        let file = root.appendingPathComponent("ledger.json")
        let ledger = Ledger(fileURL: file)
        let entry = LedgerEntry(sourceKey: "K1", cardName: "SD", sourceRelativePath: "DCIM/C1.MP4",
                                destinationPath: "/x/y.mp4", size: 1, sha256: "abc", offloadedAt: Date())
        ledger.add(entry)

        let reloaded = Ledger(fileURL: file)
        XCTAssertTrue(reloaded.contains(key: "K1"))
        XCTAssertEqual(reloaded.recent().count, 1)

        let card = CardVolume(url: URL(fileURLWithPath: "/Volumes/SD"), name: "SD", uuid: nil)
        let known = Clip(url: URL(fileURLWithPath: "/Volumes/SD/DCIM/C1.MP4"), relativePath: "DCIM/C1.MP4",
                         size: 1, creationDate: nil, modificationDate: nil)
        let fresh = Clip(url: URL(fileURLWithPath: "/Volumes/SD/DCIM/C2.MP4"), relativePath: "DCIM/C2.MP4",
                         size: 1, creationDate: nil, modificationDate: nil)
        let session = OffloadSession(card: card, clips: [known, fresh],
                                     knownKeys: [known.ledgerKey(volumeIdentity: card.identity)])
        XCTAssertEqual(session.newClips.map(\.relativePath), ["DCIM/C2.MP4"])
        XCTAssertEqual(session.alreadyOffloadedCount, 1)
    }
}

/// Collects ledger entries from the background offload in a thread-safe way.
private actor Recorder {
    var entries: [LedgerEntry] = []
    func add(_ entry: LedgerEntry) { entries.append(entry) }
}
