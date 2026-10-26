import XCTest
@testable import SnapDrop

final class NamingTemplateTests: XCTestCase {
    /// 2026-10-25 14:30:05 local time.
    private var sampleDate: Date {
        var components = DateComponents()
        components.year = 2026; components.month = 10; components.day = 25
        components.hour = 14; components.minute = 30; components.second = 5
        return Calendar.current.date(from: components)!
    }

    private func file(_ path: String, minutesAfter minutes: Double = 0) -> Clip {
        let date = sampleDate.addingTimeInterval(minutes * 60)
        return Clip(url: URL(fileURLWithPath: "/Volumes/CARD/" + path), relativePath: path,
                    size: 10, creationDate: date, modificationDate: date)
    }

    private func errors(_ raw: String, _ kind: NamingTemplate.Kind) -> [String] {
        NamingTemplate.parse(raw, kind: kind).issues.filter { $0.severity == .error }.map(\.message)
    }

    private func warnings(_ raw: String, _ kind: NamingTemplate.Kind) -> [String] {
        NamingTemplate.parse(raw, kind: kind).issues.filter { $0.severity == .warning }.map(\.message)
    }

    // MARK: Parsing and validation

    func testDefaultsParseCleanly() {
        XCTAssertTrue(NamingTemplate.parse(NamingTemplates.defaultFolder, kind: .folder).issues.isEmpty)
        XCTAssertTrue(NamingTemplate.parse(NamingTemplates.defaultFile, kind: .file).issues.isEmpty)
        XCTAssertEqual(NamingTemplate.parse("{date}/{project}", kind: .folder).template?.components.count, 2)
        XCTAssertEqual(NamingTemplate.parse("", kind: .folder).template?.components.count, 0, "Empty folder = flat")
        XCTAssertEqual(NamingTemplates.standard.file.tokens, [.date, .project, .seq])
    }

    func testUnknownTokens() {
        XCTAssertEqual(errors("{date}_{foo}", .file), ["{foo} isn’t a known token."])
        XCTAssertEqual(errors("{Date}_{PROJECT}_{Seq}", .file), [], "Token names ignore case")
        XCTAssertEqual(errors("{}_{seq}", .file), ["“{}” is an empty token. Pick one from the list below."])
        XCTAssertEqual(errors("{date_{seq}", .file), ["A “{” is missing its closing “}”."])
        XCTAssertEqual(errors("{date}_{seq", .file), ["A “{” is missing its closing “}”."])
        XCTAssertEqual(errors("date}_{seq}", .file), ["There’s a “}” without a matching “{”."])
    }

    func testIllegalCharacters() {
        XCTAssertEqual(errors("{date}:{seq}", .file), ["“:” isn’t allowed in file or folder names."])
        XCTAssertEqual(errors("{date}/{project}:x", .folder), ["“:” isn’t allowed in file or folder names."])
        XCTAssertEqual(errors("{date}?{seq}", .file), ["“?” isn’t allowed in file or folder names."])
        XCTAssertEqual(errors("{date}/{seq}", .file),
                       ["“/” isn’t allowed in the file name. Use the folder structure for folders."])
        XCTAssertEqual(errors("{date}\t{seq}", .file), ["Names can’t contain tabs or line breaks."])
        XCTAssertEqual(errors(".{seq}", .file), ["Names can’t start with “.” — the file or folder would be hidden."])
        XCTAssertEqual(errors("{date}/.cache", .folder), ["Names can’t start with “.” — the file or folder would be hidden."])
        XCTAssertEqual(errors("{date} - {project} (A)_{seq}", .file), [], "Spaces, dashes and brackets are fine")
    }

    func testEmptyComponents() {
        let message = "A folder level is empty. Check for “//” or a “/” at the start or end."
        XCTAssertEqual(errors("{date}//{project}", .folder), [message])
        XCTAssertEqual(errors("/{date}", .folder), [message])
        XCTAssertEqual(errors("{date}/", .folder), [message])
        XCTAssertEqual(errors("{date}/ /{project}", .folder), [message])
        XCTAssertEqual(errors("", .file), ["The file name can’t be empty."])
        XCTAssertEqual(errors("   ", .file), ["The file name can’t be empty."])
        XCTAssertNil(NamingTemplates(folder: "{date}//x", file: "{seq}"))
    }

