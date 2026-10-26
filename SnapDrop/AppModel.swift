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
    let cameras: CameraStore

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
    private var camerasObserver: AnyCancellable?
    private var categoriesObserver: AnyCancellable?

    init(settings: AppSettings? = nil, ledger: Ledger? = nil, cameras: CameraStore? = nil, startWatching: Bool = true) {
        self.settings = settings ?? AppSettings()
        self.ledger = ledger ?? Ledger()
        self.cameras = cameras ?? CameraStore()
        self.watcher = VolumeWatcher()

        // The Offload button depends on the camera list (e.g. the chosen camera was deleted).
        camerasObserver = self.cameras.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        // Turning a file category on or off in Settings updates the current card right away.
        categoriesObserver = self.settings.$includedCategories.sink { [weak self] categories in
            self?.session?.includedCategories = categories
        }

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
        newSession.includedCategories = settings.includedCategories
        if newSession.projectInput.isEmpty { newSession.projectInput = settings.lastProject }
        newSession.cameraID = cameras.suggestedCamera(forCard: newSession.card.identity) ?? newSession.cameraID
        session = newSession
    }

    /// Let views that watch the model also refresh when the session changes.
    private func forwardChanges(from session: OffloadSession?) {
        sessionObserver = session?.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    // MARK: Offloading

    /// Why the Offload button is disabled right now (`nil` = ready to go).
    var offloadBlocker: String? {
        guard let session else {
            return isScanning ? "Scanning card…" : "Insert a card to begin"
        }
        let naming = settings.naming
        return OffloadReadiness.blocker(
            hasCard: true,
            isScanning: isScanning,
            newFileCount: session.newClips.count,
            namingIsValid: naming != nil,
            needs: NamingNeeds(naming),
            project: session.project,
            shootName: session.shootName,
            hasCamera: !cameraTokenValue(for: session).isEmpty,
            hasDestination: settings.destinationURL != nil,
            requiredBytes: session.newBytes,
            availableBytes: settings.destinationURL.flatMap(VolumeInfo.availableBytes(at:)))
    }

    func startOffload() {
        guard let session, session.phase == .ready, offloadBlocker == nil,
              let destination = settings.destinationURL, let naming = settings.naming else { return }
        let plan = OffloadPlanner.plan(
            files: session.newClips,
            naming: naming,
            context: namingContext(for: session),
            existingNames: OffloadPlanner.diskLister(root: destination))
        settings.rememberProject(session.projectInput)
        cameras.remember(session.cameraID, forCard: session.card.identity)
        session.start(plan: plan, destination: destination, ledger: ledger)
    }

    // MARK: Naming

    /// The values for the template tokens (empty fields stay empty).
    func namingContext(for session: OffloadSession) -> NamingContext {
        let card = NamingContext.clean(session.card.name)
        return NamingContext(
            project: session.project,
            shoot: session.shootName,
            camera: cameraTokenValue(for: session),
            card: card.isEmpty ? "Card" : card)
    }

    /// The `{camera}` value for the session's selected camera ("" if none).
    func cameraTokenValue(for session: OffloadSession) -> String {
        cameras.camera(id: session.cameraID)?.tokenValue ?? ""
    }

    /// Picks the camera for the current card and remembers it for next time.
    func selectCamera(_ id: UUID?) {
        guard let session, session.phase == .ready else { return }
        session.cameraID = id
        cameras.remember(id, forCard: session.card.identity)
    }

    /// What the preview shows: the frozen plan once copying started, otherwise a fresh
    /// plan with placeholders for fields that are still empty.
    func previewPlan(for session: OffloadSession) -> [PlannedFile] {
        if let plan = session.plan { return plan }
        return OffloadPlanner.plan(
            files: session.newClips,
            naming: settings.naming ?? .standard,
            context: namingContext(for: session).fillingBlanks(),
            existingNames: OffloadPlanner.diskLister(root: settings.destinationURL))
    }

    /// True when the preview contains placeholder values for fields the templates need.
    func previewHasPlaceholders(for session: OffloadSession) -> Bool {
        guard session.plan == nil else { return false }
        let needs = NamingNeeds(settings.naming)
        return (needs.project && session.project.isEmpty)
            || (needs.shoot && session.shootName.isEmpty)
            || (needs.camera && cameraTokenValue(for: session).isEmpty)
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
