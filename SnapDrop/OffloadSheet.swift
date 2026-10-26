import SwiftUI
import AppKit

/// The sheet that appears when a card is inserted.
struct OffloadSheet: View {
    @ObservedObject var session: OffloadSession
    @ObservedObject var settings: AppSettings
    let ledger: Ledger
    /// Closes the sheet.
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            switch session.phase {
            case .ready: readyView
            case .running: runningView
            case .finished: finishedView
            }
        }
        .padding(24)
        .frame(width: 480)
        .interactiveDismissDisabled(session.phase == .running)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "sdcard.fill")
                .font(.system(size: 34))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.card.name)
                    .font(.title2.weight(.semibold))
                Text(countsLine)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var countsLine: String {
        let size = ByteCountFormatter.string(fromByteCount: session.newBytes, countStyle: .file)
        let new = session.newClips.count
        var line = "\(new) new clip\(new == 1 ? "" : "s") (\(size))"
        if session.alreadyOffloadedCount > 0 {
            line += " · \(session.alreadyOffloadedCount) already offloaded"
        }
        return line
    }

    // MARK: Ready

    @ViewBuilder
    private var readyView: some View {
        if session.newClips.isEmpty {
            Text("Everything on this card has already been offloaded.")
            HStack {
                Spacer()
                Button("Close", action: close)
                    .keyboardShortcut(.defaultAction)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Shoot name").font(.headline)
                TextField("e.g. Beach Shoot", text: $session.shootNameInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(start)
                if let example = session.exampleName {
                    Text("First file: \(example)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Destination").font(.headline)
                HStack {
                    Text(settings.destinationPath ?? "Not chosen yet")
                        .foregroundStyle(settings.destinationPath == nil ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Choose…") { settings.chooseDestination() }
                }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: close)
                    .keyboardShortcut(.cancelAction)
                Button("Offload", action: start)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canStart)
            }
        }
    }

    private var canStart: Bool {
        !session.shootName.isEmpty && settings.destinationURL != nil && !session.newClips.isEmpty
    }

    private func start() {
        guard canStart, let destination = settings.destinationURL else { return }
        session.start(destination: destination, ledger: ledger)
    }

    // MARK: Running

    private var runningView: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProgressView(value: session.progress.fraction)
            Text("Copying \(session.progress.currentFile)")
                .lineLimit(1)
                .truncationMode(.middle)
            Text("\(session.progress.filesDone) of \(session.progress.filesTotal) files")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            HStack {
                Spacer()
                Button("Cancel") { session.cancel() }
                    .keyboardShortcut(.cancelAction)
            }
        }
    }

    // MARK: Finished

    private var finishedView: some View {
        let summary = session.summary ?? OffloadSummary()
        return VStack(alignment: .leading, spacing: 10) {
            if summary.cancelled {
                Label("Offload cancelled", systemImage: "xmark.octagon")
                    .font(.headline)
            } else if summary.failed == 0 {
                Label("Offload complete", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
            } else {
                Label("Finished with problems", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                GridRow { Text("Copied & verified"); Text("\(summary.copied)").monospacedDigit() }
                GridRow { Text("Skipped (already offloaded)"); Text("\(summary.skipped)").monospacedDigit() }
                GridRow { Text("Failed"); Text("\(summary.failed)").monospacedDigit() }
            }

            if !summary.failures.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(summary.failures, id: \.self) { failure in
                            Text(failure).font(.caption).textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
            }

            HStack {
                if let destination = settings.destinationURL {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([destination])
                    }
                }
                Spacer()
                Button("Done", action: close)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