    func testSequencePadding() {
        let parsed = NamingTemplate.parse("{date}_{seq:3}", kind: .file)
        XCTAssertNotNil(parsed.template)
        XCTAssertEqual(parsed.template?.components.first?.last, .token(.seq, padding: 3))
        XCTAssertEqual(errors("{seq:0}", .file), ["{seq:…} needs a number from 1 to 9, like {seq:3}."])
        XCTAssertEqual(errors("{seq:10}", .file), ["{seq:…} needs a number from 1 to 9, like {seq:3}."])
        XCTAssertEqual(errors("{seq:x}", .file), ["{seq:…} needs a number from 1 to 9, like {seq:3}."])
        XCTAssertEqual(errors("{date:3}_{seq}", .file), ["Only {seq} can take a number, like {seq:3}."])
        XCTAssertEqual(errors("{seq}_{seq:2}", .file), ["Use {seq} only once."])
        XCTAssertEqual(errors("{date}/{seq}", .folder), ["{seq} only works in the file name."])

        let template = NamingTemplates(folder: "", file: "{project}_{seq:3}")!
        let plan = OffloadPlanner.plan(files: [file("A.MP4")], naming: template,
                                       context: NamingContext(project: "S"), existingNames: { _ in [] })
        XCTAssertEqual(plan.map(\.fileName), ["S_001.mp4"])
    }

    func testWarningWithoutSeqOrOriginal() {
        let message = "Without {seq} or {original}, files that would get the same name get “_2”, “_3”… added."
        XCTAssertEqual(warnings("{date}_{project}", .file), [message])
        XCTAssertEqual(warnings("{date}_{original}", .file), [])
        XCTAssertEqual(warnings("{date}_{seq}", .file), [])
        XCTAssertNotNil(NamingTemplate.parse("{date}_{project}", kind: .file).template, "A warning doesn't block")
    }

    func testIssuesAreReportedOnce() {
        XCTAssertEqual(errors("{a}:{a}:", .file).count, 2)
    }

    // MARK: Rendering

    func testTokenValues() {
        let clip = file("DCIM/100MSDCF/DSC00012.ARW")
        let context = NamingContext(project: "Doc", camera: "FX3", card: "CardA")
        func value(_ token: TemplateToken, padding: Int? = nil, sequence: Int? = nil) -> String {
            TemplateRenderer.value(of: token, padding: padding, file: clip, context: context, sequence: sequence)
        }
        XCTAssertEqual(value(.project), "Doc")
        XCTAssertEqual(value(.camera), "FX3")
        XCTAssertEqual(value(.card), "CardA")
        XCTAssertEqual(value(.date), "2026-10-25")
        XCTAssertEqual(value(.year), "2026")
        XCTAssertEqual(value(.month), "10")
        XCTAssertEqual(value(.day), "25")
        XCTAssertEqual(value(.time), "143005")
        XCTAssertEqual(value(.type), "Photo")
        XCTAssertEqual(value(.original), "DSC00012")
        XCTAssertEqual(value(.ext), "arw")
        XCTAssertEqual(value(.seq, sequence: 7), "0007")
        XCTAssertEqual(value(.seq, padding: 2, sequence: 7), "07")
        XCTAssertEqual(value(.seq, padding: 2, sequence: 123), "123")
    }

    func testRenderingSanitizesValues() {
        let naming = NamingTemplates(folder: "{project}/{camera}", file: "{card}_{original}")!
        let context = NamingContext(project: "Bad:Name/Here", camera: "..hidden", card: " A*B?C ")
        let plan = OffloadPlanner.plan(files: [file("DCIM/we:ird.MP4")], naming: naming, context: context,
                                       existingNames: { _ in [] })
        XCTAssertEqual(plan.first?.folder, "Bad-Name-Here/hidden")
        XCTAssertEqual(plan.first?.fileName, "A-B-C_we-ird.mp4")
    }

    func testEmptyValuesFallBackToUntitled() {
        let naming = NamingTemplates(folder: "{project}", file: "{camera}")!
        let plan = OffloadPlanner.plan(files: [file("A.MP4")], naming: naming, context: NamingContext(),
                                       existingNames: { _ in [] })
        XCTAssertEqual(plan.first?.relativePath, "Untitled/Untitled.mp4")
    }

    func testLongNamesAreShortened() {
        let naming = NamingTemplates(folder: "", file: "{project}_{seq}")!
        let long = String(repeating: "x", count: 400)
        let plan = OffloadPlanner.plan(files: [file("A.MP4"), file("B.MP4", minutesAfter: 1)], naming: naming,
                                       context: NamingContext(project: long), existingNames: { _ in [] })
        XCTAssertEqual(plan.count, 2)
        XCTAssertEqual(Set(plan.map(\.fileName)).count, 2, "Shortened names still never collide")
        XCTAssertTrue(plan.allSatisfy { $0.fileName.count <= TemplateRenderer.maxComponentLength + 10 })
    }

