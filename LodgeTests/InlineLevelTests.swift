import XCTest
@testable import Lodge

/// Tokens side by side in one folder level ("{project}_{date}").
final class InlineLevelTests: XCTestCase {
    private func clip(_ path: String = "DCIM/C0001.MP4", day: Int = 25) -> Clip {
        var components = DateComponents()
        components.year = 2026; components.month = 10; components.day = day; components.hour = 10
        let date = Calendar.current.date(from: components)!
        return Clip(url: URL(fileURLWithPath: "/Volumes/CARD/" + path), relativePath: path,
                    size: 1, creationDate: date, modificationDate: date)
    }

    private func folder(_ template: String, _ context: NamingContext, file: Clip? = nil) throws -> String {
        let parsed = try XCTUnwrap(NamingTemplate.parse(template, kind: .folder).template, template)
        return TemplateRenderer.folderPath(parsed, file: file ?? clip(), context: context)
    }

    // MARK: Parsing

    func testParsesSideBySideTokens() {
        XCTAssertEqual(InlineLevel("{project}_{date}"), InlineLevel(items: ["{project}", "{date}"], separator: "_"))
        XCTAssertEqual(InlineLevel("{project}-{date}-{camera}").items, ["{project}", "{date}", "{camera}"])
        XCTAssertEqual(InlineLevel("{project}-{date}").separator, "-")
        XCTAssertEqual(InlineLevel("{date} {project}"), InlineLevel(items: ["{date}", "{project}"], separator: " "))
        XCTAssertEqual(InlineLevel("{project}{date}"), InlineLevel(items: ["{project}", "{date}"], separator: ""))
        XCTAssertEqual(InlineLevel("Clients_{project}").items, ["Clients", "{project}"])
        XCTAssertEqual(InlineLevel("{seq:3}_{date}").items, ["{seq:3}", "{date}"], "Padding stays with its token")
        XCTAssertTrue(InlineLevel("{project}_{date}").isCombined)
    }

    func testSinglePiecesStayWhole() {
        XCTAssertEqual(InlineLevel("{date}").items, ["{date}"])
        XCTAssertEqual(InlineLevel("Clients").items, ["Clients"])
        XCTAssertEqual(InlineLevel("Raw_Footage").items, ["Raw_Footage"], "No token, so not split")
        XCTAssertEqual(InlineLevel("{project}__{date}").items, ["{project}__{date}"], "An empty piece means it stays whole")
        XCTAssertEqual(InlineLevel("_{date}").items, ["_{date}"])
        XCTAssertEqual(InlineLevel("").items, [])
        XCTAssertFalse(InlineLevel("{date}").isCombined)
    }

    func testEveryExistingTemplateRoundTrips() {
        let templates = NamingPreset.all.map(\.folder) + [
            "{date}/{camera}", "Clients/{project}/{date}", "{year}/{date} {project}",
            "{project}_{date}/{camera}/{type}", "{project}{date}", "Raw_Footage/{date}", "{project}__{date}",
            "{date}-{project}_{camera}",
        ]
        for template in templates {
            for level in FolderTemplateEditor.levels(template) {
                XCTAssertEqual(InlineLevel(level).text, level, "\(template): \(level)")
            }
        }
        // Mixed separators: split on the first one, the rest stays in its piece.
        XCTAssertEqual(InlineLevel("{date}-{project}_{camera}").items, ["{date}", "{project}_{camera}"])
    }

    func testSeparatorNames() {
        XCTAssertEqual(InlineLevel.separators, ["_", "-", " ", ""])
        XCTAssertEqual(InlineLevel.defaultSeparator, "_")
        XCTAssertEqual(InlineLevel.separators.map(InlineLevel.name(ofSeparator:)), ["Underscore", "Hyphen", "Space", "None"])
        XCTAssertEqual(InlineLevel.symbol(ofSeparator: " "), "␣")
        XCTAssertEqual(InlineLevel.symbol(ofSeparator: ""), "none")
        XCTAssertEqual(InlineLevel.symbol(ofSeparator: "_"), "_")
    }

    // MARK: Editing

    func testDroppingATokenBesideAnother() {
        let t = "{project}/{date}/{camera}"
        XCTAssertEqual(FolderTemplateEditor.insertInline("{date}", into: "{project}/{camera}", level: 0, at: 1), "{project}_{date}/{camera}")
        XCTAssertEqual(FolderTemplateEditor.insertInline("{date}", into: "{project}/{camera}", level: 0, at: 0), "{date}_{project}/{camera}")
        XCTAssertEqual(FolderTemplateEditor.insertInline("{type}", into: "{project}-{date}", level: 0, at: 1), "{project}-{type}-{date}",
                       "Joins the level's own separator")
        XCTAssertEqual(FolderTemplateEditor.insertInline("{type}", into: t, level: 0, at: 99), "{project}_{type}/{date}/{camera}")
        XCTAssertEqual(FolderTemplateEditor.insertInline("{type}", into: t, level: 5, at: 0), t, "No such level")
        XCTAssertEqual(FolderTemplateEditor.dropInline(.token(.date), level: 0, at: 1, in: "{project}/{camera}"), "{project}_{date}/{camera}")
        XCTAssertEqual(FolderTemplateEditor.inlineLevel("{project}_{date}/{camera}", at: 0)?.items, ["{project}", "{date}"])
        XCTAssertNil(FolderTemplateEditor.inlineLevel("{date}", at: 3))
    }

