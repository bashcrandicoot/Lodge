import SwiftUI

/// A small ⓘ next to a control. Hovering it for a moment (or clicking it) shows `text` in a
/// little popover; the same text is the tooltip and what VoiceOver reads.
struct InfoHint: View {
    let text: String
    /// What the hint is about, for VoiceOver ("Quick dump").
    let subject: String

    @State private var showing = false
    @State private var hoverTask: Task<Void, Never>?

    var body: some View {
        Button { showing.toggle() } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
                .imageScale(.small)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(text)
        .onHover { inside in
            hoverTask?.cancel()
            hoverTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(inside ? 450 : 150))
                guard !Task.isCancelled else { return }
                showing = inside
            }
        }
        .onDisappear { hoverTask?.cancel() }
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 240, alignment: .leading)
                .padding(12)
        }
        .accessibilityLabel("About \(subject)")
        .accessibilityHint(text)
    }
}

enum QuickDumpHelp {
    static let text = "Skips the project name and dumps all the footage straight into a dated folder."
}
