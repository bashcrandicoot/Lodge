import SwiftUI
import AppKit

/// The bar along the bottom of the window. It changes with the offload:
/// ready → the big "Offload N Files" button, running → progress, finished → summary.
struct OffloadBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let session = model.session {
            OffloadBarContent(session: session)
        } else {
            ReadyRow(title: OffloadFormatting.offloadButtonTitle(fileCount: 0),
                     blocker: model.offloadBlocker,
                     start: {})
                .modifier(OffloadBarRowPadding())
        }
    }
}

/// The ready and finished rows keep the bar's usual size and margins.
private struct OffloadBarRowPadding: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(minHeight: 64)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
    }
}

private struct OffloadBarContent: View {
    @ObservedObject var session: OffloadSession
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch session.phase {
                case .ready:
                    ReadyRow(
                        title: OffloadFormatting.offloadButtonTitle(fileCount: session.newClips.count),
                        blocker: blocker,
                        start: model.startOffload)
                        .modifier(OffloadBarRowPadding())
                        .transition(transition)
                case .running:
                    ProgressRow(session: session)
                        .transition(transition)
                case .finished:
                    CompletionRow(session: session)
                        .modifier(OffloadBarRowPadding())
                        .transition(transition)
                }
            }
            // The wagon drives to the lodge while the files copy and verify, and stays parked
            // (lodge lit) under the summary once they're done.
            if session.phase != .ready {
                WagonStrip(progress: session.progress.fraction,
                           arrived: arrived,
                           stopped: session.phase == .finished && !arrived)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.35), value: session.phase)
    }

    private var arrived: Bool {
        guard session.phase == .finished, let summary = session.summary else { return false }
        return OffloadFeedback.isCleanSuccess(summary)
    }

    private var transition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
    }

    private var blocker: String? { model.offloadBlocker }
}

// MARK: - Ready

private struct ReadyRow: View {
    let title: String
    let blocker: String?
    let start: () -> Void
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            if showsFormatResult {
                FormatResultLine()
            } else if let blocker {
                Label(blocker, systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            } else {
                Label("Ready. Every file is verified with SHA-256 after copying.", systemImage: "checkmark.shield")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: start) {
                Label {
                    Text(title).contentTransition(.numericText())
                } icon: {
                    Image(systemName: "arrow.down.circle.fill")
                }
                .animation(reduceMotion ? nil : .snappy, value: title)
            }
            .buttonStyle(.themeProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(blocker != nil)
            .help(blocker ?? "Copy and verify the new files")
            .accessibilityHint(blocker ?? "")
        }
    }

    /// Right after formatting, say how it went instead of "This card is empty".
    private var showsFormatResult: Bool {
        switch model.formatState {
        case .formatted, .failed: return true
        case .idle, .formatting: return false
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
            let percent = Int(progress.fraction * 100)
            let fileNumber = min(progress.filesDone + 1, max(progress.filesTotal, 1))
            let bytes = OffloadFormatting.bytesProgress(done: progress.bytesDone, total: progress.bytesTotal)

            HStack(spacing: 14) {
                stageLabel(progress.isVerifying)
                    .fixedSize()
                Text(progress.currentFile)
                    .font(.system(size: 12.5, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)

                HStack(spacing: 0) {
                    Text("\(percent)%")
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText(value: Double(percent)))
                    separator
                    Text("\(fileNumber) of \(progress.filesTotal)")
                        .contentTransition(.numericText(value: Double(progress.filesDone)))
                    separator
                    Text(bytes)
                        .contentTransition(.numericText())
                    separator
                    Text(eta)
                }
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
                .animation(reduceMotion ? nil : .snappy, value: progress.bytesDone)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Offload progress")
                .accessibilityValue("\(percent) percent. File \(fileNumber) of \(progress.filesTotal). \(bytes). \(eta)")
                .accessibilityAddTraits(.updatesFrequently)

                Button("Cancel", role: .cancel, action: session.cancel)
                    .keyboardShortcut(.cancelAction)
            }
            .frame(height: 41)
            .padding(.horizontal, 20)
        }
    }

    private var separator: some View {
        Text("·")
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 5)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func stageLabel(_ verifying: Bool) -> some View {
        if verifying {
            Label("Verifying", systemImage: "checkmark.shield.fill")
                .foregroundStyle(.tint)
                .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
                .font(.system(size: 13, weight: .semibold))
        } else {
            Label("Copying", systemImage: "arrow.down.circle.fill")
                .foregroundStyle(.tint)
                .font(.system(size: 13, weight: .semibold))
        }
    }
}

// MARK: - Finished

private struct CompletionRow: View {
    @ObservedObject var session: OffloadSession
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingFailures = false
    /// Bumped once on appear to bounce the result symbol.
    @State private var bounces = 0
    @State private var glowing = false
    @Environment(\.theme) private var theme
    private var plainTheme: Bool { theme.isPlain }

    var body: some View {
        let summary = session.summary ?? OffloadSummary()
        let success = OffloadFeedback.isCleanSuccess(summary)
        HStack(spacing: 14) {
            ZStack {
                if success {
                    // A soft glow in the icon's colours behind the checkmark.
                    Circle()
                        .fill(plainTheme
                              ? AnyShapeStyle(theme.accent.opacity(glowing ? 0.25 : 0))
                              : AnyShapeStyle(theme.borderGradient.opacity(glowing ? 0.45 : 0)))
                        .frame(width: 54, height: 54)
                        .blur(radius: 14)
                }
                if success && !reduceMotion {
                    CompletionBurst(color: theme.burst)
                }
                if success {
                    // The tick draws itself in once verification has finished.
                    DrawnCheckmark(fill: plainTheme ? AnyShapeStyle(theme.accent) : AnyShapeStyle(theme.borderGradient),
                                   tick: theme.onAccent, size: 30)
                        .shadow(color: plainTheme ? .clear : theme.glow.opacity(glowing ? 0.5 : 0), radius: 10)
                } else {
                    Image(systemName: symbol(summary))
                        .foregroundStyle(color(summary))
                        .font(.system(size: 30))
                        .symbolEffect(.bounce, value: bounces)
                }
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(title(summary))
                        .font(.headline)
                    FormatStatusLine()
                }
                // "57 copied" counts up as the summary appears.
                CountUpText(value: Double(summary.copied)) { copied in
                    var counted = summary
                    counted.copied = Int(copied.rounded())
                    return subtitle(counted)
                }
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                FormatResultLine()
                    .font(.callout)
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
            if !session.cardRemoved {
                FormatCardButton()
            }
            Button(action: model.ejectSelectedCard) {
                Label(session.cardRemoved ? "Ejected" : "Eject Card", systemImage: "eject.fill")
            }
            .disabled(session.cardRemoved || model.isEjecting)
            Button("Done", action: model.finishSession)
                .buttonStyle(.themeProminent)
                .keyboardShortcut(.defaultAction)
        }
        .controlSize(.large)
        .onAppear {
            guard !reduceMotion else { glowing = true; return }
            withAnimation(.easeOut(duration: 0.6)) { glowing = true }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                bounces += 1
            }
        }
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
        return s.failed == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
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