    func testExtensionIsAlwaysLowercasedAndAppended() {
        let naming = NamingTemplates(folder: "", file: "{original}")!
        let plan = OffloadPlanner.plan(files: [file("C0001.MP4"), file("README", minutesAfter: 1)], naming: naming,
                                       context: NamingContext(), existingNames: { _ in [] })
        XCTAssertEqual(plan.map(\.fileName), ["C0001.mp4", "README"])
    }

    func testEveryPreset() {
        let context = NamingContext(project: "Doc", camera: "FX3", card: "CardA")
        let expected: [String: [String]] = [
            "Date / Project": ["2026-10-25/Doc/2026-10-25_Doc_0001.mp4", "2026-10-25/Doc/2026-10-25_Doc_0002.arw"],
            "Project / Date / Camera": ["Doc/2026-10-25/FX3/2026-10-25_Doc_FX3_0001.mp4",
                                        "Doc/2026-10-25/FX3/2026-10-25_Doc_FX3_0002.arw"],
            "Project / Type / Date": ["Doc/Video/2026-10-25/2026-10-25_Doc_0001.mp4",
                                      "Doc/Photo/2026-10-25/2026-10-25_Doc_0001.arw"],
            "Year / Month / Day": ["2026/10/25/2026-10-25_Doc_0001.mp4", "2026/10/25/2026-10-25_Doc_0002.arw"],
            "Date / Project, Original Names": ["2026-10-25/Doc/C0001.mp4", "2026-10-25/Doc/DSC00012.arw"],
            "Flat": ["2026-10-25_Doc_0001.mp4", "2026-10-25_Doc_0002.arw"],
        ]
        XCTAssertEqual(Set(NamingPreset.all.map(\.name)), Set(expected.keys))
        for preset in NamingPreset.all {
            XCTAssertTrue(NamingTemplate.parse(preset.folder, kind: .folder).issues.isEmpty, preset.name)
            XCTAssertTrue(NamingTemplate.parse(preset.file, kind: .file).issues.isEmpty, preset.name)
            guard let naming = NamingTemplates(folder: preset.folder, file: preset.file) else {
                XCTFail(preset.name)
                continue
            }
            let plan = OffloadPlanner.plan(
                files: [file("PRIVATE/M4ROOT/CLIP/C0001.MP4"), file("DCIM/100MSDCF/DSC00012.ARW", minutesAfter: 1)],
                naming: naming, context: context, existingNames: { _ in [] })
            XCTAssertEqual(plan.map(\.relativePath), expected[preset.name], preset.name)
        }
    }

    // MARK: Collisions and numbering

    func testCollisionSuffixWithoutSeq() {
        let naming = NamingTemplates(folder: "", file: "{original}")!
        let files = [file("DCIM/100/C0001.MP4"), file("DCIM/101/C0001.MP4", minutesAfter: 1),
                     file("DCIM/102/c0001.mp4", minutesAfter: 2)]
        let plan = OffloadPlanner.plan(files: files, naming: naming, context: NamingContext(),
                                       existingNames: { _ in ["C0001.mp4"] })
        XCTAssertEqual(plan.map(\.fileName), ["C0001_2.mp4", "C0001_3.mp4", "c0001_4.mp4"])

        let projectOnly = NamingTemplates(folder: "", file: "{date}_{project}")!
        let named = OffloadPlanner.plan(files: Array(files.prefix(2)), naming: projectOnly,
                                        context: NamingContext(project: "S"), existingNames: { _ in [] })
        XCTAssertEqual(named.map(\.fileName), ["2026-10-25_S.mp4", "2026-10-25_S_2.mp4"])
    }

    func testSequenceContinuesAfterHighestMatchingFile() {
        let existing = [
            "2026-10-25_Trip_0007.MP4",          // counts (case-insensitive)
            "2026-10-25_trip_0003.mov",          // counts
            "2026-10-25_Trip_0012.mov.snapdrop-partial", // an unfinished copy still reserves its number
            "2026-10-25_TripB_0099.mp4",         // different project, ignored
            "notes.txt",
        ]
        let plan = OffloadPlanner.plan(files: [file("A.MP4"), file("B.MP4", minutesAfter: 1)], naming: .standard,
                                       context: NamingContext(project: "Trip"), existingNames: { _ in existing })
        XCTAssertEqual(plan.map(\.fileName), ["2026-10-25_Trip_0013.mp4", "2026-10-25_Trip_0014.mp4"])
    }

