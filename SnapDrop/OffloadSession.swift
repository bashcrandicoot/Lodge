import Foundation

/// The state of offloading one card: what's on it, what the user typed,
/// and progress while copying.
@MainActor
final class OffloadSession: ObservableObject, Identifiable {
    enum Phase: Equatable {
        case ready      // waiting for the user to press Offload
        case running    // copying / verifying
        case finished   // done (or cancelled) — showing the summary
    }

    let id = UUID()
    let card: CardVolume
    /// Every file on the card, sorted by what the ledger knows (all categories).
    let inventory: CardInventory
    private let missingIDs: Set<String>
    private let offloadedIDs: Set<String>
    /// Every file on the card that hasn't been offloaded before (all categories).
    var allNewFiles: [Clip] { inventory.new }
    /// Files the ledger says were already offloaded, copy present or not (all categories).
    var allOffloadedFiles: [Clip] { inventory.offloaded + inventory.missing }
    /// Which kinds of files to offload (from Settings ▸ General).
    @Published var includedCategories: Set<MediaCategory> = Set(MediaCategory.allCases) {
        didSet { refreshFiles() }
    }
    /// Copy already-offloaded files again ("Re-offload…" menu). Off unless the user asks.
    @Published var reoffloadMode: ReoffloadMode = .off {
        didSet { refreshFiles() }
    }
    /// Single files picked with "Re-offload This File" (card paths).
    @Published var reoffloadIDs: Set<String> = [] {
        didSet { refreshFiles() }
    }
    /// Video lengths in seconds, by card path (read during the scan; unknown lengths are missing).
    let durations: [String: Double]
    /// "Skip short videos" (from Settings ▸ General).
    @Published var shortRule: ShortClipRule = .off {
        didSet { refreshFiles() }
    }
    /// Short clips the user chose to offload anyway (card paths).
    @Published var includedShortIDs: Set<String> = [] {
        didSet { refreshFiles() }
    }
    /// "Include All Short Clips" for this card.
    @Published var includeAllShort = false {
        didSet { refreshFiles() }
    }
    /// New short videos (and their sidecars) that won't be copied. Fixed once the offload starts.
    @Published private(set) var skippedShort = ShortClipSkip()
    /// What the Offload button copies: new files in the included categories, plus re-offloads.
    @Published private(set) var newClips: [Clip] = []
    /// Card paths in `newClips` that were offloaded before.
    @Published private(set) var reoffloadingIDs: Set<String> = []
    /// Already-offloaded files (copy present) in the included categories that won't be copied.
    @Published private(set) var alreadyOffloadedCount = 0
    /// Files whose copy is missing at the destination, in the included categories, not being copied.
    @Published private(set) var missingCopyCount = 0

    /// What the user typed in the Project field (fills `{project}`).
    @Published var projectInput = ""
    /// The camera these files came from (fills `{camera}`).
    @Published var cameraID: UUID?
    /// The final names, fixed when the offload starts (the preview shows these while copying).
    @Published private(set) var plan: [PlannedFile]?
    /// Card paths of files that were copied and verified in this offload.
    @Published private(set) var verifiedIDs: Set<String> = []
    @Published private(set) var phase: Phase = .ready
    @Published private(set) var progress = OffloadProgress()
    @Published private(set) var summary: OffloadSummary?
    @Published private(set) var startedAt: Date?
    /// Paths of the files copied in this offload (for "Show in Finder").
    @Published private(set) var copiedPaths: [String] = []
    /// The card was ejected or unplugged after the offload started.
    @Published var cardRemoved = false

    /// Called once when the offload ends (successfully, with failures, or cancelled).
    var onFinished: ((OffloadSummary) -> Void)?

    private var task: Task<Void, Never>?

    init(card: CardVolume, inventory: CardInventory, durations: [String: Double] = [:]) {
        self.card = card
        self.inventory = inventory
        self.durations = durations
        self.missingIDs = Set(inventory.missing.map(\.relativePath))
        self.offloadedIDs = Set(inventory.offloaded.map(\.relativePath))
        refreshFiles()
    }

    /// Without destination checks: files the ledger knows count as offloaded.
    convenience init(card: CardVolume, clips: [Clip], knownKeys: Set<String>) {
        self.init(card: card, inventory: CardInventory.classify(files: clips, volumeIdentity: card.identity,
                                                                knownKeys: knownKeys))
    }

    private func refreshFiles() {
        guard phase == .ready else { return }   // never change the list mid-offload
        let selection = OffloadSelection.make(inventory: inventory, categories: includedCategories,
                                              reoffload: reoffloadMode, reoffloadIDs: reoffloadIDs,
                                              shortRule: shortRule, durations: durations,
                                              includedShortIDs: includedShortIDs, includeAllShort: includeAllShort)
        newClips = selection.toCopy
        skippedShort = selection.skippedShort
        reoffloadingIDs = selection.reoffloading
        alreadyOffloadedCount = selection.offloadedKept
        missingCopyCount = selection.missingKept
    }

