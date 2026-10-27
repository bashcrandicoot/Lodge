import XCTest
@testable import Lodge

final class RecentOffloadsTests: XCTestCase {
    private func entry(_ copyName: String, source: String = "DCIM/100MSDCF/FILE") -> LedgerEntry {
        LedgerEntry(sourceKey: "key-\(copyName)", cardName: "A7S3", sourceRelativePath: source,
                    destinationPath: "/Users/demo/Movies/Shoot/" + copyName,
                    size: 1, sha256: "x", offloadedAt: Date(timeIntervalSince1970: 0))
    }

    func testVideoGetsFilmIcon() {
        XCTAssertEqual(entry("C0001.mov").category, .video)
        XCTAssertEqual(entry("C0001.mov").category.symbol, "film")
        for name in ["a.mp4", "a.mxf", "a.m4v", "a.braw", "a.r3d", "a.mts", "a.m2ts", "a.insv"] {
            XCTAssertEqual(entry(name).category.symbol, "film", name)
        }
    }

    func testPhotosAndRawGetPhotoIcon() {
        XCTAssertEqual(entry("DSC00001.jpg").category, .photo)
        XCTAssertEqual(entry("DSC00001.arw").category, .photo)
        XCTAssertEqual(entry("DSC00001.arw").category.symbol, "photo")
        for name in ["a.heic", "a.png", "a.tiff", "a.dng", "a.cr3", "a.nef", "a.raf", "a.gpr"] {
            XCTAssertEqual(entry(name).category.symbol, "photo", name)
        }
    }

    func testAudioGetsWaveformIcon() {
        XCTAssertEqual(entry("ZOOM0001.wav").category, .audio)
        XCTAssertEqual(entry("ZOOM0001.wav").category.symbol, "waveform")
        for name in ["a.mp3", "a.m4a", "a.aif", "a.aiff", "a.flac", "a.bwf"] {
            XCTAssertEqual(entry(name).category.symbol, "waveform", name)
        }
    }

    func testUppercaseExtensions() {
        XCTAssertEqual(entry("C0001.MOV").category.symbol, "film")
        XCTAssertEqual(entry("DSC00001.JPG").category.symbol, "photo")
        XCTAssertEqual(entry("DSC00001.ARW").category.symbol, "photo")
        XCTAssertEqual(entry("ZOOM0001.WAV").category.symbol, "waveform")
        XCTAssertEqual(entry("Clip.Mp4").category.symbol, "film")
    }

    func testUnknownOrMissingExtensionFallsBackToDoc() {
        XCTAssertEqual(entry("C0001M01.XML").category, .other)
        XCTAssertEqual(entry("C0001M01.XML").category.symbol, "doc")
        XCTAssertEqual(entry("notes.xyz").category.symbol, "doc")
        XCTAssertEqual(entry("README", source: "README").category.symbol, "doc")
    }

    func testCopyWithoutExtensionUsesTheNameOnTheCard() {
        XCTAssertEqual(entry("Interview", source: "PRIVATE/M4ROOT/CLIP/C0001.MP4").category, .video)
    }
}
