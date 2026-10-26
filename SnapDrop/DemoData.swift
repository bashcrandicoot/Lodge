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

    static let card = CardVolume(url: URL(fileURLWithPath: "/Volumes/A7SIII"), name: "A7S III", uuid: "DEMO-CARD")

    static func clips() -> [Clip] {
        var components = DateComponents()
        components.year = 2026; components.month = 10; components.day = 25; components.hour = 9
        let start = Calendar.current.date(from: components) ?? Date()
        return (1...24).map { index in
            let date = start.addingTimeInterval(Double(index) * 420)
            let name = String(format: "C%04d.MP4", index)
            return Clip(
                url: card.url.appendingPathComponent("PRIVATE/M4ROOT/CLIP/\(name)"),
                relativePath: "PRIVATE/M4ROOT/CLIP/\(name)",
                size: Int64(600_000_000 + (index * 73_000_000) % 900_000_000),
                creationDate: date,
                modificationDate: date)
        }
    }

    @MainActor
    static func model(state: State) -> AppModel {
        let settings = AppSettings(defaults: nil)
        let ledgerURL = FileManager.default.temporaryDirectory.appendingPathComponent("snapdrop-demo-ledger.json")
        try? FileManager.default.removeItem(at: ledgerURL)
        let ledger = Ledger(fileURL: ledgerURL)
        let model = AppModel(settings: settings, ledger: ledger, startWatching: false)
        guard state != .empty else { return model }

        settings.destinationPath = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first?.path
        let all = clips()
        let alreadyDone = all.prefix(6)
        for clip in alreadyDone {
            ledger.add(LedgerEntry(
                sourceKey: clip.ledgerKey(volumeIdentity: card.identity),
                cardName: card.name,
                sourceRelativePath: clip.relativePath,
                destinationPath: "/Users/demo/Movies/2026-10-24/SunsetHike/2026-10-24_SunsetHike_000\(ledger.entries.count + 1).mp4",
                size: clip.size,
                sha256: "demo",
                offloadedAt: Date().addingTimeInterval(-86_400)))
        }

        let session = OffloadSession(card: card, clips: all, knownKeys: ledger.knownKeys)
        session.projectInput = "Coastline"
        session.shootNameInput = "Beach Shoot"
        let total = session.newBytes
        let plan = OffloadPlanner.plan(files: session.newClips, naming: settings.naming ?? .standard,
                                       context: model.namingContext(for: session), existingNames: { _ in [] })
        switch state {
        case .running:
            session.applyDemo(
                phase: .running,
                progress: OffloadProgress(filesDone: 7, filesTotal: session.newClips.count,
                                          currentFile: "C0014.MP4", bytesDone: total * 2 / 5, bytesTotal: total),
                startedAt: Date().addingTimeInterval(-140),
                summary: nil,
                plan: plan,
                verifiedIDs: Set(plan.prefix(7).map(\.id)))
        case .finished:
            session.applyDemo(
                phase: .finished,
                progress: OffloadProgress(filesDone: session.newClips.count, filesTotal: session.newClips.count,
                                          bytesDone: total, bytesTotal: total),
                startedAt: Date().addingTimeInterval(-420),
                summary: OffloadSummary(copied: session.newClips.count, skipped: 6, failed: 0),
                plan: plan,
                verifiedIDs: Set(plan.map(\.id)))
        default:
            break
        }
        model.installDemo(card: card, session: session)
        return model
    }
}

extension View {
    /// Previews: supply a demo model and all its shared objects.
    func demoEnvironment(_ model: AppModel) -> some View {
        appEnvironment(model)
    }
}
#endif
