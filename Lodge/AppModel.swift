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
    let destinations: DestinationStore
    let presets: PresetStore

    /// The card shown in the funnel (its mount path).
    @Published private(set) var selectedCardID: String?
    /// The selected card's clips and offload state. `nil` while scanning / no card.
    @Published private(set) var session: OffloadSession? {
        didSet {
            forwardChanges(from: session)
            if session !== oldValue {
                // A new card, a rescan or an eject: stop drawing thumbnails for the old files.
                thumbnails.cancelAll()
                QuickLookController.shared.close()
            }
        }
    }
    /// Thumbnails for the Media grid (and list, if turned on).
    let thumbnails = ThumbnailProvider()
    @Published private(set) var isScanning = false
    @Published var showingRecent = false
    @Published private(set) var isEjecting = false
    @Published var ejectError: String?
    /// The selected card's files sorted by what the ledger knows. `nil` while scanning / no card.
    /// Re-checked after each offload (the session keeps the list it started with).
    @Published private(set) var cardInventory: CardInventory?
    /// Is the selected card safe to format? `nil` while scanning / no card.
    var formatReadiness: FormatReadiness? {
        cardInventory.map { FormatReadiness(inventory: $0, skipped: session?.skippedShort ?? ShortClipSkip()) }
    }
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
    private var destinationsObserver: AnyCancellable?
    private var categoriesObserver: AnyCancellable?
    private var appearanceObserver: AnyCancellable?
    private var shortRuleObserver: AnyCancellable?
    private var fileRulesObserver: AnyCancellable?
    private var presetsObserver: AnyCancellable?
    /// Video lengths by ledger key (`nil` = couldn't be read), so rescans don't read them again.
    private var durationCache: [String: Double?] = [:]
    /// Reads video lengths for "Skip videos shorter than" (tests swap in a fake).
    var durationReader: DurationReading = AVDurationReader()

    init(settings: AppSettings? = nil, ledger: Ledger? = nil, cameras: CameraStore? = nil,
         destinations: DestinationStore? = nil, presets: PresetStore? = nil,
         formatter: CardFormatter = CardFormatter(), startWatching: Bool = true) {
        self.formatter = formatter
        self.settings = settings ?? AppSettings()
        self.ledger = ledger ?? Ledger()
        self.cameras = cameras ?? CameraStore()
        self.destinations = destinations ?? DestinationStore()
        // (As the unit tests' host, never touch the user's saved presets.)
        self.presets = presets ?? (AppModel.isRunningUnitTests ? PresetStore(fileURL: nil) : PresetStore())
        self.watcher = VolumeWatcher()

        // The old Settings ▸ General ▸ Destination folder joins the favorites, once: favorites are
        // now the only place destinations are set. Then start in the default favorite.
        if !self.settings.destinationMigrated {
            self.destinations.adoptLegacyDestination(self.settings.destinationPath)
            self.settings.destinationMigrated = true
        }
        let launchPath = self.destinations.launchDestination(currentPath: self.settings.destinationPath)
        if launchPath != self.settings.destinationPath {
            self.settings.destinationPath = launchPath
        }
        // "Not connected" and the Offload button follow drives coming and going.
        destinationsObserver = self.destinations.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }

        presetsObserver = self.presets.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }

        // Settings ▸ Files: new proxy/sidecar extensions re-plan right away; a changed ignore
        // list rescans the card (ignored files aren't part of the card's file list at all).
        fileRulesObserver = self.settings.$fileRules.removeDuplicates().dropFirst().sink { [weak self] rules in
            guard let self, let session = self.session else { return }
            let ignoreChanged = session.fileRules.ignorePatterns != rules.ignorePatterns
            session.fileRules = rules
            if ignoreChanged, session.phase == .ready, !self.isScanning, self.watcher.cards.contains(session.card) {
                self.select(session.card, keepFormatState: true)
            }
        }

        // The Offload button depends on the camera list (e.g. the chosen camera was deleted).
        camerasObserver = self.cameras.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        // Turning a file category on or off in Settings updates the current card right away.
        categoriesObserver = self.settings.$includedCategories.sink { [weak self] categories in
            self?.session?.includedCategories = categories
        }

        shortRuleObserver = self.settings.$skipShortClips
            .combineLatest(self.settings.$shortClipSeconds)
            .sink { [weak self] enabled, seconds in
                self?.session?.shortRule = ShortClipRule(isEnabled: enabled, threshold: Double(seconds))
            }

        // Settings ▸ Appearance: Light / Dark / System for every window, alerts and menus included.
        if !AppModel.isRunningUnitTests && !AppModel.demoForcesAppearance {
            appearanceObserver = self.settings.$appearance.sink { appearance in
                NSApp?.appearance = appearance.nsAppearance
            }
        }

        // The watcher must ignore the volume the destination folder lives on.
        watcher.destinationPathProvider = { [weak self] in self?.settings.destinationPath }
        watcher.onCardInserted = { [weak self] card in self?.cardInserted(card) }
        watcher.onCardRemoved = { [weak self] card in self?.cardRemoved(card) }

        // Don't watch for cards while unit tests run inside the app.
        if startWatching && !AppModel.isRunningUnitTests {
            watcher.start()
            self.destinations.startWatchingDrives()
        }
    }

    /// Screenshots pick Light or Dark with `-LodgeDemoAppearance` (Debug builds only).
    static var demoForcesAppearance: Bool {
        #if DEBUG
        DemoData.launchState != nil && UserDefaults.standard.string(forKey: "LodgeDemoAppearance") != nil
        #else
        false
        #endif
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
        cardInventory = nil
        if !keepFormatState {
            formatState = .idle
            pendingFormattedMount = nil
        }
        isScanning = true
        let entries = ledger.entriesByKey()
        let cache = durationCache
        let reader = durationReader
        let rules = settings.fileRules
        Task {
            let (inventory, durations) = await Task.detached(priority: .userInitiated) {
                let scan = ClipScanner.scanReport(volumeURL: card.url, rules: rules)
                // Checks each offloaded file's copy is still at the destination ("Missing copy").
                var inventory = CardInventory.classify(files: scan.files, volumeIdentity: card.identity,
                                                       entries: entries, fileSize: FormatReadiness.diskFileSize)
                inventory.ignored = scan.ignored
                // Video lengths for "Skip videos shorter than" and the list (only files that may be copied).
                let durations = await DurationScanner.read(inventory.new + inventory.missing,
                                                           volumeIdentity: card.identity, cache: cache, reader: reader)
                return (inventory, durations)
            }.value
            self.durationCache.merge(durations.fresh) { _, new in new }
            // The user may have picked a different card while we were scanning.
            guard self.selectedCardID == card.id else { return }
            self.isScanning = false
            self.cardInventory = inventory
            self.install(OffloadSession(card: card, inventory: inventory, durations: durations.byPath))
        }
    }

    /// Re-checks the ledger and destination copies for the current session's files (after an offload).
    private func refreshInventory(for session: OffloadSession) {
        let card = session.card
        let files = session.inventory.all
        let ignored = session.inventory.ignored
        let entries = ledger.entriesByKey()
        Task {
            let inventory = await Task.detached(priority: .userInitiated) {
                var inventory = CardInventory.classify(files: files, volumeIdentity: card.identity, entries: entries,
                                                       fileSize: FormatReadiness.diskFileSize)
                inventory.ignored = ignored
                return inventory
            }.value
            guard self.session === session else { return }
            self.cardInventory = inventory
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
            self.refreshInventory(for: newSession)
            let allGood = OffloadFeedback.isCleanSuccess(summary)
            if OffloadFeedback.shouldPlaySuccessSound(summary, enabled: self.settings.playSuccessSound) {
                NSSound(named: "Glass")?.play()
            }
            if self.settings.ejectAfterOffload && allGood && !newSession.cardRemoved {
                self.ejectCard(newSession.card)
            }
        }
        newSession.includedCategories = settings.includedCategories
        newSession.shortRule = settings.shortClipRule
        newSession.fileRules = settings.fileRules
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
        let naming = settings.effectiveNaming
        return OffloadReadiness.blocker(
            hasCard: true,
            isScanning: isScanning,
            newFileCount: session.newClips.count,
            missingCopies: session.missingCopyCount,
            shortClipsSkipped: session.skippedShort.clips.count,
            cardIsEmpty: session.inventory.fileCount == 0,
            namingIsValid: naming != nil,
            needs: NamingNeeds(naming),
            project: session.project,
            hasCamera: !cameraTokenValue(for: session).isEmpty,
            hasDestination: settings.destinationURL != nil,
            destinationConnected: settings.destinationPath.map(DestinationStore.isFolder) ?? true,
            requiredBytes: session.newBytes,
            availableBytes: settings.destinationURL.flatMap(VolumeInfo.availableBytes(at:)))
    }

    func startOffload() {
        guard let session, session.phase == .ready, offloadBlocker == nil,
              let destination = settings.destinationURL, let naming = settings.effectiveNaming else { return }
        let plan = OffloadPlanner.plan(
            files: session.newClips,
            naming: naming,
            context: namingContext(for: session),
            rules: settings.fileRules,
            existingNames: OffloadPlanner.diskLister(root: destination))
        // A quick dump doesn't use the project, so it doesn't replace the remembered one.
        if !settings.quickDump { settings.rememberProject(session.projectInput) }
        cameras.remember(session.cameraID, forCard: session.card.identity)
        session.start(plan: plan, destination: destination, ledger: ledger)
    }

    // MARK: Naming

    /// The values for the template tokens (empty fields stay empty).
    func namingContext(for session: OffloadSession) -> NamingContext {
        let card = NamingContext.clean(session.card.name)
        return NamingContext(
            project: settings.quickDump ? "" : session.project,
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
            naming: settings.effectiveNaming ?? .standard,
            context: namingContext(for: session).fillingBlanks(),
            rules: settings.fileRules,
            existingNames: OffloadPlanner.diskLister(root: settings.destinationURL))
    }

    /// True when the preview contains placeholder values for fields the templates need.
    func previewHasPlaceholders(for session: OffloadSession) -> Bool {
        guard session.plan == nil else { return false }
        let needs = NamingNeeds(settings.effectiveNaming)
        return (needs.project && session.project.isEmpty)
            || (needs.camera && cameraTokenValue(for: session).isEmpty)
    }

    // MARK: Re-offloading and forgetting

    /// Chooses what gets copied again. "Everything" asks first, because it makes a second
    /// set of copies of the whole card.
    func setReoffloadMode(_ mode: ReoffloadMode) {
        guard let session, session.phase == .ready else { return }
        guard mode == .everything else {
            session.reoffloadMode = mode
            return
        }
        let count = session.inventory.all.filter { session.includedCategories.contains($0.category) }.count
        let alert = ReoffloadAlert.makeEverything(cardName: session.card.name, fileCount: count)
        presentSheet(alert) { [weak session] response in
            guard response == .alertFirstButtonReturn, let session, session.phase == .ready else { return }
            session.reoffloadMode = .everything
        }
    }

    /// How many ledger entries the selected card has (for "Forget This Card's History…").
    var selectedCardHistoryCount: Int {
        guard let card = selectedCard else { return 0 }
        return ledger.entryCount(forVolume: card.identity)
    }

    /// Asks, then removes every ledger entry for the selected card and rescans it:
    /// its files show as new again. Copies at the destination are left alone.
    func confirmForgetSelectedCardHistory() {
        guard !isBusy, !formatState.isFormatting, let card = selectedCard else { return }
        let count = ledger.entryCount(forVolume: card.identity)
        guard count > 0 else { return }
        let alert = ReoffloadAlert.makeForget(cardName: card.name, entryCount: count)
        presentSheet(alert) { [weak self] response in
            guard response == ReoffloadAlert.forgetResponse, let self, !self.isBusy else { return }
            self.ledger.forget(volumeIdentity: card.identity)
            if self.selectedCardID == card.id, self.watcher.cards.contains(card) { self.select(card) }
        }
    }

    /// Removes one entry from the history (Recent Offloads ▸ Forget).
    func forgetLedgerEntry(_ entry: LedgerEntry) {
        ledger.forget(entry)
        // The selected card may now have new files.
        if let card = selectedCard, session?.phase == .ready, entry.sourceKey.hasPrefix(card.identity + "|"),
           watcher.cards.contains(card) {
            select(card)
        }
    }

    /// Shows an alert as a sheet on the main window (or as a dialog if there's none).
    private func presentSheet(_ alert: NSAlert, handler: @escaping (NSApplication.ModalResponse) -> Void) {
        let window = NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("main") == true && $0.isVisible }
            ?? NSApp.keyWindow
        if let window {
            alert.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(alert.runModal())
        }
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
                self.ejectError = "Couldn’t eject \(card.name): \(error.localizedDescription)"
            }
            self.isEjecting = false
        }
    }

    // MARK: Destinations

    /// The favorite the current destination folder belongs to, if any.
    var currentFavorite: FavoriteDestination? {
        destinations.favorite(forPath: settings.destinationPath)
    }

    /// Switches to a favorite (not while copying, and only if its folder is there).
    func useFavorite(_ favorite: FavoriteDestination) {
        guard !isBusy, destinations.isConnected(favorite) else { return }
        settings.destinationPath = favorite.path
        destinations.markUsed(favorite.id)
        watcher.refresh()
    }

    /// The standard folder panel, for a folder that isn't a favorite.
    func chooseOtherDestination() {
        guard !isBusy else { return }
        settings.chooseDestination()
        destinations.markUsed(currentFavorite?.id)
        watcher.refresh()
    }

    /// A folder dropped from Finder onto the Destination stage: its favorite if it is one,
    /// otherwise used like "Choose Other Folder…". Returns false if it isn't a folder.
    @discardableResult
    func useDroppedFolder(_ url: URL) -> Bool {
        guard !isBusy, DestinationStore.isFolder(url.path) else { return false }
        if let favorite = destinations.favorite(forPath: url.path) {
            useFavorite(favorite)
        } else {
            settings.destinationPath = DestinationStore.normalized(url.path)
            destinations.markUsed(nil)
            watcher.refresh()
        }
        return true
    }

    /// Saves the current destination folder as a favorite and remembers it as last used.
    func addCurrentDestinationToFavorites() {
        guard let path = settings.destinationPath else { return }
        let favorite = destinations.add(path: path)
        destinations.markUsed(favorite.id)
    }

    // MARK: Presets

    /// Switches to a preset: templates, short clips, quick dump and file rules at once, plus its
    /// destination (if connected) and camera (for the card on screen). The tree updates live.
    func applyPreset(_ preset: OffloadPreset) {
        guard !isBusy else { return }
        settings.apply(preset)
        if let path = preset.destinationPath, DestinationStore.isFolder(path) {
            if let favorite = destinations.favorite(forPath: path) {
                useFavorite(favorite)
            } else {
                settings.destinationPath = path
                destinations.markUsed(nil)
                watcher.refresh()
            }
        }
        if let camera = cameras.camera(id: preset.cameraID), let session, session.phase == .ready {
            selectCamera(camera.id)
        }
        presets.markActive(preset.id)
    }

    /// The current setup (destination and camera as shown in the main window).
    func currentSetupAsPreset(name: String) -> OffloadPreset {
        settings.makePreset(name: name, destinationPath: settings.destinationPath,
                            cameraID: session?.cameraID ?? presets.activePreset?.cameraID)
    }

    /// "Save Current Setup as Preset…": adds it and makes it the active one.
    @discardableResult
    func saveCurrentSetupAsPreset(named name: String) -> OffloadPreset {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let preset = presets.add(currentSetupAsPreset(name: trimmed.isEmpty ? "New Preset" : trimmed))
        presets.markActive(preset.id)
        return preset
    }

    /// "Update “Drone Day”": the active preset takes over the current setup.
    func updateActivePresetFromCurrentSetup() {
        guard let active = presets.activePreset else { return }
        var updated = currentSetupAsPreset(name: active.name)
        updated.id = active.id
        presets.update(updated)
    }

    /// True when a setting changed after the active preset was picked (the switcher says "Edited").
    var activePresetIsEdited: Bool {
        guard let active = presets.activePreset else { return false }
        return Self.preset(active, differsFrom: settings, destinationPath: settings.destinationPath)
    }

    /// Compares the parts a preset sets (a preset without a destination doesn't care where files go).
    static func preset(_ preset: OffloadPreset, differsFrom settings: AppSettings, destinationPath: String?) -> Bool {
        if preset.folderTemplate != settings.folderTemplate || preset.fileTemplate != settings.fileTemplate
            || preset.skipShortClips != settings.skipShortClips || preset.quickDump != settings.quickDump
            || preset.fileRules != settings.fileRules { return true }
        if preset.skipShortClips && preset.shortClipSeconds != settings.shortClipSeconds { return true }
        if let path = preset.destinationPath {
            return DestinationStore.normalized(path) != destinationPath.map(DestinationStore.normalized)
        }
        return false
    }

    // MARK: Formatting

    /// Format Card… is offered only for a mounted, fully offloaded card while nothing else runs.
    var canFormatSelectedCard: Bool {
        guard let card = selectedCard, watcher.cards.contains(card),
              let readiness = formatReadiness, readiness.isReady || readiness.isReadyExceptShortClips,
              !isBusy, !isScanning, !isEjecting, !formatState.isFormatting, session?.cardRemoved != true else { return false }
        return true
    }

    /// Asks for confirmation (Cancel is the default button), then formats.
    func confirmFormatSelectedCard() {
        guard canFormatSelectedCard, let card = selectedCard, let readiness = formatReadiness else { return }
        let alert = FormatAlert.make(cardName: card.name, readiness: readiness)
        presentSheet(alert) { [weak self] response in
            guard response == FormatAlert.formatResponse else { return }
            self?.formatSelectedCard()
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
        // Skipped short clips the user agreed to discard (by ledger key: a changed file blocks formatting).
        let skippedIDs = session?.skippedShort.ids ?? []
        let rules = settings.fileRules
        let discarding = Set((cardInventory?.new ?? [])
            .filter { skippedIDs.contains($0.relativePath) }
            .map { $0.ledgerKey(volumeIdentity: card.identity) })
        Task {
            let outcome = await formatter.format(
                card: card, destinationPath: destinationPath, destinationVolume: destinationVolume,
                stillReady: {
                    // Same ignore list as the scan the user saw: ignored files never block formatting.
                    let files = ClipScanner.scan(volumeURL: card.url, rules: rules)
                    let inventory = CardInventory.classify(files: files, volumeIdentity: card.identity,
                                                           entries: entries, fileSize: FormatReadiness.diskFileSize)
                    return FormatReadiness.stillReady(inventory: inventory, volumeIdentity: card.identity,
                                                      discarding: discarding)
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
            cardInventory = CardInventory()   // empty: nothing pending, nothing to format
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

    /// Activates Lodge and brings its main window to the front.
    func bringWindowForward() {
        NSApp.activate()
        let main = NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("main") == true }
            ?? NSApp.windows.first { $0.canBecomeMain }
        main?.makeKeyAndOrderFront(nil)
    }

    #if DEBUG
    /// Used by previews and demo mode to show a card without real hardware.
    func installDemo(card: CardVolume, session demoSession: OffloadSession, inventory: CardInventory? = nil) {
        watcher.injectDemoCards([card])
        selectedCardID = card.id
        isScanning = false
        cardInventory = inventory ?? demoSession.inventory
        install(demoSession)
    }
    #endif
}
