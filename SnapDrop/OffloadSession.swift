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
    /// Clips that have not been offloaded before.
    let newClips: [Clip]
    /// Clips the ledger says were already offloaded.
    let alreadyOffloadedCount: Int

    @Published var shootNameInput = ""
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

    init(card: CardVolume, clips: [Clip], knownKeys: Set<String>) {
        self.card = card
        let fresh = clips.filter { !knownKeys.contains($0.ledgerKey(volumeIdentity: card.identity)) }
        self.newClips = fresh
        self.alreadyOffloadedCount = clips.count - fresh.count
    }

    /// The cleaned-up shoot name ("Beach Shoot" -> "BeachShoot").
    var shootName: String { NamingContext.clean(shootNameInput) }

    /// The cleaned-up project name.
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
            alreadyOffloaded: alreadyOffloadedCount)

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
