import XCTest
@testable import Lodge

final class FinderRevealTests: XCTestCase {
    private let destination = URL(fileURLWithPath: "/Volumes/Footage/Projects", isDirectory: true)
    private func url(_ path: String) -> URL { URL(fileURLWithPath: path) }
    private func folder(_ path: String) -> URL { URL(fileURLWithPath: path, isDirectory: true) }

    func testOneFileIsSelectedInItsFolder() {
        XCTAssertEqual(FinderReveal.target(files: [url("/Volumes/Footage/Projects/Doc/2026-10-28/A001.MP4")],
                                           destination: destination),
                       .select(url("/Volumes/Footage/Projects/Doc/2026-10-28/A001.MP4")))
    }

    func testFilesInOneFolderOpenThatFolderOnce() {
        let files = ["A001.MP4", "A002.MP4", "A003.MP4"].map { url("/Volumes/Footage/Projects/Doc/2026-10-28/\($0)") }
        XCTAssertEqual(FinderReveal.target(files: files, destination: destination),
                       .open(folder("/Volumes/Footage/Projects/Doc/2026-10-28")))
    }

    func testFilesInSeveralFoldersOpenTheFolderTheyShare() {
        let files = [url("/Volumes/Footage/Projects/Doc/2026-10-27/FX6/A001.MXF"),
                     url("/Volumes/Footage/Projects/Doc/2026-10-28/FX6/A002.MXF"),
                     url("/Volumes/Footage/Projects/Doc/2026-10-28/A7S/C0001.MP4")]
        XCTAssertEqual(FinderReveal.target(files: files, destination: destination),
                       .open(folder("/Volumes/Footage/Projects/Doc")))
    }

    func testDuplicatesCountOnce() {
        let file = url("/Volumes/Footage/Projects/Doc/A001.MP4")
        XCTAssertEqual(FinderReveal.target(files: [file, file], destination: destination), .select(file))
    }

    func testNoFilesOpenTheDestination() {
        XCTAssertEqual(FinderReveal.target(files: [], destination: destination), .open(destination))
        XCTAssertNil(FinderReveal.target(files: [], destination: nil))
    }

    func testFilesOnlySharingAVolumeFallBackToTheDestination() {
        let files = [url("/Volumes/Footage/A.MP4"), url("/Volumes/Other/B.MP4")]
        XCTAssertEqual(FinderReveal.target(files: files, destination: destination), .open(destination))
    }
}
