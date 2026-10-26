import XCTest
@testable import Lodge

/// Every file goes into a folder for its own extension (MP4/, ARW/, WAV/, XYZ/…), with proxies
/// and sidecars in Proxies/ and Sidecars/, and nothing shares a Video/Photo/Other folder.
final class FormatFolderTests: XCTestCase {
    private func file(_ path: String, minutesAfter minutes: Double = 0) -> Clip {
        var components = DateComponents()
        components.year = 2026; components.month = 10; components.day = 25; components.hour = 10
        let date = Calendar.current.date(from: components)!.addingTimeInterval(minutes * 60)
        return Clip(url: URL(fileURLWithPath: "/Volumes/CARD/" + path), relativePath: path,
                    size: 1, creationDate: date, modificationDate: date)
    }

    func testFolderNames() {
        XCTAssertEqual(FormatFolder.name(forExtension: "MP4"), "MP4")
        XCTAssertEqual(FormatFolder.name(forExtension: "mp4"), "MP4", ".MP4 and .mp4 share a folder")
        XCTAssertEqual(FormatFolder.name(forExtension: "Mov"), "MOV")
        XCTAssertEqual(FormatFolder.name(forExtension: "braw"), "BRAW")
        XCTAssertEqual(FormatFolder.name(forExtension: "JPG"), "JPG")
        XCTAssertEqual(FormatFolder.name(forExtension: "jpeg"), "JPG", ".JPEG is the same format as .JPG")
        XCTAssertEqual(FormatFolder.name(forExtension: "TIFF"), "TIF")
        XCTAssertEqual(FormatFolder.name(forExtension: "360"), "360")
        XCTAssertEqual(FormatFolder.name(forExtension: "xyz"), "XYZ", "Unknown extensions get their own folder")
        XCTAssertEqual(FormatFolder.name(forFile: "C0001.MP4"), "MP4")
        XCTAssertNil(FormatFolder.name(forFile: "README"))
        XCTAssertNil(FormatFolder.name(forExtension: ""))
    }

    func testMixedCardGetsOneFolderPerExtension() {
        let names = ["C0001.MP4", "c0002.mp4", "A001.MOV", "B001.MXF", "A001_C001.braw", "A001.R3D",
                     "DSC0001.ARW", "IMG_0001.CR3", "DSC_0001.NEF", "IMG_0002.DNG", "DSCF0001.RAF",
                     "IMG_0003.HEIC", "IMG_0004.JPG", "IMG_0005.jpeg", "Screen.png", "ZOOM0001.WAV",
                     "voice.mp3", "scan.TIF", "scan2.tiff", "odd.xyz"]
        let files = names.enumerated().map { file("DCIM/" + $0.element, minutesAfter: Double($0.offset)) }
        let plan = OffloadPlanner.plan(files: files, naming: .standard, context: NamingContext(project: "Mix"),
                                       existingNames: { _ in [] })
        let folderOf = Dictionary(uniqueKeysWithValues: plan.map { ($0.originalName, $0.folder) })
        let expected: [String: String] = [
            "C0001.MP4": "MP4", "c0002.mp4": "MP4", "A001.MOV": "MOV", "B001.MXF": "MXF",
            "A001_C001.braw": "BRAW", "A001.R3D": "R3D", "DSC0001.ARW": "ARW", "IMG_0001.CR3": "CR3",
            "DSC_0001.NEF": "NEF", "IMG_0002.DNG": "DNG", "DSCF0001.RAF": "RAF", "IMG_0003.HEIC": "HEIC",
            "IMG_0004.JPG": "JPG", "IMG_0005.jpeg": "JPG", "Screen.png": "PNG", "ZOOM0001.WAV": "WAV",
            "voice.mp3": "MP3", "scan.TIF": "TIF", "scan2.tiff": "TIF", "odd.xyz": "XYZ",
        ]
        for (name, format) in expected {
            XCTAssertEqual(folderOf[name], "2026-10-25/Mix/" + format, name)
        }
        XCTAssertEqual(plan.count, names.count)
        XCTAssertTrue(plan.allSatisfy { $0.templateFolder == "2026-10-25/Mix" })
        XCTAssertTrue(plan.allSatisfy { !["Video", "Photo", "Audio", "Other"].contains($0.sortFolder ?? "") })
        // One running number for the whole shoot, in capture order, across the format folders.
        XCTAssertEqual(plan.map(\.fileName), (1...names.count).map { i -> String in
            let ext = (names[i - 1] as NSString).pathExtension.lowercased()
            return String(format: "2026-10-25_Mix_%04d.", i) + ext
        })
    }

