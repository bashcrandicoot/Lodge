import XCTest
@testable import Lodge

/// "Quick dump" (skip the project name), and the drag-and-drop folder tree's template edits.
final class QuickDumpTests: XCTestCase {
    func testProjectDropsOutOfFileNamesCleanly() {
        XCTAssertEqual(QuickDump.fileTemplate("{date}_{project}_{seq}"), "{date}_{seq}")
        XCTAssertEqual(QuickDump.fileTemplate("{date}_{project}{seq}"), "{date}_{seq}")
        XCTAssertEqual(QuickDump.fileTemplate("{project}_{date}_{seq}"), "{date}_{seq}")
        XCTAssertEqual(QuickDump.fileTemplate("{date}_{seq}_{project}"), "{date}_{seq}")
        XCTAssertEqual(QuickDump.fileTemplate("{date}-{Project}-{seq}"), "{date}-{seq}")
        XCTAssertEqual(QuickDump.fileTemplate("{date} {project:upper} {seq}"), "{date} {seq}")
        XCTAssertEqual(QuickDump.fileTemplate("{project}__{shoot}_{camera}_{seq}"), "{camera}_{seq}")
        XCTAssertEqual(QuickDump.fileTemplate("{original}"), "{original}", "Nothing to take out")
        XCTAssertEqual(QuickDump.fileTemplate("{project}_{original}"), "{original}")
        XCTAssertEqual(QuickDump.fileTemplate("{project}"), "{date}_{seq}", "Falls back rather than an empty name")
        XCTAssertEqual(QuickDump.fileTemplate("Clip_{project}"), "{date}_{seq}")
    }

    func testProjectFolderLevelsDisappear() {
        XCTAssertEqual(QuickDump.folderTemplate("{date}/{project}"), "{date}")
        XCTAssertEqual(QuickDump.folderTemplate("{project}/{date}/{camera}"), "{date}/{camera}")
        XCTAssertEqual(QuickDump.folderTemplate("{year}/{date} {project}"), "{year}/{date}")
        XCTAssertEqual(QuickDump.folderTemplate("{project}"), "")
        XCTAssertEqual(QuickDump.folderTemplate("Clients/{project}/{type}"), "Clients/{type}")
        XCTAssertEqual(QuickDump.folderTemplate(""), "")
        XCTAssertTrue(QuickDump.mentionsProject("{date}/{Project}"))
        XCTAssertTrue(QuickDump.mentionsProject("{shoot}"))
        XCTAssertFalse(QuickDump.mentionsProject("{date}/{camera}"))
        // Every built-in example stays valid with quick dump on.
        for preset in NamingPreset.all {
            let stripped = QuickDump.templates(folder: preset.folder, file: preset.file)
            XCTAssertNotNil(NamingTemplates(folder: stripped.folder, file: stripped.file), preset.name)
            XCTAssertFalse(QuickDump.mentionsProject(stripped.folder + stripped.file), preset.name)
        }
    }

    @MainActor
    func testSettingsUseTheQuickDumpTemplatesAndRememberTheTick() throws {
        let suite = "LodgeTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        XCTAssertFalse(settings.quickDump)
        XCTAssertEqual(settings.effectiveNaming, settings.naming)
        settings.quickDump = true
        XCTAssertEqual(settings.effectiveNaming, NamingTemplates(folder: "{date}", file: "{date}_{seq}"))
        XCTAssertEqual(settings.folderTemplate, NamingTemplates.defaultFolder, "The saved templates don't change")
        XCTAssertFalse(NamingNeeds(settings.effectiveNaming).project)
        XCTAssertTrue(AppSettings(defaults: defaults).quickDump)
    }

    private func clip(_ name: String, minutesAfter minutes: Double = 0) -> Clip {
        var components = DateComponents()
        components.year = 2026; components.month = 10; components.day = 25; components.hour = 9
        let date = Calendar.current.date(from: components)!.addingTimeInterval(minutes * 60)
        return Clip(url: URL(fileURLWithPath: "/Volumes/CARD/DCIM/" + name), relativePath: "DCIM/" + name,
                    size: 1, creationDate: date, modificationDate: date)
    }

    func testNumberingContinuesAfterEarlierQuickDumps() {
        let naming = NamingTemplates(folder: "{date}", file: "{date}_{seq}")!
        let files = [clip("C0010.MP4"), clip("C0011.MP4", minutesAfter: 1), clip("C0011M01.XML", minutesAfter: 1)]
        let plan = OffloadPlanner.plan(files: files, naming: naming, context: NamingContext(), existingNames: {
            $0 == "2026-10-25" ? ["2026-10-25_0001.mp4", "2026-10-25_0002.mp4", "notes.txt"] : []
        })
        XCTAssertEqual(plan.map(\.relativePath), [
            "2026-10-25/2026-10-25_0003.mp4",
            "2026-10-25/2026-10-25_0004.mp4",
            "2026-10-25/Sidecars/2026-10-25_0004M01.xml",
        ])
    }

