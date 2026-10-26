import Foundation
import AppKit

/// The app's central object. It owns the settings, the card watcher, the ledger,
/// and the offload session that is currently shown (if any).
///
/// `@MainActor` means everything in here runs on the main (UI) thread, which is
/// what SwiftUI expects for objects that drive the UI.
@MainActor
final class AppModel: ObservableObject {
    let settings = AppSettings()
    let watcher = VolumeWatcher()
    let ledger = Ledger()

    /// The card offload currently shown in the sheet. `nil` = no sheet.
    @Published var session: OffloadSession?

    init() {
        // The watcher must ignore the volume the destination folder lives on.
        watcher.destinationPathProvider = { [weak self] in self?.settings.destinationPath }

        watcher.onCardInserted = { [weak self] card in
            self?.openSession(for: card, automatic: true)
        }
        watcher.onCardRemoved = { [weak self] card in
            guard let self, let session = self.session else { return }
            // If the card is pulled out before the user started, just close the sheet.
            if session.card.id == card.id && session.phase == .ready {
                self.session = nil
            }
        }

        // Don't start watching for cards while unit tests are running inside the app.
        if !AppModel.isRunningUnitTests {
            watcher.start()
        }
    }

    /// True when the app was launched as the host for the unit tests.
    static var isRunningUnitTests: Bool {
        NSClassFromString("XCTestCase") != nil
    }

    /// Scans a card for clips (in the background) and shows the offload sheet.
    /// - Parameter automatic: `true` when triggered by inserting a card. Automatic
    ///   sessions are skipped if the card has no clips (e.g. a random USB stick or
    ///   disk image), or if another sheet is already open.
    func openSession(for card: CardVolume, automatic: Bool) {
        if let current = session, current.phase == .running { return }
        if automatic, let current = session, current.phase == .ready { return }

        Task {
            // Scanning touches the disk, so do it off the main thread.
            let clips = await Task.detached(priority: .userInitiated) {
                ClipScanner.scan(volumeURL: card.url)
            }.value

            if automatic && clips.isEmpty { return }
            if let current = self.session, current.phase == .running { return }

            self.session = OffloadSession(card: card, clips: clips, knownKeys: self.ledger.knownKeys)
            NSApp.activate()
        }
    }
}