    func testProxiesAndSidecarsKeepTheirOwnFolders() {
        let files = [
            file("DCIM/100GOPRO/GX010001.MP4"), file("DCIM/100GOPRO/GL010001.LRV"), file("DCIM/100GOPRO/GX010001.THM"),
            file("PRIVATE/M4ROOT/CLIP/C0001.MP4", minutesAfter: 1), file("PRIVATE/M4ROOT/CLIP/C0001M01.XML", minutesAfter: 1),
            file("PRIVATE/M4ROOT/CLIP/C0001.WAV", minutesAfter: 1),
            file("DCIM/100MSDCF/DSC00001.ARW", minutesAfter: 2), file("DCIM/100MSDCF/DSC00001.JPG", minutesAfter: 2),
            file("PRIVATE/M4ROOT/MEDIAPRO.XML", minutesAfter: 3),
        ]
        let plan = OffloadPlanner.plan(files: files, naming: .standard, context: NamingContext(project: "Surf"),
                                       existingNames: { _ in [] })
        XCTAssertEqual(plan.map(\.relativePath), [
            "2026-10-25/Surf/MP4/2026-10-25_Surf_0001.mp4",
            "2026-10-25/Surf/Proxies/2026-10-25_Surf_0001.lrv",
            "2026-10-25/Surf/Sidecars/2026-10-25_Surf_0001.thm",
            "2026-10-25/Surf/MP4/2026-10-25_Surf_0002.mp4",
            "2026-10-25/Surf/WAV/2026-10-25_Surf_0002.wav",
            "2026-10-25/Surf/Sidecars/2026-10-25_Surf_0002M01.xml",
            "2026-10-25/Surf/ARW/2026-10-25_Surf_0003.arw",
            "2026-10-25/Surf/JPG/2026-10-25_Surf_0004.jpg",
            "2026-10-25/Surf/Sidecars/MEDIAPRO.xml",
        ])
        XCTAssertEqual(plan.map(\.sortFolder), ["MP4", "Proxies", "Sidecars", "MP4", "WAV", "Sidecars", "ARW", "JPG", "Sidecars"])
        XCTAssertEqual(plan[4].sidecarOf, "C0001.MP4", "The clip's audio keeps its name, in the WAV folder")
    }

    func testNumberingCarriesOnFromEveryFormatFolder() {
        let existing: OffloadPlanner.ExistingNames = { folder in
            switch folder {
            case "2026-10-25/Trip": return ["2026-10-25_Trip_0002.mp4"]          // older offload, before format folders
            case "2026-10-25/Trip/ARW": return ["2026-10-25_Trip_0007.arw"]
            default: return []
            }
        }
        let plan = OffloadPlanner.plan(files: [file("DCIM/C0010.MP4"), file("DCIM/DSC0011.ARW", minutesAfter: 1)],
                                       naming: .standard, context: NamingContext(project: "Trip"), existingNames: existing)
        XCTAssertEqual(plan.map(\.relativePath), ["2026-10-25/Trip/MP4/2026-10-25_Trip_0008.mp4",
                                                  "2026-10-25/Trip/ARW/2026-10-25_Trip_0009.arw"])
    }

    func testTypeLevelStillSplitsByExtension() throws {
        let naming = try XCTUnwrap(NamingTemplates(folder: "{project}/{type}", file: "{original}"))
        let plan = OffloadPlanner.plan(files: [file("A.MP4"), file("B.MOV"), file("C.JPG"), file("D.JPEG"), file("E.xyz")],
                                       naming: naming, context: NamingContext(project: "Doc"), existingNames: { _ in [] })
        XCTAssertEqual(plan.map(\.folder), ["Doc/Video/MP4", "Doc/Video/MOV", "Doc/Photo/JPG", "Doc/Photo/JPG", "Doc/Other/XYZ"])
    }

    func testIgnoreListStillApplies() throws {
        let card = FileManager.default.temporaryDirectory.appendingPathComponent("lodge-formats-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: card) }
        for path in ["DCIM/C0001.MP4", "DCIM/C0001.tmp", "DCIM/._C0001.MP4", ".DS_Store", "DCIM/odd.xyz"] {
            let url = card.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: url)
        }
        var rules = FileRules.standard
        rules.ignorePatterns += ["*.tmp"]
        let files = ClipScanner.scan(volumeURL: card, rules: rules)
        let plan = OffloadPlanner.plan(files: files, naming: .standard, context: NamingContext(project: "P"),
                                       rules: rules, existingNames: { _ in [] })
        XCTAssertEqual(Set(plan.compactMap(\.sortFolder)), ["MP4", "XYZ"], "No TMP folder: ignored files aren't offloaded")
    }

    func testTreeShowsFormatFoldersBeforeProxiesAndSidecars() {
        let files = [file("DCIM/GX010001.MP4"), file("DCIM/GL010001.LRV"), file("DCIM/GX010001.THM"),
                     file("DCIM/DSC0001.ARW", minutesAfter: 1), file("DCIM/A.wav", minutesAfter: 2),
                     file("DCIM/B.MP4", minutesAfter: 3)]
        let plan = OffloadPlanner.plan(files: files, naming: .standard, context: NamingContext(project: "Surf"),
                                       existingNames: { _ in [] })
        let shoot = FolderTree.build(rootName: "Movies", plan: plan).node(at: "2026-10-25/Surf")
        XCTAssertEqual(shoot?.children.map(\.name), ["ARW", "MP4", "WAV", "Proxies", "Sidecars"])
        XCTAssertEqual(shoot?.children.map(\.isFormatFolder), [true, true, true, false, false])
        XCTAssertEqual(shoot?.children.map(\.isRoleFolder), [false, false, false, true, true])
        XCTAssertEqual(shoot?.node(at: "2026-10-25/Surf/MP4")?.fileCount, 2)
        XCTAssertTrue(shoot?.files.isEmpty == true, "Nothing is left loose in the shoot folder")
    }
}