    @MainActor
    func testModelOffloadsWithoutAProjectName() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lodge-qd-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let settings = AppSettings(defaults: nil)
        settings.destinationPath = folder.path
        settings.skipShortClips = false
        let model = AppModel(settings: settings, ledger: Ledger(fileURL: folder.appendingPathComponent("ledger.json")),
                             cameras: CameraStore(fileURL: nil), destinations: DestinationStore(fileURL: nil),
                             presets: PresetStore(fileURL: nil), startWatching: false)
        let card = CardVolume(url: URL(fileURLWithPath: "/Volumes/CARD"), name: "CARD", uuid: "Q")
        model.installDemo(card: card, session: OffloadSession(card: card, clips: [clip("C0001.MP4")], knownKeys: []))
        let session = try XCTUnwrap(model.session)
        XCTAssertNotNil(model.offloadBlocker, "Normally the project name is required")
        settings.quickDump = true
        XCTAssertNil(model.offloadBlocker, "Quick dump doesn't need one")
        session.projectInput = "Ignored"
        XCTAssertEqual(model.previewPlan(for: session).map(\.relativePath), ["2026-10-25/2026-10-25_0001.mp4"])
        XCTAssertEqual(model.namingContext(for: session).project, "")
    }

    // MARK: Folder tree editing

    func testFolderLevelsMoveInsertAndRemove() {
        let template = "{date}/{project}/{camera}"
        XCTAssertEqual(FolderTemplateEditor.levels(template), ["{date}", "{project}", "{camera}"])
        XCTAssertEqual(FolderTemplateEditor.levels("/{date}//{project}/"), ["{date}", "{project}"])
        XCTAssertEqual(FolderTemplateEditor.move(template, from: 2, to: 0), "{camera}/{date}/{project}")
        XCTAssertEqual(FolderTemplateEditor.move(template, from: 0, to: 9), "{project}/{camera}/{date}")
        XCTAssertEqual(FolderTemplateEditor.move(template, from: 7, to: 0), template)
        XCTAssertEqual(FolderTemplateEditor.insert(.type, into: template), "{date}/{project}/{camera}/{type}")
        XCTAssertEqual(FolderTemplateEditor.insert(.year, into: template, at: 0), "{year}/{date}/{project}/{camera}")
        XCTAssertEqual(FolderTemplateEditor.insert(.date, into: ""), "{date}")
        XCTAssertEqual(FolderTemplateEditor.remove(template, at: 1), "{date}/{camera}")
        XCTAssertEqual(FolderTemplateEditor.remove("{date}", at: 0), "")
    }

    func testDragPayloadsAndDrops() {
        XCTAssertEqual(FolderTemplateEditor.payload("lodge-level:2"), .level(2))
        XCTAssertEqual(FolderTemplateEditor.payload("lodge-token:camera"), .token(.camera))
        XCTAssertNil(FolderTemplateEditor.payload("lodge-token:nope"))
        XCTAssertNil(FolderTemplateEditor.payload("/Users/me/Movies"))
        let template = "{date}/{project}/{camera}"
        // Dropping a level on a row puts it before that row; on the end slot, after the last.
        XCTAssertEqual(FolderTemplateEditor.drop(.level(0), on: 2, in: template), "{project}/{date}/{camera}")
        XCTAssertEqual(FolderTemplateEditor.drop(.level(0), on: 3, in: template), "{project}/{camera}/{date}")
        XCTAssertEqual(FolderTemplateEditor.drop(.level(2), on: 0, in: template), "{camera}/{date}/{project}")
        XCTAssertEqual(FolderTemplateEditor.drop(.level(1), on: 1, in: template), template)
        XCTAssertEqual(FolderTemplateEditor.drop(.level(1), on: 2, in: template), template)
        XCTAssertEqual(FolderTemplateEditor.drop(.token(.type), on: 1, in: template), "{date}/{type}/{project}/{camera}")
        XCTAssertEqual(FolderTemplateEditor.drop(.token(.card), on: 3, in: template), "{date}/{project}/{camera}/{card}")
        for token in FolderTemplateEditor.levelTokens {
            XCTAssertNotNil(NamingTemplates(folder: FolderTemplateEditor.insert(token, into: template), file: "{seq}"), token.rawValue)
        }
    }
}
