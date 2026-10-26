#if DEBUG
import SwiftUI

/// Sample cards, clips and offloads for SwiftUI previews and screenshots.
/// Only compiled into Debug builds. Never touches real settings or the real ledger.
enum DemoData {
    enum State: String {
        case empty, ready, running, finished
    }

    /// Set by launching with `-LodgeDemo YES -LodgeDemoState <state>`.
    static var launchState: State? {
        guard UserDefaults.standard.bool(forKey: "LodgeDemo") else { return nil }
        return State(rawValue: UserDefaults.standard.string(forKey: "LodgeDemoState") ?? "") ?? .ready
    }

    /// Set by launching with `-LodgeDemoSettingsTab <general|appearance|destinations|naming|presets|files|cameras>`.
    static var launchSettingsTab: SettingsTab? {
        UserDefaults.standard.string(forKey: "LodgeDemoSettingsTab").flatMap(SettingsTab.init(rawValue:))
    }

    /// Set by launching with `-LodgeDemoTheme <default|aurora|ocean|…>`.
    static var launchTheme: ThemePalette.ID? {
        UserDefaults.standard.string(forKey: "LodgeDemoTheme").flatMap(ThemePalette.ID.init(rawValue:))
    }

    /// Set by launching with `-LodgeDemoFolderTemplate '{project}_{date}/{camera}'`. Read from the
    /// raw arguments: UserDefaults would parse a value starting with "{" as a property list.
    static var launchFolderTemplate: String? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "-LodgeDemoFolderTemplate"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    /// Set by launching with `-LodgeDemoExpandTree YES` (every folder) or `files` (and the file lists).
    static var launchExpandTree: String? {
        guard UserDefaults.standard.bool(forKey: "LodgeDemo"),
              let value = UserDefaults.standard.string(forKey: "LodgeDemoExpandTree") else { return nil }
        switch value.lowercased() {
        case "yes", "1", "true": return "folders"
        case "files": return "files"
        default: return nil
        }
    }

