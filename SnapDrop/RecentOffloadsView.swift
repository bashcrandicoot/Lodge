import SwiftUI
import AppKit

/// The "Recent Offloads" popover opened from the toolbar.
struct RecentOffloadsView: View {
    @EnvironmentObject private var ledger: Ledger
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let recent = ledger.recent(limit: 50)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Recent Offloads").font(.headline)
                Spacer()
                Text("\(ledger.entries.count) total")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            Divider()
            if let error = ledger.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(10)
            }
            if recent.isEmpty {
                ContentUnavailableView {
                    Label("No Offloads Yet", systemImage: "clock")
                } description: {
                    Text("Files you offload will be listed here.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(recent) { entry in
                    RecentRow(entry: entry)
                        .contextMenu {
                            Button("Show in Finder") { RecentRow.reveal(entry) }
                            Divider()
                            Button("Forget") { model.forgetLedgerEntry(entry) }
                                .disabled(model.isBusy)
                                .help("Remove from the history. The copy itself isn’t touched; the file shows as new on its card again.")
                        }
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 440, height: 480)
    }
}

/// One row: new file name, where it came from, when and how big.
struct RecentRow: View {
    let entry: LedgerEntry

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "film")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(URL(fileURLWithPath: entry.destinationPath).lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(entry.cardName) · \(entry.sourceRelativePath)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(entry.offloadedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.caption)
                Text(OffloadFormatting.bytes(entry.size))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                RecentRow.reveal(entry)
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Show in Finder")
            .accessibilityLabel("Show \(URL(fileURLWithPath: entry.destinationPath).lastPathComponent) in Finder")
        }
        .padding(.vertical, 2)
    }

    static func reveal(_ entry: LedgerEntry) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.destinationPath)])
    }
}

#if DEBUG
#Preview("Recent offloads") {
    RecentOffloadsView().demoEnvironment(DemoData.model(state: .finished))
}
#endif
