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

    /// Set by launching with `-SnapDropDemoSettingsTab <general|destinations|naming|cameras>`.
    static var launchSettingsTab: SettingsTab? {
        UserDefaults.standard.string(forKey: "SnapDropDemoSettingsTab").flatMap(SettingsTab.init(rawValue:))
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

        let session = OffloadSession(card: card, clips: all, knownKeys: ledger.knownKeys)
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
                                          bytesDone: total * 2 / 5, bytesTotal: total),
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
        let readiness: FormatReadiness
        if state == .finished {
            readiness = FormatReadiness(fileCount: all.count, totalBytes: all.reduce(0) { $0 + $1.size },
                                        copiesFolder: (settings.destinationPath ?? "") + "/Coastline")
        } else {
            readiness = FormatReadiness.compute(files: all, volumeIdentity: card.identity,
                                                entries: ledger.entriesByKey(), fileSize: { _ in nil })
        }
        model.installDemo(card: card, session: session, readiness: readiness)
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