    func testMergingAWholeLevel() {
        let t = "{project}/{date}/{camera}"
        XCTAssertEqual(FolderTemplateEditor.dropInline(.level(1), level: 0, at: 1, in: t), "{project}_{date}/{camera}")
        XCTAssertEqual(FolderTemplateEditor.dropInline(.level(0), level: 1, at: 0, in: t), "{project}_{date}/{camera}")
        XCTAssertEqual(FolderTemplateEditor.dropInline(.level(2), level: 0, at: 0, in: t), "{camera}_{project}/{date}")
        XCTAssertEqual(FolderTemplateEditor.mergeLevel(t, level: 1, into: 1, at: 0), t, "Not onto itself")
        XCTAssertEqual(FolderTemplateEditor.mergeLevel("{date}/{project}_{camera}", level: 1, into: 0, at: 1),
                       "{date}_{project}_{camera}")
    }

    func testReorderingMovingAndRemovingPieces() {
        let t = "{project}_{date}_{camera}/{type}"
        // Reorder in the row.
        XCTAssertEqual(FolderTemplateEditor.moveItem(t, level: 0, item: 0, toLevel: 0, at: 2), "{date}_{project}_{camera}/{type}")
        XCTAssertEqual(FolderTemplateEditor.moveItem(t, level: 0, item: 0, toLevel: 0, at: 3), "{date}_{camera}_{project}/{type}")
        XCTAssertEqual(FolderTemplateEditor.moveItem(t, level: 0, item: 2, toLevel: 0, at: 0), "{camera}_{project}_{date}/{type}")
        XCTAssertEqual(FolderTemplateEditor.moveItem(t, level: 0, item: 1, toLevel: 0, at: 1), t, "Dropped where it was")
        XCTAssertEqual(FolderTemplateEditor.dropInline(.item(level: 0, item: 1), level: 0, at: 0, in: t), "{date}_{project}_{camera}/{type}")
        // Into another level; an emptied level goes away.
        XCTAssertEqual(FolderTemplateEditor.moveItem(t, level: 0, item: 2, toLevel: 1, at: 1), "{project}_{date}/{type}_{camera}")
        XCTAssertEqual(FolderTemplateEditor.moveItem("{date}/{project}", level: 1, item: 0, toLevel: 0, at: 1), "{date}_{project}")
        // Out to its own level.
        XCTAssertEqual(FolderTemplateEditor.extractItem(t, level: 0, item: 1, toSlot: 1), "{project}_{camera}/{date}/{type}")
        XCTAssertEqual(FolderTemplateEditor.extractItem(t, level: 0, item: 0, toSlot: 0), "{project}/{date}_{camera}/{type}")
        XCTAssertEqual(FolderTemplateEditor.extractItem(t, level: 0, item: 2, toSlot: 2), "{project}_{date}/{type}/{camera}")
        XCTAssertEqual(FolderTemplateEditor.extractItem("{project}_{date}", level: 0, item: 1, toSlot: 1), "{project}/{date}")
        XCTAssertEqual(FolderTemplateEditor.drop(.item(level: 0, item: 1), on: 1, in: "{project}_{date}/{camera}"),
                       "{project}/{date}/{camera}", "Dropping a piece between rows makes a level")
        XCTAssertEqual(FolderTemplateEditor.extractItem("{date}/{camera}", level: 0, item: 0, toSlot: 2), "{camera}/{date}",
                       "A single piece just moves its level")
        // Remove.
        XCTAssertEqual(FolderTemplateEditor.removeItem(t, level: 0, item: 1), "{project}_{camera}/{type}")
        XCTAssertEqual(FolderTemplateEditor.removeItem("{project}_{date}/{type}", level: 0, item: 0), "{date}/{type}")
        XCTAssertEqual(FolderTemplateEditor.removeItem("{date}/{type}", level: 1, item: 0), "{date}")
        XCTAssertEqual(FolderTemplateEditor.removeItem(t, level: 0, item: 9), t)
    }

