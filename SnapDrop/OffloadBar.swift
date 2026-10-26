import SwiftUI
import AppKit

/// The bar along the bottom of the window. It changes with the offload:
/// ready → the big "Offload N Clips" button, running → progress, finished → summary.
struct OffloadBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if let session = model.session {
                OffloadBarContent(session: session)
            } else {
                ReadyRow(title: OffloadFormatting.offloadButtonTitle(clipCount: 0),
                         blocker: model.isScanning ? "Scanning card…" : "Insert a card to begin",
                         start: {})
            }
        }
        .frame(minHeight: 64)
    }
}

private struct OffloadBarContent: View {
    @ObservedObject var session: OffloadSession
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            switch session.phase {
            case .ready:
                ReadyRow(
                    title: OffloadFormatting.offloadButtonTitle(clipCount: session.newClips.count),
                    blocker: blocker,
                    start: model.startOffload)
                    .transition(transition)
            case .running:
                ProgressRow(session: session)
                    .transition(transition)
            case .finished:
                CompletionRow(session: session)
                    .transition(transition)
            }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.35), value: session.phase)
    }

    private var transition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
    }

    private var blocker: String? {
        OffloadReadiness.blocker(
            hasCard: true,
            isScanning: model.isScanning,
            newClipCount: session.newClips.count,
            shootName: session.shootName,
            hasDestination: settings.destinationURL != nil,
            requiredBytes: session.newBytes,
            availableBytes: settings.destinationURL.flatMap(VolumeInfo.availableBytes(at:)))
    }
}

// MARK: - Ready

private struct ReadyRow: View {
    let title: String
    let blocker: String?
    let start: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let blocker {
                Label(blocker, systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            } else {
                Label("Ready. Every clip is verified with SHA-256 after copying.", systemImage: "checkmark.shield")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: start) {
                Label(title, systemImage: "arrow.down.circle.fill")
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(blocker != nil)
            .help(blocker ?? "Copy and verify the new clips")
            .accessibilityHint(blocker ?? "")
        }
    }
}

// MARK: - Running

private struct ProgressRow: View {
    @ObservedObject var session: OffloadSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Re-render once a second so the time estimate keeps moving.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let progress = session.progress
            let eta = OffloadFormatting.etaText(OffloadFormatting.estimatedSecondsRemaining(
                bytesDone: progress.bytesDone,
                bytesTotal: progress.bytesTotal,
                elapsed: context.date.timeIntervalSince(session.startedAt ?? context.date)))

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    stageLabel(progress.isVerifying)
                    Text(progress.currentFile)
                        .font(.body.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text("\(min(progress.filesDone + 1, max(progress.filesTotal, 1))) of \(progress.filesTotal)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: progress.fraction)
                    .progressViewStyle(.linear)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: progress.fraction)
                    .accessibilityLabel("Offload progress")
                    .accessibilityValue("\(Int(progress.fraction * 100)) percent. \(eta)")

                HStack {
                    Text(OffloadFormatting.bytesProgress(done: progress.bytesDone, total: progress.bytesTotal))
                        .monospacedDigit()
                    Text("·").foregroundStyle(.tertiary)
                    Text(eta)
                    Spacer()
                    Button("Cancel", role: .cancel, action: session.cancel)
                        .keyboardShortcut(.cancelAction)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func stageLabel(_ verifying: Bool) -> some View {
        if verifying {
            Label("Verifying", systemImage: "checkmark.shield.fill")
                .foregroundStyle(.tint)
                .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
                .font(.body.weight(.semibold))
        } else {
            Label("Copying", systemImage: "arrow.down.circle.fill")
                .foregroundStyle(.tint)
                .font(.body.weight(.semibold))
        }
    }
}

// MARK: - Finished

private struct CompletionRow: View {
    @ObservedObject var session: OffloadSession
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @State private var showingFailures = false

    var body: some View {
        let summary = session.summary ?? OffloadSummary()
        HStack(spacing: 14) {
            Image(systemName: symbol(summary))
                .font(.system(size: 30))
                .foregroundStyle(color(summary))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title(summary))
                    .font(.headline)
                Text(subtitle(summary))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            Spacer()

            if !summary.failures.isEmpty {
                Button("Show Problems") { showingFailures = true }
                    .popover(isPresented: $showingFailures) { FailureList(failures: summary.failures) }
            }
            Button(action: showInFinder) {
                Label("Show in Finder", systemImage: "folder")
            }
            .disabled(settings.destinationURL == nil)
            Button(action: model.ejectSelectedCard) {
                Label(session.cardRemoved ? "Ejected" : "Eject Card", systemImage: "eject.fill")
            }
            .disabled(session.cardRemoved || model.isEjecting)
            Button("Done", action: model.finishSession)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .controlSize(.large)
    }

    private func showInFinder() {
        let files = session.copiedPaths.map { URL(fileURLWithPath: $0) }
        if !files.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(files)
        } else if let destination = settings.destinationURL {
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        }
    }

    private func symbol(_ s: OffloadSummary) -> String {
        if s.cancelled { return "xmark.octagon.fill" }
        return s.failed == 0 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
    }

    private func color(_ s: OffloadSummary) -> Color {
        if s.cancelled { return .secondary }
        return s.failed == 0 ? .green : .orange
    }

    private func title(_ s: OffloadSummary) -> String {
        if s.cancelled { return "Offload Cancelled" }
        return s.failed == 0 ? "Offload Complete" : "Finished with Problems"
    }

    private func subtitle(_ s: OffloadSummary) -> String {
        var text = OffloadFormatting.summaryLine(s)
        if let error = model.ejectError {
            text += " — \(error)"
        } else if session.cardRemoved {
            text += " — card ejected, safe to remove"
        }
        return text
    }
}

private struct FailureList: View {
    let failures: [String]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(failures, id: \.self) { failure in
                    Label(failure, systemImage: "exclamationmark.circle")
                        .font(.callout)
                        .textSelection(.enabled)
                }
            }
            .padding()
        }
        .frame(width: 420, height: 220)
    }
}

#if DEBUG
#Preview("Bar – ready") {
    OffloadBar().demoEnvironment(DemoData.model(state: .ready)).padding().frame(width: 900)
}

#Preview("Bar – running") {
    OffloadBar().demoEnvironment(DemoData.model(state: .running)).padding().frame(width: 900)
}

#Preview("Bar – finished") {
    OffloadBar().demoEnvironment(DemoData.model(state: .finished)).padding().frame(width: 900)
}
#endif
