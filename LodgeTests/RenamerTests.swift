import XCTest
@testable import Lodge

final class RenamerTests: XCTestCase {
    func testSanitizeName() {
        XCTAssertEqual(Renamer.sanitizeName("Beach Shoot"), "BeachShoot")
        XCTAssertEqual(Renamer.sanitizeName("beach shoot"), "BeachShoot")
        XCTAssertEqual(Renamer.sanitizeName("  my_wedding!! day 2 "), "MyWeddingDay2")
        XCTAssertEqual(Renamer.sanitizeName("sunset-beach"), "Sunset-beach")
        XCTAssertEqual(Renamer.sanitizeName("--hello--"), "Hello")
        XCTAssertEqual(Renamer.sanitizeName("../../etc"), "Etc")
        XCTAssertEqual(Renamer.sanitizeName("   "), "")
    }

    func testDateString() {
        let date = Date(timeIntervalSince1970: 1_761_400_000) // 2025-10-25 13:46:40 UTC
        XCTAssertEqual(Renamer.dateString(for: date, timeZone: TimeZone(identifier: "UTC")!), "2025-10-25")
    }

    func testFileNameAndFolder() {
        let prefix = Renamer.prefix(dateString: "2026-10-25", project: "Coastline")
        XCTAssertEqual(Renamer.fileName(prefix: prefix, sequence: 7, fileExtension: "MP4"), "2026-10-25_Coastline_0007.mp4")
        let folder = Renamer.folderURL(destination: URL(fileURLWithPath: "/Dest"), dateString: "2026-10-25", project: "Coastline")
        XCTAssertEqual(folder.path, "/Dest/2026-10-25/Coastline")
    }

    func testSequenceParsing() {
        let prefix = "2026-10-25_Coastline"
        XCTAssertEqual(Renamer.sequenceNumber(in: "2026-10-25_Coastline_0012.mp4", prefix: prefix), 12)
        XCTAssertEqual(Renamer.sequenceNumber(in: "2026-10-25_coastline_0003.MOV", prefix: prefix), 3)
        XCTAssertEqual(Renamer.sequenceNumber(in: "2026-10-25_Coastline_0004.mp4.lodge-partial", prefix: prefix), 4)
        XCTAssertNil(Renamer.sequenceNumber(in: "2026-10-25_CoastlineTwo_0099.mp4", prefix: prefix))
        XCTAssertNil(Renamer.sequenceNumber(in: "2026-10-25_Coastline_12abc.mp4", prefix: prefix))
        XCTAssertNil(Renamer.sequenceNumber(in: "notes.txt", prefix: prefix))
        XCTAssertEqual(Renamer.highestSequence(in: ["2026-10-25_Coastline_0002.mp4", "2026-10-25_Coastline_0010.mov", "x.mp4"], prefix: prefix), 10)
        XCTAssertEqual(Renamer.highestSequence(in: [], prefix: prefix), 0)
    }

    func testAllocatorContinuesAfterExistingFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lodge-alloc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let prefix = "2026-10-25_Test"
        FileManager.default.createFile(atPath: folder.appendingPathComponent("\(prefix)_0005.mp4").path, contents: Data())

        var allocator = SequenceAllocator()
        XCTAssertEqual(allocator.nextFileURL(folder: folder, prefix: prefix, fileExtension: "MOV").lastPathComponent, "\(prefix)_0006.mov")
        XCTAssertEqual(allocator.nextFileURL(folder: folder, prefix: prefix, fileExtension: "mp4").lastPathComponent, "\(prefix)_0007.mp4")
        // Someone else created 0008 in the meantime: it must be skipped, never overwritten.
        FileManager.default.createFile(atPath: folder.appendingPathComponent("\(prefix)_0008.mp4").path, contents: Data())
        XCTAssertEqual(allocator.nextFileURL(folder: folder, prefix: prefix, fileExtension: "mp4").lastPathComponent, "\(prefix)_0009.mp4")
    }
}

final class FilterAndKeyTests: XCTestCase {
    func testClipFileNames() {
        XCTAssertTrue(ClipScanner.isClipFileName("C0001.MP4"))
        XCTAssertTrue(ClipScanner.isClipFileName("clip.mov"))
        XCTAssertTrue(ClipScanner.isClipFileName("A001.MXF"))
        XCTAssertTrue(ClipScanner.isClipFileName("A001_C002.braw"))
        XCTAssertFalse(ClipScanner.isClipFileName("._C0001.MP4"))
        XCTAssertFalse(ClipScanner.isClipFileName(".hidden.mp4"))
        XCTAssertFalse(ClipScanner.isClipFileName("IMG_0001.JPG"))
        XCTAssertFalse(ClipScanner.isClipFileName("C0001.XML"))
    }

    func testVolumeFilter() {
        XCTAssertTrue(VolumeFilter.isCandidate(path: "/Volumes/SD", isRemovable: true, isEjectable: true, isRootFileSystem: false, destinationPath: "/Users/me/Footage"))
        XCTAssertFalse(VolumeFilter.isCandidate(path: "/", isRemovable: false, isEjectable: false, isRootFileSystem: true, destinationPath: nil))
        XCTAssertFalse(VolumeFilter.isCandidate(path: "/Volumes/Internal", isRemovable: false, isEjectable: false, isRootFileSystem: false, destinationPath: nil))
        XCTAssertFalse(VolumeFilter.isCandidate(path: "/Volumes/T7", isRemovable: true, isEjectable: true, isRootFileSystem: false, destinationPath: "/Volumes/T7/Footage"))
        XCTAssertTrue(VolumeFilter.isCandidate(path: "/Volumes/T7", isRemovable: true, isEjectable: true, isRootFileSystem: false, destinationPath: "/Volumes/T7 2/Footage"))
    }

    func testLedgerKey() {
        let date = Date(timeIntervalSince1970: 1000.7)
        XCTAssertEqual(LedgerKey.make(volumeIdentity: "UUID-1", relativePath: "DCIM/C1.MP4", size: 42, modificationDate: date), "UUID-1|DCIM/C1.MP4|42|1000")
        XCTAssertEqual(LedgerKey.make(volumeIdentity: "CARD", relativePath: "a.mov", size: 1, modificationDate: nil), "CARD|a.mov|1|nodate")
    }
}
