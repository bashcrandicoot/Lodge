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
    /// Is the selected card safe to format? `nil` while scanning / no card.
    @Published private(set) var formatReadiness: FormatReadiness?
    @Published private(set) var formatState: FormatState = .idle

    enum FormatState: Equatable {
        case idle
        case formatting(cardName: String)
        case formatted(cardName: String)
        case failed(String)

        var isFormatting: Bool { if case .formatting = self { return true } else { return false } }
    }

    let formatter: CardFormatter
    /// Mount path of the card being formatted (its unmount/remount is expected, not a removal).
    private var formattingCardPath: String?
    /// Where the freshly formatted card will show up again.
    private var pendingFormattedMount: String?

    private var sessionObserver: AnyCancellable?
    private var camerasObserver: AnyCancellable?
    private var categoriesObserver: AnyCancellable?

    init(settings: AppSettings? = nil, ledger: Ledger? = nil, cameras: CameraStore? = nil,
         formatter: CardFormatter = CardFormatter(), startWatching: Bool = true) {
        self.formatter = formatter
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
        if let pending = pendingFormattedMount, pending == card.url.path {
            // The card we just formatted is back, empty.
            pendingFormattedMount = nil
            select(card, keepFormatState: true)
            return
        }
        guard !isBusy, !formatState.isFormatting else { return }
        select(card)
        bringWindowForward()
    }

    private func cardRemoved(_ card: CardVolume) {
        // Formatting unmounts and remounts the card; that's not the user pulling it out.
        if formattingCardPath == card.url.path || pendingFormattedMount == card.url.path { return }
        guard selectedCardID == card.id else { return }
        if let current = session, current.card.id == card.id, current.phase != .ready {
            // Keep the progress/summary visible; just note the card is gone.
            current.cardRemoved = true
            return
        }
        clearSelection()
    }

    /// Shows `card` in the funnel and scans it for clips in the background.
    func select(_ card: CardVolume, keepFormatState: Bool = false) {
        guard !isBusy, !formatState.isFormatting else { return }
        selectedCardID = card.id
        session = nil
        formatReadiness = nil
        if !keepFormatState {
            formatState = .idle
            pendingFormattedMount = nil
        }
        isScanning = true
        let entries = ledger.entriesByKey()
        Task {
            let (clips, readiness) = await Task.detached(priority: .userInitiated) {
                let clips = ClipScanner.scan(volumeURL: card.url)
                let readiness = FormatReadiness.compute(files: clips, volumeIdentity: card.identity, entries: entries,
                                                        fileSize: FormatReadiness.diskFileSize)
                return (clips, readiness)
            }.value
            // The user may have picked a different card while we were scanning.
            guard self.selectedCardID == card.id else { return }
            self.isScanning = false
            self.formatReadiness = readiness
            self.install(OffloadSession(card: card, clips: clips, knownKeys: self.ledger.knownKeys))
        }
    }

    /// Re-checks "Ready to format" for the current session's files (after an offload).
    private func refreshFormatReadiness(for session: OffloadSession) {
        let card = session.card
        let files = session.allNewFiles + session.allOffloadedFiles
        let entries = ledger.entriesByKey()
        Task {
            let readiness = await Task.detached(priority: .userInitiated) {
                FormatReadiness.compute(files: files, volumeIdentity: card.identity, entries: entries,
                                        fileSize: FormatReadiness.diskFileSize)
            }.value
            guard self.session === session else { return }
            self.formatReadiness = readiness
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
            self.refreshFormatReadiness(for: newSession)
            let allGood = OffloadFeedback.isCleanSuccess(summary)
            if OffloadFeedback.shouldPlaySuccessSound(summary, enabled: self.settings.playSuccessSound) {
                NSSound(named: "Glass")?.play()
            }
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
            cardIsEmpty: session.allNewFiles.isEmpty && session.allOffloadedFiles.isEmpty,
            namingIsValid: naming != nil,
            needs: NamingNeeds(naming),
            project: session.project,
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

    // MARK: Formatting

    /// Format Card… is offered only for a mounted, fully offloaded card while nothing else runs.
    var canFormatSelectedCard: Bool {
        guard let card = selectedCard, watcher.cards.contains(card), formatReadiness?.isReady == true,
              !isBusy, !isScanning, !isEjecting, !formatState.isFormatting, session?.cardRemoved != true else { return false }
        return true
    }

    /// Asks for confirmation (Cancel is the default button), then formats.
    func confirmFormatSelectedCard() {
        guard canFormatSelectedCard, let card = selectedCard, let readiness = formatReadiness else { return }
        let alert = FormatAlert.make(cardName: card.name, readiness: readiness)
        let window = NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("main") == true && $0.isVisible }
            ?? NSApp.keyWindow
        let handler: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == FormatAlert.formatResponse else { return }
            self?.formatSelectedCard()
        }
        if let window {
            alert.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(alert.runModal())
        }
    }

    /// Erases the selected card with diskutil (same file system and name) after re-checking it.
    func formatSelectedCard() {
        guard canFormatSelectedCard, let card = selectedCard else { return }
        formatState = .formatting(cardName: card.name)
        formattingCardPath = card.url.path
        let entries = ledger.entriesByKey()
        let destinationPath = settings.destinationPath
        let destinationVolume = settings.destinationURL
            .flatMap { try? $0.resourceValues(forKeys: [.volumeURLKey]).volume }?.path
        let formatter = self.formatter
        Task {
            let outcome = await formatter.format(
                card: card, destinationPath: destinationPath, destinationVolume: destinationVolume,
                stillReady: {
                    let files = ClipScanner.scan(volumeURL: card.url)
                    return FormatReadiness.compute(files: files, volumeIdentity: card.identity, entries: entries,
                                                   fileSize: FormatReadiness.diskFileSize).isReady
                })
            self.formatFinished(card: card, outcome: outcome)
        }
    }

    private func formatFinished(card: CardVolume, outcome: FormatOutcome) {
        formattingCardPath = nil
        switch outcome {
        case .refused(let message), .failed(let message):
            formatState = .failed(message)
        case .formatted(let name, let mountPoint):
            formatState = .formatted(cardName: name)
            formatReadiness = FormatReadiness()   // empty: nothing pending, nothing to format
            let mount = mountPoint ?? card.url.path
            if settings.ejectAfterOffload {
                // Keep the finished offload on screen; the unmount marks its card as removed.
                ejectCard(CardVolume(url: URL(fileURLWithPath: mount, isDirectory: true), name: name, uuid: nil))
            } else if let back = watcher.cards.first(where: { $0.url.path == mount }) {
                select(back, keepFormatState: true)
            } else {
                // Not remounted yet: `cardInserted` shows it when it appears.
                pendingFormattedMount = mount
            }
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
    func installDemo(card: CardVolume, session demoSession: OffloadSession, readiness: FormatReadiness? = nil) {
        watcher.injectDemoCards([card])
        selectedCardID = card.id
        isScanning = false
        formatReadiness = readiness
        install(demoSession)
    }
    #endif
}