    func testSequenceOnlyTemplateIgnoresUnrelatedNumbers() {
        let naming = NamingTemplates(folder: "", file: "{seq}")!
        let plan = OffloadPlanner.plan(files: [file("A.MP4")], naming: naming, context: NamingContext(),
                                       existingNames: { _ in ["2026-10-25_Other.mp4", "0004.mov"] })
        XCTAssertEqual(plan.map(\.fileName), ["0005.mp4"])
    }

    func testSequenceWithTextAfterIt() {
        let naming = NamingTemplates(folder: "", file: "{date}_{seq}_{original}")!
        let plan = OffloadPlanner.plan(files: [file("C0001.MP4")], naming: naming, context: NamingContext(),
                                       existingNames: { _ in ["2026-10-25_0007_C0099.mp4"] })
        XCTAssertEqual(plan.map(\.fileName), ["2026-10-25_0008_C0001.mp4"])
    }

    func testNumbersAreCountedPerFolder() {
        let naming = NamingTemplates(folder: "{type}", file: "{project}_{seq}")!
        let files = [file("A.MP4"), file("B.JPG", minutesAfter: 1), file("C.MP4", minutesAfter: 2)]
        let plan = OffloadPlanner.plan(files: files, naming: naming, context: NamingContext(project: "S"),
                                       existingNames: { $0 == "Video" ? ["S_0002.mp4"] : [] })
        XCTAssertEqual(plan.map(\.relativePath), ["Video/S_0003.mp4", "Photo/S_0001.jpg", "Video/S_0004.mp4"])
    }

    func testFreeURLNeverOverwrites() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("snapdrop-free-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let target = folder.appendingPathComponent("A.mp4")
        XCTAssertEqual(OffloadPlanner.freeURL(for: target), target)
        FileManager.default.createFile(atPath: target.path, contents: Data())
        XCTAssertEqual(OffloadPlanner.freeURL(for: target).lastPathComponent, "A_2.mp4")
        FileManager.default.createFile(atPath: folder.appendingPathComponent("A_2.mp4.snapdrop-partial").path, contents: Data())
        XCTAssertEqual(OffloadPlanner.freeURL(for: target).lastPathComponent, "A_3.mp4")
    }

    // MARK: End to end