    /// Made-up folders "already" in the demo destination (it's the real Movies folder, which
    /// the demo shouldn't show): earlier Coastline shoots, a Drone Day and an Exports folder.
    static func existingFolders(root: String) -> FolderListing.Lister {
        let tree: [String: [String]] = [
            "": ["Coastline", "Coastline_2026-10-18", "Drone Day", "Exports"],
            "coastline": ["2026-10-18"],
            "coastline/2026-10-18": ["A7S3"],
            "coastline/2026-10-18/a7s3": [],
            "coastline_2026-10-18": ["A7S3"],
            "coastline_2026-10-18/a7s3": [],
            "drone day": ["2026-09-30"],
            "drone day/2026-09-30": [],
            "exports": [],
        ]
        let base = URL(fileURLWithPath: root).standardizedFileURL.path
        return { url in
            let path = url.standardizedFileURL.path
            guard path == base || path.hasPrefix(base + "/") else { return nil }
            let relative = String(path.dropFirst(base.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return tree[relative.lowercased()]
        }
    }

    /// Set by launching with `-LodgeDemoLayout grid` (and `-LodgeDemoListThumbnails YES`).
    static var launchLayout: MediaLayout? {
        UserDefaults.standard.string(forKey: "LodgeDemoLayout").flatMap(MediaLayout.init(rawValue:))
    }

    /// Screenshots: moves a window to the middle of the highest-resolution screen (a Retina one
    /// when there is one), so captures are 2x even when an external 1x display is the main one.
    @MainActor
    static func centreOnSharpestScreen(_ window: NSWindow) {
        guard let screen = NSScreen.screens.max(by: { $0.backingScaleFactor < $1.backingScaleFactor }) else { return }
        let area = screen.visibleFrame, frame = window.frame
        window.setFrameOrigin(NSPoint(x: area.midX - frame.width / 2, y: area.midY - frame.height / 2))
    }

    /// Quick Look in demo mode: the files don't exist, so preview a picture in the theme's colours
    /// (drawn once into the temporary folder).
    @MainActor
    static func previewImage(for clip: Clip, theme: ResolvedTheme) -> URL? {
        guard MediaPreviewSupport.hasThumbnail(fileName: clip.url.lastPathComponent) else { return nil }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("LodgeDemoPreviews", isDirectory: true)
        let url = folder.appendingPathComponent("\(theme.palette.id.rawValue)-\(theme.isDark ? "dark" : "light")-\(clip.url.deletingPathExtension().lastPathComponent).png")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let t = Double(StableHash.of(clip.url.lastPathComponent) % 1000) / 1000
        let picture = LinearGradient(colors: [theme.placeholder(t), theme.placeholder((t + 0.45).truncatingRemainder(dividingBy: 1))],
                                     startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay {
                Image(systemName: clip.category.symbol)
                    .font(.system(size: 220, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .frame(width: 1600, height: 1000)
        let renderer = ImageRenderer(content: picture)
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return nil }
        try? png.write(to: url)
        return url
    }

    /// Movies (default, in use), an external SSD that isn't plugged in, and Pictures.
    @MainActor
    static func destinationStore() -> DestinationStore {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let movies = FavoriteDestination(name: "Movies", path: home + "/Movies")
        let store = DestinationStore(fileURL: nil, favorites: [
            movies,
            FavoriteDestination(name: "Footage SSD", path: "/Volumes/Footage SSD/Projects"),
            FavoriteDestination(name: "Stills Library", path: home + "/Pictures"),
        ], defaultID: movies.id)
        store.markUsed(movies.id)
        return store
    }

    /// Four presets; "Sony Shoot" is in use. `-LodgeDemoQuickDump YES` switches to "Quick Dump".
    @MainActor
    static func presetStore(cameras: CameraStore) -> PresetStore {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let sony = OffloadPreset(name: "Sony Shoot", destinationPath: home + "/Movies",
                                 folderTemplate: NamingPreset.all[1].folder, fileTemplate: NamingPreset.all[1].file,
                                 cameraID: cameras.cameras[1].id)
        let store = PresetStore(fileURL: nil, presets: [
            sony,
            OffloadPreset(name: "Drone Day", destinationPath: "/Volumes/Footage SSD/Projects",
                          folderTemplate: "{date}/{camera}", fileTemplate: "{date}_{camera}_{seq}",
                          cameraID: cameras.cameras[2].id, shortClipSeconds: 3),
            OffloadPreset(name: "Quick Dump", destinationPath: home + "/Movies",
                          folderTemplate: NamingPreset.all[1].folder, fileTemplate: NamingPreset.all[1].file,
                          skipShortClips: false, quickDump: true),
            OffloadPreset(name: "Client B-Roll", folderTemplate: "Clients/{project}/{date}",
                          fileTemplate: "{project}_{date}_{seq}", shortClipSeconds: 8),
        ])
        store.markActive(sony.id)
        return store
    }

    /// Items a real card would have that Lodge ignores (system files, AppleDouble files).
    static let ignoredItems = [".DS_Store", ".Spotlight-V100", ".Trashes", ".fseventsd",
                               "PRIVATE/M4ROOT/CLIP/._C0007.MP4"]

    @MainActor
    static func cameraStore() -> CameraStore {
        CameraStore(fileURL: nil, cameras: [
            Camera(name: "Sony FX3", code: "FX3"),
            Camera(name: "Sony A7S III", code: "A7S3"),
            Camera(name: "DJI Mini 4 Pro", code: "Mini4"),
            Camera(name: "Zoom H6"),
        ])
    }

    static let card = CardVolume(url: URL(fileURLWithPath: "/Volumes/A7SIII"), name: "A7S III", uuid: "DEMO-CARD")

    /// A mixed card: 24 clips (each with a Sony M01.XML sidecar), RAW photos, a few
    /// WAVs from an audio recorder, the camera's own database file, and three drone clips
    /// with their DJI proxies (.LRF) and telemetry (.SRT).
    static func clips() -> [Clip] {
        var components = DateComponents()
        components.year = 2026; components.month = 10; components.day = 25; components.hour = 9
        let start = Calendar.current.date(from: components) ?? Date()
        var files: [Clip] = []
        func add(_ path: String, size: Int64, at date: Date) {
            files.append(Clip(url: card.url.appendingPathComponent(path), relativePath: path,
                              size: size, creationDate: date, modificationDate: date))
        }
        for index in 1...24 {
            let date = start.addingTimeInterval(Double(index) * 420)
            let name = String(format: "C%04d", index)
            add("PRIVATE/M4ROOT/CLIP/\(name).MP4", size: Int64(600_000_000 + (index * 73_000_000) % 900_000_000), at: date)
            add("PRIVATE/M4ROOT/CLIP/\(name)M01.XML", size: 4_200, at: date)
            if index.isMultiple(of: 2) {
                add(String(format: "DCIM/100MSDCF/DSC%05d.ARW", index / 2), size: 24_500_000, at: date.addingTimeInterval(90))
            }
        }
        for index in 1...3 {
            add(String(format: "ZOOM/ZOOM%04d.WAV", index), size: 310_000_000, at: start.addingTimeInterval(Double(index) * 2_400))
        }
        add("PRIVATE/M4ROOT/MEDIAPRO.XML", size: 18_000, at: start.addingTimeInterval(24 * 420 + 60))
        for index in 1...3 {
            let date = start.addingTimeInterval(24 * 420 + 600 + Double(index) * 300)
            let name = String(format: "DCIM/DJI_001/DJI_%04d", index)
            add(name + ".MP4", size: Int64(1_400_000_000 + index * 210_000_000), at: date)
            add(name + ".LRF", size: Int64(90_000_000 + index * 12_000_000), at: date)
            add(name + ".SRT", size: 64_000, at: date)
        }
        return files
    }

    /// Clip lengths: mostly 0:12–1:40, plus two accidental 2–3 second takes (C0011, C0019).
    static func durations() -> [String: Double] {
        var result: [String: Double] = [:]
        for index in 1...24 {
            let name = String(format: "C%04d", index)
            let seconds: Double
            switch index {
            case 11: seconds = 2.4
            case 19: seconds = 3.1
            default: seconds = Double(12 + (index * 37) % 88) + 0.5
            }
            result["PRIVATE/M4ROOT/CLIP/\(name).MP4"] = seconds
        }
        for index in 1...3 {
            result[String(format: "DCIM/DJI_001/DJI_%04d.MP4", index)] = Double(40 + index * 23)
        }
        return result
    }

    @MainActor
    static func model(state: State) -> AppModel {
        let settings = AppSettings(defaults: nil)
        let ledgerURL = FileManager.default.temporaryDirectory.appendingPathComponent("lodge-demo-ledger.json")
        try? FileManager.default.removeItem(at: ledgerURL)
        let ledger = Ledger(fileURL: ledgerURL)
        let cameras = cameraStore()
        // The demo never runs diskutil: every command "fails", so Format can't erase anything.
        let presets = presetStore(cameras: cameras)
        let model = AppModel(settings: settings, ledger: ledger, cameras: cameras, destinations: destinationStore(),
                             presets: presets, supportPrompt: SupportPromptStore(defaults: nil),
                             formatter: CardFormatter(runner: DemoCommandRunner()), startWatching: false)
        settings.destinationPath = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first?.path
        if let theme = launchTheme { settings.themeID = theme }
        if let layout = launchLayout { settings.mediaLayout = layout }
        settings.showListThumbnails = UserDefaults.standard.bool(forKey: "LodgeDemoListThumbnails")
        model.thumbnails.usesPlaceholders = true
        if let root = settings.destinationPath { model.subfolderLister = existingFolders(root: root) }
        guard state != .empty else { return model }

        settings.apply(NamingPreset.all[1])   // Project / Date / Camera ("Sony Shoot")
        if UserDefaults.standard.bool(forKey: "LodgeDemoQuickDump"),
           let quick = presets.presets.first(where: { $0.quickDump }) {
            settings.apply(quick)
            presets.markActive(quick.id)
        }
        if let folder = launchFolderTemplate,
           NamingTemplates(folder: folder, file: settings.fileTemplate) != nil {
            settings.folderTemplate = folder
        }
        let all = clips()
        let alreadyDone = all.prefix(15)      // the first six clips (with sidecars) and three photos
        for clip in alreadyDone {
            ledger.add(LedgerEntry(
                sourceKey: clip.ledgerKey(volumeIdentity: card.identity),
                cardName: card.name,
                sourceRelativePath: clip.relativePath,
                destinationPath: "/Users/demo/Movies/Coastline/2026-10-25/A7S3/" + clip.url.lastPathComponent,
                size: clip.size,
                sha256: "demo",
                offloadedAt: Date().addingTimeInterval(-86_400)))
        }

        // Three of those copies have gone missing from the destination ("3 missing at destination").
        let entries = ledger.entriesByKey()
        let missingNames: Set<String> = ["C0004.MP4", "C0004M01.XML", "DSC00002.ARW"]
        let sizes = Dictionary(entries.values.map { ($0.destinationPath, $0.size) }, uniquingKeysWith: { a, _ in a })
        let inventory = CardInventory.classify(
            files: all, volumeIdentity: card.identity, entries: entries,
            fileSize: { path in missingNames.contains((path as NSString).lastPathComponent) ? nil : sizes[path] })
        var inventoryWithIgnored = inventory
        inventoryWithIgnored.ignored = ignoredItems
        let session = OffloadSession(card: card, inventory: inventoryWithIgnored, durations: durations())
        session.shortRule = settings.shortClipRule
        session.fileRules = settings.fileRules
        // While copying and when finished, the missing copies are being re-offloaded too.
        if state != .ready { session.reoffloadMode = .missing }
        session.projectInput = "Coastline"
        session.cameraID = cameras.cameras[1].id
        let total = session.newBytes
        let plan = OffloadPlanner.plan(files: session.newClips, naming: settings.effectiveNaming ?? .standard,
                                       context: model.namingContext(for: session), rules: settings.fileRules,
                                       existingNames: { _ in [] })
        // While "copying", the current file is a clip partway down the list.
        let current = plan.indices.first { $0 >= 9 && plan[$0].category == .video } ?? min(9, plan.count - 1)
        switch state {
        case .running:
            session.applyDemo(
                phase: .running,
                progress: OffloadProgress(filesDone: current, filesTotal: plan.count,
                                          currentFile: plan[current].originalName, currentID: plan[current].id,
                                          bytesDone: Int64(Double(total) * demoProgress), bytesTotal: total,
                                          currentFileBytes: plan[current].size * 3 / 5),
                startedAt: Date().addingTimeInterval(-140),
                summary: nil,
                plan: plan,
                verifiedIDs: Set(plan.prefix(current).map(\.id)))
        case .finished:
            session.applyDemo(
                phase: .finished,
                progress: OffloadProgress(filesDone: plan.count, filesTotal: plan.count,
                                          bytesDone: total, bytesTotal: total),
                startedAt: Date().addingTimeInterval(-420),
                summary: OffloadSummary(copied: plan.count, skipped: session.alreadyOffloadedCount, failed: 0),
                plan: plan,
                verifiedIDs: Set(plan.map(\.id)))
        default:
            break
        }
        // Ready to format once everything is offloaded; otherwise "N files not yet offloaded".
        var cardInventory = inventoryWithIgnored
        if state == .finished {
            // Everything but the two skipped short clips (and their sidecars).
            let skipped = session.skippedShort.ids
            cardInventory = CardInventory(new: all.filter { skipped.contains($0.relativePath) },
                                          offloaded: all.filter { !skipped.contains($0.relativePath) },
                                          copiesFolder: (settings.destinationPath ?? "") + "/Coastline",
                                          ignored: ignoredItems)
        }
        model.installDemo(card: card, session: session, inventory: cardInventory)
        if state == .running && UserDefaults.standard.bool(forKey: "LodgeDemoWagonDrive") {
            driveToTheLodge(session: session, plan: plan, current: current, total: total)
        }
        return model
    }

    /// How far the "copying" demo has got: `-LodgeDemoProgress 0.62` (default 0.4).
    static var demoProgress: Double {
        let value = UserDefaults.standard.double(forKey: "LodgeDemoProgress")
        return value > 0 ? min(1, value) : 0.4
    }

    /// `-LodgeDemoWagonDrive YES`: after a second, the "copying" demo runs on to 100 % along the
    /// wagon's slow-down curve and finishes, so the whole arrival plays (for recordings).
    private static func driveToTheLodge(session: OffloadSession, plan: [PlannedFile], current: Int, total: Int64) {
        let start = demoProgress
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            let began = Date()
            while true {
                let t = Date().timeIntervalSince(began) / SlowdownCurve.duration
                let k = min(1, t)
                let fraction = start + (1 - start) * (1 - pow(1 - k, 2.2))
                let index = min(plan.count - 1, current + Int(Double(plan.count - current) * k))
                session.applyDemo(
                    phase: .running,
                    progress: OffloadProgress(filesDone: index, filesTotal: plan.count,
                                              currentFile: plan[index].originalName, currentID: plan[index].id,
                                              bytesDone: Int64(Double(total) * fraction), bytesTotal: total,
                                              currentFileBytes: plan[index].size / 2, isVerifying: k > 0.9),
                    startedAt: began.addingTimeInterval(-140), summary: nil, plan: plan,
                    verifiedIDs: Set(plan.prefix(index).map(\.id)))
                if k >= 1 { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            try? await Task.sleep(for: .seconds(0.6))
            session.applyDemo(
                phase: .finished,
                progress: OffloadProgress(filesDone: plan.count, filesTotal: plan.count, bytesDone: total, bytesTotal: total),
                startedAt: began.addingTimeInterval(-420),
                summary: OffloadSummary(copied: plan.count, skipped: session.alreadyOffloadedCount, failed: 0),
                plan: plan, verifiedIDs: Set(plan.map(\.id)))
        }
    }
}

/// Stands in for diskutil in demo mode: every command fails.
struct DemoCommandRunner: CommandRunning {
    func run(_ executable: String, _ arguments: [String]) async throws -> CommandResult {
        CommandResult(status: 1, output: Data(), errorOutput: "Demo mode")
    }
}

extension View {
    /// Previews: supply a demo model and all its shared objects.
    func demoEnvironment(_ model: AppModel) -> some View {
        appEnvironment(model)
    }
}
/// Screenshots are taken with the app left in the background (it never takes focus), where
/// switches, segments and the title bar turn grey. In demo mode, draw every window as if it
/// were the active one so the screenshots show the real colours. Debug builds only.
extension DemoData {
    static func drawWindowsAsActive() {
        let alwaysActive: @convention(block) (AnyObject) -> Bool = { _ in true }
        let implementation = imp_implementationWithBlock(alwaysActive)
        for name in ["isKeyWindow", "isMainWindow", "_hasActiveAppearance",
                     "_hasActiveAppearanceIgnoringKeyFocus", "hasKeyAppearance", "hasMainAppearance"] {
            if let method = class_getInstanceMethod(NSWindow.self, NSSelectorFromString(name)) {
                method_setImplementation(method, implementation)
            }
        }
    }
}
#endif