    /// Offloaded files in the included categories with a missing copy (re-offloaded or not).
    var missingCopiesInView: Int {
        inventory.missing.filter { includedCategories.contains($0.category) }.count
    }

    /// Offloaded files (copy present or missing) in the included categories.
    var offloadedInView: Int {
        allOffloadedFiles.filter { includedCategories.contains($0.category) }.count
    }

    /// "Re-offload This File" for one file (and its sidecars), or undo it.
    func toggleReoffload(_ clip: Clip) {
        if reoffloadIDs.contains(clip.relativePath) {
            reoffloadIDs.remove(clip.relativePath)
        } else {
            reoffloadIDs.insert(clip.relativePath)
        }
    }

    /// The video's length, if it could be read.
    func duration(of clip: Clip) -> Double? { durations[clip.relativePath] }

    /// Is this a short clip (by the current rule), skipped or included anyway?
    func isShortClip(_ clip: Clip) -> Bool {
        clip.category == .video && offloadedStatus(of: clip) == nil && shortRule.isShort(durations[clip.relativePath])
    }

    /// "Include Anyway" for one short clip (its sidecars come along), or skip it again.
    func toggleIncludeShort(_ clip: Clip) {
        if includeAllShort {
            // Turning one off from "all" keeps the others included.
            includedShortIDs = Set(inventory.new.filter(isShortClip).map(\.relativePath))
            includeAllShort = false
        }
        if includedShortIDs.contains(clip.relativePath) {
            includedShortIDs.remove(clip.relativePath)
        } else {
            includedShortIDs.insert(clip.relativePath)
        }
    }

    /// Short clips that are being offloaded because the user included them.
    func isIncludedShortClip(_ clip: Clip) -> Bool {
        isShortClip(clip) && !skippedShort.ids.contains(clip.relativePath)
    }

    /// Was this file offloaded before? (`nil` = never; `true` = copy missing.)
    func offloadedStatus(of clip: Clip) -> Bool? {
        if missingIDs.contains(clip.relativePath) { return true }
        if offloadedIDs.contains(clip.relativePath) { return false }
        return nil
    }

    /// New files per category, e.g. [.video: 42, .photo: 120].
    var categoryCounts: [MediaCategory: Int] {
        newClips.reduce(into: [:]) { $0[$1.category, default: 0] += 1 }
    }

    /// The cleaned-up project name ("Beach Day" -> "BeachDay").
    var project: String { NamingContext.clean(projectInput) }

    /// Total size of the new clips, in bytes.
    var newBytes: Int64 { newClips.reduce(0) { $0 + $1.size } }

    /// Starts copying in the background.
    /// `plan` comes from `OffloadPlanner` (see `AppModel.startOffload`).
    func start(plan: [PlannedFile], destination: URL, ledger: Ledger) {
        guard phase == .ready, !plan.isEmpty else { return }
        self.plan = plan
        phase = .running
        startedAt = Date()
        progress = OffloadProgress(filesTotal: plan.count, bytesTotal: plan.reduce(0) { $0 + $1.size })

        let job = OffloadJob(
            card: card,
            plan: plan,
            destination: destination,
            alreadyOffloaded: alreadyOffloadedCount + missingCopyCount)

        // `Task.detached` runs the copy on a background thread so the UI stays responsive.
        // Every UI update hops back to the main thread with `MainActor.run`.
        task = Task.detached(priority: .userInitiated) {
            let result = await Offloader.run(
                job: job,
                progress: { update in
                    await MainActor.run { self.progress = update }
                },
                record: { entry in
                    await ledger.add(entry)
                    await MainActor.run {
                        self.copiedPaths.append(entry.destinationPath)
                        self.verifiedIDs.insert(entry.sourceRelativePath)
                    }
                })
            await MainActor.run {
                self.summary = result
                self.phase = .finished
                self.onFinished?(result)
            }
        }
    }

    /// Stops after the current chunk. The half-copied file is deleted; finished ones are kept.
    func cancel() {
        task?.cancel()
    }

    #if DEBUG
    /// Puts the session into a given state for previews and screenshots.
    func applyDemo(phase: Phase, progress: OffloadProgress, startedAt: Date?, summary: OffloadSummary?,
                   plan: [PlannedFile]? = nil, verifiedIDs: Set<String> = []) {
        self.plan = plan
        self.verifiedIDs = verifiedIDs
        self.phase = phase
        self.progress = progress
        self.startedAt = startedAt
        self.summary = summary
    }
    #endif
}
