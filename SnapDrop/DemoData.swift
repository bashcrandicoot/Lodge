#if DEBUG
import SwiftUI

/// Sample cards, clips and offloads for SwiftUI previews and screenshots.
/// Only compiled into Debug builds. Never touches real settings or the real ledger.
enum DemoData {
    enum State: String {
        case empty, ready, running, finished
    }

    /// Set by launching with `-SnapDropDemo YES -SnapDropDemoState <state>`.
    static var launchState: State? {
        guard UserDefaults.standard.bool(forKey: "SnapDropDemo") else { return nil }
        return State(rawValue: UserDefaults.standard.string(forKey: "SnapDropDemoState") ?? "") ?? .ready
    }

    /// Set by launching with `-SnapDropDemoSettingsTab <general|appearance|destinations|naming|cameras>`.
    static var launchSettingsTab: SettingsTab? {
        UserDefaults.standard.string(forKey: "SnapDropDemoSettingsTab").flatMap(SettingsTab.init(rawValue:))
    }

    /// Set by launching with `-SnapDropDemoTheme <comet|aurora|ocean|…>`.
    static var launchTheme: ThemePalette.ID? {
        UserDefaults.standard.string(forKey: "SnapDropDemoTheme").flatMap(ThemePalette.ID.init(rawValue:))
    }

    /// Set by launching with `-SnapDropDemoLayout grid` (and `-SnapDropDemoListThumbnails YES`).
    static var launchLayout: MediaLayout? {
        UserDefaults.standard.string(forKey: "SnapDropDemoLayout").flatMap(MediaLayout.init(rawValue:))
    }

    /// Quick Look in demo mode: the files don't exist, so preview a picture in the theme's colours
    /// (drawn once into the temporary folder).
    @MainActor
    static func previewImage(for clip: Clip, theme: ResolvedTheme) -> URL? {
        guard MediaPreviewSupport.hasThumbnail(fileName: clip.url.lastPathComponent) else { return nil }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("SnapDropDemoPreviews", isDirectory: true)
        let url = folder.appendingPathComponent("\(theme.palette.id.rawValue)-\(clip.url.deletingPathExtension().lastPathComponent).png")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let t = Double(StableHash.of(clip.url.lastPathComponent) % 1000) / 1000
        let picture = LinearGradient(colors: [theme.sweep(t), theme.sweep((t + 0.45).truncatingRemainder(dividingBy: 1))],
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
    /// WAVs from an audio recorder and the camera's own database file.
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
        return result
    }

    @MainActor
    static func model(state: State) -> AppModel {
        let settings = AppSettings(defaults: nil)
        let ledgerURL = FileManager.default.temporaryDirectory.appendingPathComponent("snapdrop-demo-ledger.json")
        try? FileManager.default.removeItem(at: ledgerURL)
        let ledger = Ledger(fileURL: ledgerURL)
        let cameras = cameraStore()
        // The demo never runs diskutil: every command "fails", so Format can't erase anything.
        let model = AppModel(settings: settings, ledger: ledger, cameras: cameras, destinations: destinationStore(),
                             formatter: CardFormatter(runner: DemoCommandRunner()), startWatching: false)
        settings.destinationPath = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first?.path
        if let theme = launchTheme { settings.themeID = theme }
        if let layout = launchLayout { settings.mediaLayout = layout }
        settings.showListThumbnails = UserDefaults.standard.bool(forKey: "SnapDropDemoListThumbnails")
        model.thumbnails.usesPlaceholders = true
        guard state != .empty else { return model }

        settings.apply(NamingPreset.all[1])   // Project / Date / Camera
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
        let session = OffloadSession(card: card, inventory: inventory, durations: durations())
        session.shortRule = settings.shortClipRule
        // While copying and when finished, the missing copies are being re-offloaded too.
        if state != .ready { session.reoffloadMode = .missing }
        session.projectInput = "Coastline"
        session.cameraID = cameras.cameras[1].id
        let total = session.newBytes
        let plan = OffloadPlanner.plan(files: session.newClips, naming: settings.naming ?? .standard,
                                       context: model.namingContext(for: session), existingNames: { _ in [] })
        // While "copying", the current file is a clip partway down the list.
        let current = plan.indices.first { $0 >= 9 && plan[$0].category == .video } ?? min(9, plan.count - 1)
        switch state {
        case .running:
            session.applyDemo(
                phase: .running,
                progress: OffloadProgress(filesDone: current, filesTotal: plan.count,
                                          currentFile: plan[current].originalName, currentID: plan[current].id,
                                          bytesDone: total * 2 / 5, bytesTotal: total,
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
        var cardInventory = inventory
        if state == .finished {
            // Everything but the two skipped short clips (and their sidecars).
            let skipped = session.skippedShort.ids
            cardInventory = CardInventory(new: all.filter { skipped.contains($0.relativePath) },
                                          offloaded: all.filter { !skipped.contains($0.relativePath) },
                                          copiesFolder: (settings.destinationPath ?? "") + "/Coastline")
        }
        model.installDemo(card: card, session: session, inventory: cardInventory)
        return model
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
#endif
