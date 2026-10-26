import XCTest
@testable import Lodge

/// The expandable Layout tree: every planned folder, folders already on disk, and depths.
final class FolderTreeTests: XCTestCase {
    private func clip(_ path: String = "DCIM/C0001.MP4") -> Clip {
        var components = DateComponents()
        components.year = 2026; components.month = 10; components.day = 25; components.hour = 10
        let date = Calendar.current.date(from: components)!
        return Clip(url: URL(fileURLWithPath: "/Volumes/CARD/" + path), relativePath: path,
                    size: 1, creationDate: date, modificationDate: date)
    }

    private func planned(_ folder: String, _ name: String, role: FileRole = .main) -> PlannedFile {
        PlannedFile(clip: clip("DCIM/" + name), folder: folder, fileName: name, sidecarOf: nil, role: role)
    }

    func testTreeHasEveryPlannedFolder() {
        let plan = [
            planned("Coastline_2026-10-25/A7S3/Video", "b.mp4"),
            planned("Coastline_2026-10-25/A7S3/Video", "a.mp4"),
            planned("Coastline_2026-10-25/A7S3/Video/Proxies", "a.lrv", role: .proxy),
            planned("Coastline_2026-10-25/A7S3/Photo", "c.jpg"),
            planned("coastline_2026-10-25/A7S3/Audio", "d.wav"),
            planned("Coastline_2026-10-26/A7S3/Video", "e.mp4"),
        ]
        let tree = FolderTree.build(rootName: "Movies", plan: plan)
        XCTAssertEqual(tree.name, "Movies")
        XCTAssertEqual(tree.path, "")
        XCTAssertEqual(tree.children.map(\.name), ["Coastline_2026-10-25", "Coastline_2026-10-26"], "Case doesn't split a folder")
        XCTAssertEqual(tree.fileCount, 6)
        let camera = tree.node(at: "Coastline_2026-10-25/A7S3")
        XCTAssertEqual(camera?.depth, 2)
        XCTAssertEqual(camera?.children.map(\.name), ["Audio", "Photo", "Video"])
        let video = tree.node(at: "Coastline_2026-10-25/A7S3/Video")
        XCTAssertEqual(video?.files.map(\.fileName), ["b.mp4", "a.mp4"], "Files stay in plan order")
        XCTAssertEqual(video?.children.map(\.name), ["Proxies"])
        XCTAssertEqual(video?.children.first?.isRoleFolder, true)
        XCTAssertEqual(video?.fileCount, 3)
        XCTAssertEqual(tree.allPaths.count, 10)
        XCTAssertNil(tree.node(at: "Nope"))
    }

    func testRoleFoldersComeLast() {
        let plan = [
            planned("Shoot/Sidecars", "a.xml", role: .sidecar),
            planned("Shoot/Proxies", "a.lrv", role: .proxy),
            planned("Shoot/B", "b.mp4"),
            planned("Shoot/Zed", "z.mp4"),
            planned("Shoot/A10", "a10.mp4"),
            planned("Shoot/A9", "a9.mp4"),
        ]
        let shoot = FolderTree.build(rootName: "Root", plan: plan).node(at: "Shoot")
        XCTAssertEqual(shoot?.children.map(\.name), ["A9", "A10", "B", "Zed", "Proxies", "Sidecars"])
        // A folder the template happens to call "Proxies" isn't a role folder.
        let named = FolderTree.build(rootName: "Root", plan: [planned("Proxies", "x.mp4")])
        XCTAssertEqual(named.children.first?.isRoleFolder, false)
    }

    func testOtherFoldersOnDisk() {
        XCTAssertEqual(FolderTree.otherFolders(onDisk: ["Exports", "coastline", ".hidden", "Archive 10", "Archive 9"],
                                               planned: ["Coastline"]),
                       ["Archive 9", "Archive 10", "Exports"])
        XCTAssertEqual(FolderTree.otherFolders(onDisk: [], planned: ["A"]), [])
    }

    func testTreeDepthsFollowTheTemplate() {
        XCTAssertEqual(FolderTree.levelIndices(template: "{project}_{date}/{camera}/{type}", quickDump: false), [0, 1, 2])
        XCTAssertEqual(FolderTree.levelIndices(template: "{project}/{date}/{camera}", quickDump: true), [1, 2])
        XCTAssertEqual(FolderTree.levelIndices(template: "{project}_{date}/{camera}", quickDump: true), [0, 1],
                       "A combined level keeps its other tokens")
        XCTAssertEqual(FolderTree.levelIndices(template: "", quickDump: false), [])
    }

    func testRenderingOnePiece() {
        let context = NamingContext(project: "Coastline", camera: "", card: "Card")
        XCTAssertEqual(FolderTree.render(piece: "{project}", file: clip(), context: context), "Coastline")
        XCTAssertEqual(FolderTree.render(piece: "{date}", file: clip(), context: context), "2026-10-25")
        XCTAssertEqual(FolderTree.render(piece: "{camera}", file: clip(), context: context), "")
        XCTAssertEqual(FolderTree.render(piece: "Clients", file: clip(), context: context), "Clients")
        XCTAssertNil(FolderTree.render(piece: "{nope}", file: clip(), context: context))
    }

    @MainActor
    func testFolderListingCachesUntilRefreshed() throws {
        var calls = 0
        let listing = FolderListing()
        let root = URL(fileURLWithPath: "/Volumes/X")
        let lister: FolderListing.Lister = { url in
            calls += 1
            return url.lastPathComponent == "X" ? ["A", "B"] : nil
        }
        XCTAssertEqual(listing.subfolders(root: root, path: "", using: lister), ["A", "B"])
        XCTAssertEqual(listing.subfolders(root: root, path: "", using: lister), ["A", "B"])
        XCTAssertNil(listing.subfolders(root: root, path: "A", using: lister))
        XCTAssertNil(listing.subfolders(root: root, path: "A", using: lister))
        XCTAssertEqual(calls, 2)
        listing.refresh()
        _ = listing.subfolders(root: root, path: "", using: lister)
        XCTAssertEqual(calls, 3)
        XCTAssertEqual(listing.revision, 1)

        // The real disk: folders only, no hidden ones, nil when missing.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lodge-tree-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Shoot"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent(".cache"), withIntermediateDirectories: true)
        try Data().write(to: folder.appendingPathComponent("clip.mp4"))
        XCTAssertEqual(FolderListing.diskSubfolders(folder), ["Shoot"])
        XCTAssertNil(FolderListing.diskSubfolders(folder.appendingPathComponent("Missing")))
    }
}