    func testCustomTemplateOffloadMatchesPreview() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("snapdrop-naming-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let card = root.appendingPathComponent("Card/DCIM/100")
        let destination = root.appendingPathComponent("Dest")
        try FileManager.default.createDirectory(at: card, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination.appendingPathComponent("Doc/Video"), withIntermediateDirectories: true)
        try Data("old".utf8).write(to: destination.appendingPathComponent("Doc/Video/Doc_005.mp4"))
        for (index, name) in ["B.MP4", "A.MOV", "C.mp4"].enumerated() {
            let url = card.appendingPathComponent(name)
            try Data(name.utf8).write(to: url)
            let date = sampleDate.addingTimeInterval(Double(index))
            try FileManager.default.setAttributes([.creationDate: date, .modificationDate: date], ofItemAtPath: url.path)
        }
        let clips = ClipScanner.scan(volumeURL: root.appendingPathComponent("Card"))
        XCTAssertEqual(clips.count, 3)

        let naming = NamingTemplates(folder: "{project}/{type}", file: "{project}_{seq:3}")!
        let context = NamingContext(project: "Doc")
        let preview = OffloadPlanner.plan(files: clips, naming: naming, context: context,
                                          existingNames: OffloadPlanner.diskLister(root: destination))
        XCTAssertEqual(preview.map(\.relativePath), ["Doc/Video/Doc_006.mp4", "Doc/Video/Doc_007.mov", "Doc/Video/Doc_008.mp4"])
        XCTAssertEqual(preview.map(\.originalName), ["B.MP4", "A.MOV", "C.mp4"])

        let job = OffloadJob(card: CardVolume(url: root.appendingPathComponent("Card"), name: "Card", uuid: "U"),
                             plan: preview, destination: destination, alreadyOffloaded: 0)
        let summary = await Offloader.run(job: job, progress: { _ in }, record: { _ in })
        XCTAssertEqual(summary.copied, 3)
        XCTAssertEqual(summary.failed, 0)
        for item in preview {
            let copied = destination.appendingPathComponent(item.relativePath)
            XCTAssertEqual(try Data(contentsOf: copied), Data(item.originalName.utf8), item.relativePath)
        }
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("Doc/Video/Doc_005.mp4")), Data("old".utf8))
    }

    // MARK: Settings

    @MainActor
    func testSettingsPersistTemplatesAndRecentProjects() throws {
        let suite = "SnapDropTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.folderTemplate, "{date}/{project}")
        XCTAssertEqual(settings.fileTemplate, "{date}_{project}_{seq}")
        settings.apply(NamingPreset.all[1])
        for name in ["One", "Two", "one", "Three", "Four", "Five", "Six", "Seven", "  "] {
            settings.rememberProject(name)
        }

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.folderTemplate, "{project}/{date}/{camera}")
        XCTAssertEqual(reloaded.fileTemplate, "{date}_{project}_{camera}_{seq}")
        XCTAssertEqual(reloaded.lastProject, "Seven")
        XCTAssertEqual(reloaded.recentProjects, ["Seven", "Six", "Five", "Four", "Three", "one"])
        reloaded.fileTemplate = "{date}:{seq}"
        XCTAssertNil(reloaded.naming)
        XCTAssertFalse(reloaded.fileIssues.isEmpty)
    }

    // MARK: {shoot} merged into {project}

    func testShootIsASilentAliasForProject() {
        XCTAssertFalse(TemplateToken.allCases.map(\.rawValue).contains("shoot"), "No chip for {shoot}")
        let old = NamingTemplates(folder: "{date}/{shoot}", file: "{date}_{SHOOT}_{seq}")
        XCTAssertNotNil(old, "Old templates still parse")
        XCTAssertEqual(old?.folder.tokens, [.date, .project])
        XCTAssertEqual(NamingNeeds(old), NamingNeeds(project: true))
        XCTAssertEqual(errors("{ Shoot }_{seq}", .file), [])
        XCTAssertEqual(errors("{shoot:3}", .file), ["Only {seq} can take a number, like {seq:3}."])
        let plan = OffloadPlanner.plan(files: [file("C0001.MP4")], naming: old!,
                                       context: NamingContext(project: "Doc"), existingNames: { _ in [] })
        XCTAssertEqual(plan.map(\.relativePath), ["2026-10-25/Doc/2026-10-25_Doc_0001.mp4"])
    }

    func testMigrationReplacesShootAndMergesDuplicates() {
        func folder(_ raw: String) -> String { TemplateMigration.migrate(raw, kind: .folder) }
        func name(_ raw: String) -> String { TemplateMigration.migrate(raw, kind: .file) }
        XCTAssertEqual(folder("{date}/{shoot}"), "{date}/{project}")
        XCTAssertEqual(folder("{project}/{shoot}"), "{project}")
        XCTAssertEqual(folder("{project}/{date}/{shoot}"), "{project}/{date}/{project}", "Not side by side: left alone")
        XCTAssertEqual(folder("{date}/{project}_{Shoot}"), "{date}/{project}")
        XCTAssertEqual(name("{date}_{shoot}_{seq}"), "{date}_{project}_{seq}")
        XCTAssertEqual(name("{date}_{project}_{shoot}"), "{date}_{project}")
        XCTAssertEqual(name("{date}_{project}_{shoot}_{seq}"), "{date}_{project}_{seq}")
        XCTAssertEqual(name("{project}-{ shoot }-{seq}"), "{project}-{seq}")
        XCTAssertEqual(name("{project} - {shoot}_{seq}"), "{project} - {project}_{seq}", "Only trivial joins are merged")
        // Templates without {shoot} are never touched, even with a doubled {project}.
        XCTAssertEqual(name("{project}_{project}_{seq}"), "{project}_{project}_{seq}")
        XCTAssertEqual(folder("{project}/{project}"), "{project}/{project}")
        XCTAssertEqual(folder(""), "")
    }

    @MainActor
    func testSavedShootTemplatesAreMigratedOnLaunch() throws {
        let suite = "SnapDropTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("{project}/{shoot}", forKey: "folderTemplate")
        defaults.set("{date}_{project}_{shoot}_{seq}", forKey: "fileTemplate")

        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.folderTemplate, "{project}")
        XCTAssertEqual(settings.fileTemplate, "{date}_{project}_{seq}")
        XCTAssertEqual(defaults.string(forKey: "folderTemplate"), "{project}", "Saved right away")
        XCTAssertEqual(defaults.string(forKey: "fileTemplate"), "{date}_{project}_{seq}")
        XCTAssertEqual(AppSettings(defaults: defaults).folderTemplate, "{project}")
    }

    func testPresetsUseProjectOnce() {
        XCTAssertEqual(NamingPreset.all.first?.folder, NamingTemplates.defaultFolder)
        XCTAssertEqual(NamingPreset.all.first?.file, NamingTemplates.defaultFile)
        for preset in NamingPreset.all {
            for template in [preset.folder, preset.file] {
                XCTAssertLessThanOrEqual(template.components(separatedBy: "{project}").count - 1, 1, preset.name)
                XCTAssertFalse(template.contains("shoot"), preset.name)
            }
        }
    }
}
