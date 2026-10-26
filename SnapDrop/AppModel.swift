import Foundation
import AppKit
import Combine

/// The app's central object. It owns the settings, the card watcher, the ledger,
/// which card is selected, and that card's offload session.
///
/// `@MainActor` means everything in here runs on the main (UI) thread, which is
/// what SwiftUI expects for objects that drive the UI.
@MainActor
final class AppModel: ObservableObject {
    let settings: AppSettings
    let watcher: VolumeWatcher
    let ledger: Ledger

    /// The card shown in the funnel (its mount path).
    @Published private(set) var selectedCardID: String?
    /// The selected card's clips and offload state. `nil` while scanning / no card.
    @Published private(set) var session: OffloadSession? {
        didSet { forwardChanges(from: session) }
    }
    @Published private(set) var isScanning = false
    @Published var showingRecent = false
    @Published private(set) var isEjecting = false
    @Published var ejectError: String?

    private var sessionObserver: AnyCancellable?

    init(settings: AppSettings? = nil, ledger: Ledger? = nil, startWatching: Bool = true) {
        self.settings = settings ?? AppSettings()
        self.ledger = ledger ?? Ledger()
        self.watcher = VolumeWatcher()

        // The watcher must ignore the volume the destination folder lives on.
        watcher.destinationPathProvider = { [weak self] in self?.settings.destinationPath }
        watcher.onCardInserted = { [weak self] card in self?.cardInserted(card) }
        watcher.onCardRemoved = { [weak self] card in self?.cardRemoved(card) }

        // Don't watch for cards while unit tests run inside the app.
        if startWatching && !AppModel.isRunningUnitTests {
            watcher.start()
        }
    }

    /// True when the app was launched as the host for the unit tests.
    static var isRunningUnitTests: Bool {
        NSClassFromString("XCTestCase") != nil
    }

    /// True while clips are being copied. Card switching is locked during that time.
    var isBusy: Bool { session?.phase == .running }

    var selectedCard: CardVolume? {
        watcher.cards.first { $0.id == selectedCardID } ?? session?.card
    }

    // MARK: Cards

    /// A card was plugged in: fill the funnel with it and bring the window forward.
    private func cardInserted(_ card: CardVolume) {
        guard !isBusy else { return }
        select(card)
        bringWindowForward()
    }

    private func cardRemoved(_ card: CardVolume) {
        guard selectedCardID == card.id else { return }
        if let current = session, current.card.id == card.id, current.phase != .ready {
            // Keep the progress/summary visible; just note the card is gone.
            current.cardRemoved = true
            return
        }
        clearSelection()
    }

    /// Shows `card` in the funnel and scans it for clips in the background.
    func select(_ card: CardVolume) {
        guard !isBusy else { return }
        selectedCardID = card.id
        session = nil
        isScanning = true
        Task {
            let clips = await Task.detached(priority: .userInitiated) {
                ClipScanner.scan(volumeURL: card.url)
            }.value
            // The user may have picked a different card while we were scanning.
            guard self.selectedCardID == card.id else { return }
            self.isScanning = false
            self.install(OffloadSession(card: card, clips: clips, knownKeys: self.ledger.knownKeys))
        }
    }

    /// Called by "Done" on the completion screen.
    func finishSession() {
        guard let current = session, current.phase == .finished else { return }
        if current.cardRemoved {
            clearSelection()
        } else {
            select(current.card)   // rescan: everything just copied now shows as already offloaded
        }
    }

    private func clearSelection() {
        session = nil
        isScanning = false
        selectedCardID = nil
        if let next = watcher.cards.first {
            select(next)
        }
    }

    private func install(_ newSession: OffloadSession) {
        newSession.onFinished = { [weak self, weak newSession] summary in
            guard let self, let newSession else { return }
            let allGood = !summary.cancelled && summary.failed == 0 && summary.copied > 0
            if self.settings.ejectAfterOffload && allGood && !newSession.cardRemoved {
                self.ejectCard(newSession.card)
            }
        }
        session = newSession
    }

    /// Let views that watch the model also refresh when the session changes.
    private func forwardChanges(from session: OffloadSession?) {
        sessionObserver = session?.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    // MARK: Offloading

    func startOffload() {
        guard let session, let destination = settings.destinationURL else { return }
        session.start(destination: destination, ledger: ledger)
    }

    // MARK: Ejecting

    func ejectSelectedCard() {
        guard let card = selectedCard else { return }
        ejectCard(card)
    }

    private func ejectCard(_ card: CardVolume) {
        guard !isEjecting else { return }
        isEjecting = true
        ejectError = nil
        Task {
            do {
                try await FileManager.default.unmountVolume(at: card.url, options: [.allPartitionsAndEjectDisk])
                // The unmount notification marks the session's card as removed.
            } catch {
                self.ejectError = "Couldn't eject \(card.name): \(error.localizedDescription)"
            }
            self.isEjecting = false
        }
    }

    // MARK: Window

    /// Activates SnapDrop and brings its main window to the front.
    func bringWindowForward() {
        NSApp.activate()
        let main = NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("main") == true }
            ?? NSApp.windows.first { $0.canBecomeMain }
        main?.makeKeyAndOrderFront(nil)
    }

    #if DEBUG
    /// Used by previews and demo mode to show a card without real hardware.
    func installDemo(card: CardVolume, session demoSession: OffloadSession) {
        watcher.injectDemoCards([card])
        selectedCardID = card.id
        isScanning = false
        install(demoSession)
    }
    #endif
}
