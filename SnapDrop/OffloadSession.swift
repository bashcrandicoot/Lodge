import Foundation

/// The state of offloading one card: what's on it, what the user typed,
/// and progress while copying. The `OffloadSheet` view displays this.
@MainActor
final class OffloadSession: ObservableObject, Identifiable {
    enum Phase: Equatable {
        case ready      // waiting for the user to press Offload
        case running    // copying
        case finished   // done (or cancelled) — showing the summary
    }

    let id = UUID()
    let card: CardVolume
    /// Clips that have not been offloaded before.
    let newClips: [Clip]
    /// Clips the ledger says were already offloaded.
    let alreadyOffloadedCount: Int

    @Published var shootNameInput = ""
    @Published private(set) var phase: Phase = .ready
    @Published private(set) var progress = OffloadProgress()
    @Published private(set) var summary: OffloadSummary?

    private var task: Task<Void, Never>?

    init(card: CardVolume, clips: [Clip], knownKeys: Set<String>) {
        self.card = card
        let fresh = clips.filter { !knownKeys.contains($0.ledgerKey(volumeIdentity: card.identity)) }
        self.newClips = fresh
        self.alreadyOffloadedCount = clips.count - fresh.count
    }

    /// The cleaned-up shoot name ("Beach Shoot" -> "BeachShoot").
    var shootName: String { Renamer.sanitizeShootName(shootNameInput) }

    /// Total size of the new clips, in bytes.
    var newBytes: Int64 { newClips.reduce(0) { $0 + $1.size } }

    /// Example of the first file name, shown under the text field.
    var exampleName: String? {
        guard !shootName.isEmpty, let first = newClips.min(by: { $0.captureDate < $1.captureDate }) else { return nil }
        let date = Renamer.dateString(for: first.captureDate)
        let file = Renamer.fileName(
            prefix: Renamer.prefix(dateString: date, shootName: shootName),
            sequence: 1,
            fileExtension: first.url.pathExtension)
        return "\(date)/\(shootName)/\(file)"
    }

    /// Starts copying in the background.
    func start(destination: URL, ledger: Ledger) {
        guard phase == .ready, !shootName.isEmpty, !newClips.isEmpty else { return }
        phase = .running
        progress = OffloadProgress(filesTotal: newClips.count, bytesTotal: newBytes)

        let job = OffloadJob(
            card: card,
            clips: newClips,
            shootName: shootName,
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
                })
            await MainActor.run {
                self.summary = result
                self.phase = .finished
            }
        }
    }

    /// Stops after the current chunk. The half-copied file is deleted; finished ones are kept.
    func cancel() {
        task?.cancel()
    }
}
