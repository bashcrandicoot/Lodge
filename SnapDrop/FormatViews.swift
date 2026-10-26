import SwiftUI
import AppKit

/// The confirmation shown before formatting. Cancel is the default button.
enum FormatAlert {
    /// The response for the "Format" button (the second button).
    static let formatResponse = NSApplication.ModalResponse.alertSecondButtonReturn

    static func text(cardName: String, readiness: FormatReadiness) -> (title: String, message: String) {
        let files = readiness.fileCount == 1 ? "The 1 file" : "All \(readiness.fileCount) files"
        let size = ByteCountFormatter.string(fromByteCount: readiness.totalBytes, countStyle: .file)
        var copied = "\(files) (\(size)) on this card were copied and verified"
        if let folder = readiness.copiesFolder {
            copied += " to \((folder as NSString).abbreviatingWithTildeInPath)"
        }
        let message = copied + ".\n\nFormatting erases everything on “\(cardName)”. This can’t be undone."
            + "\n\nTip: formatting in your camera is usually best, because it sets the card up exactly the way the camera expects."
        return ("Format “\(cardName)”?", message)
    }

    static func make(cardName: String, readiness: FormatReadiness) -> NSAlert {
        let (title, message) = text(cardName: cardName, readiness: readiness)
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = title
        alert.informativeText = message
        let cancel = alert.addButton(withTitle: "Cancel")
        cancel.keyEquivalent = "\r"
        let format = alert.addButton(withTitle: "Format")
        format.keyEquivalent = ""
        format.hasDestructiveAction = true
        return alert
    }
}

/// Green "Ready to format" seal.
struct ReadyToFormatBadge: View {
    var body: some View {
        Label("Ready to format", systemImage: "checkmark.seal.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.green)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Color.green.opacity(0.12), in: Capsule())
            .help("Every file on this card has a verified copy at the destination.")
            .accessibilityElement(children: .combine)
    }
}

/// The badge, the "N files not yet offloaded" caption, or formatting progress for the selected card.
struct FormatStatusLine: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        switch model.formatState {
        case .formatting:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Formatting…").font(.caption).foregroundStyle(.secondary)
            }
        case .formatted:
            Label("Formatted", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .idle, .failed:
            if let readiness = model.formatReadiness {
                if readiness.isReady {
                    ReadyToFormatBadge()
                } else if let pending = readiness.pendingText {
                    Text(pending)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Inline result of the last format, shown in the offload bar.
struct FormatResultLine: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        switch model.formatState {
        case .formatted(let name):
            Label("“\(name)” was formatted and is ready for your camera.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .idle, .formatting:
            EmptyView()
        }
    }
}

/// "Format Card…" — enabled only when the card is ready to format.
struct FormatCardButton: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if model.formatState.isFormatting {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Formatting…")
            }
        } else {
            Button("Format Card…", role: .destructive) { model.confirmFormatSelectedCard() }
                .disabled(!model.canFormatSelectedCard)
                .help(model.canFormatSelectedCard
                      ? "Erase this card so it's ready for new footage"
                      : "Available once every file on the card has a verified copy")
        }
    }
}