    func testChangingTheSeparator() {
        let t = "{project}_{date}/{camera}"
        XCTAssertEqual(FolderTemplateEditor.setSeparator("-", in: t, level: 0), "{project}-{date}/{camera}")
        XCTAssertEqual(FolderTemplateEditor.setSeparator(" ", in: t, level: 0), "{project} {date}/{camera}")
        XCTAssertEqual(FolderTemplateEditor.setSeparator("", in: t, level: 0), "{project}{date}/{camera}")
        XCTAssertEqual(FolderTemplateEditor.setSeparator("_", in: "{project}{date}", level: 0), "{project}_{date}",
                       "Back from none")
        XCTAssertEqual(FolderTemplateEditor.setSeparator("-", in: t, level: 1), t, "Nothing to separate")
        for separator in InlineLevel.separators {
            let changed = FolderTemplateEditor.setSeparator(separator, in: t, level: 0)
            XCTAssertNotNil(NamingTemplates(folder: changed, file: NamingTemplates.defaultFile), changed)
            XCTAssertEqual(InlineLevel(FolderTemplateEditor.levels(changed)[0]).separator, separator)
        }
    }

    func testDragPayloadTextRoundTrips() {
        let payloads: [FolderTemplateEditor.Payload] = [.token(.date), .level(2), .item(level: 1, item: 3)]
        for payload in payloads {
            XCTAssertEqual(FolderTemplateEditor.payload(FolderTemplateEditor.text(for: payload)), payload)
        }
        XCTAssertNil(FolderTemplateEditor.payload("lodge-item:1"))
        XCTAssertNil(FolderTemplateEditor.payload("lodge-item:a:b"))
    }

    // MARK: Rendering

    func testCombinedLevelsRender() throws {
        let context = NamingContext(project: "Coastline", camera: "A7S3", card: "Card")
        XCTAssertEqual(try folder("{project}_{date}/{camera}", context), "Coastline_2026-10-25/A7S3")
        XCTAssertEqual(try folder("{project}-{date}", context), "Coastline-2026-10-25")
        XCTAssertEqual(try folder("{project} {date}", context), "Coastline 2026-10-25")
        XCTAssertEqual(try folder("{project}{date}", context), "Coastline2026-10-25")
        XCTAssertEqual(try folder("{date}_{camera}_{type}", context), "2026-10-25_A7S3_Video")
        XCTAssertEqual(try folder("Clients_{project}/{year}", context), "Clients_Coastline/2026")
    }

    func testAnEmptyTokenTakesItsSeparatorAlong() throws {
        let noCamera = NamingContext(project: "Coastline", camera: "", card: "Card")
        XCTAssertEqual(try folder("{camera}_{date}", noCamera), "2026-10-25")
        XCTAssertEqual(try folder("{date}_{camera}", noCamera), "2026-10-25")
        XCTAssertEqual(try folder("{project}_{camera}_{date}", noCamera), "Coastline_2026-10-25")
        XCTAssertEqual(try folder("{project}-{camera}", noCamera), "Coastline")
        let nothing = NamingContext(project: "", camera: "", card: "Card")
        XCTAssertEqual(try folder("{project}_{camera}", nothing), TemplateRenderer.fallbackName)
    }

    func testCombinedLevelsAreSanitised() throws {
        let context = NamingContext(project: "Beach/Day: 2", camera: "A7S3", card: "Card")
        let path = try folder("{project}_{date}/{camera}", context)
        let levels = path.split(separator: "/", omittingEmptySubsequences: false)
        XCTAssertEqual(levels.count, 2, "A slash in a value never adds a folder: \(path)")
        XCTAssertFalse(levels[0].contains(":"), path)
        XCTAssertTrue(levels[0].hasSuffix("_2026-10-25"), path)
        XCTAssertEqual(levels[1], "A7S3")
    }

    func testSequenceNumbersCarryOnInACombinedFolder() throws {
        let naming = try XCTUnwrap(NamingTemplates(folder: "{project}_{date}", file: "{date}_{project}_{seq}"))
        let existing: OffloadPlanner.ExistingNames = { folder in
            folder == "Coastline_2026-10-25" ? ["2026-10-25_Coastline_0001.mp4", "2026-10-25_Coastline_0002.mp4"] : []
        }
        let plan = OffloadPlanner.plan(files: [clip("DCIM/C0010.MP4"), clip("DCIM/C0011.MP4"), clip("DCIM/C0012.MP4", day: 26)],
                                       naming: naming,
                                       context: NamingContext(project: "Coastline", camera: "", card: "Card"),
                                       existingNames: existing)
        XCTAssertEqual(plan.map(\.relativePath), [
            "Coastline_2026-10-25/2026-10-25_Coastline_0003.mp4",
            "Coastline_2026-10-25/2026-10-25_Coastline_0004.mp4",
            "Coastline_2026-10-26/2026-10-26_Coastline_0001.mp4",
        ])
    }
}
