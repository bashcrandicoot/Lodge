import SwiftUI
import AppKit

/// The main window: destination folder, detected cards, and recent offloads.
struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var watcher: VolumeWatcher
    @EnvironmentObject private var ledger: Ledger

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            destinationSection
            cardsSection
            recentSection
        }
        .padding(20)
        .sheet(item: $model.session) { session in
            OffloadSheet(
                session: session,
                settings: settings,
                ledger: ledger,
                close: { model.session = nil })
        }
    }

    // MARK: Destination

    private var destinationSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                    Text(settings.destinationPath ?? "Choose a folder to copy clips into")
                        .foregroundStyle(settings.destinationPath == nil ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    if let url = settings.destinationURL {
                        Button("Show") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    }
                    Button(settings.destinationPath == nil ? "Choose…" : "Change…") {
                        settings.chooseDestination()
                        watcher.refresh()
                    }
                }
                Text("Clips are saved as YYYY-MM-DD/ShootName/YYYY-MM-DD_ShootName_0001.mp4")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(4)
        } label: {
            Text("Destination").font(.headline)
        }
    }

    // MARK: Cards

    private var cardsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                if watcher.cards.isEmpty {
                    Text("No cards detected. Insert an SD card and SnapDrop will open automatically.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(watcher.cards) { card in
                        HStack {
                            Image(systemName: "sdcard")
                            Text(card.name)
                            Text(card.url.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Offload…") { model.openSession(for: card, automatic: false) }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        } label: {
            Text("Cards").font(.headline)
        }
    }

    // MARK: Recent offloads

    private var recentSection: some View {
        GroupBox {
            let recent = ledger.recent(limit: 50)
            VStack(alignment: .leading, spacing: 6) {
                if let error = ledger.lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
                if recent.isEmpty {
                    Text("Nothing offloaded yet.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    List(recent) { entry in
                        RecentRow(entry: entry)
                    }
                    .listStyle(.inset)
                }
            }
            .padding(4)
        } label: {
            Text("Recent offloads").font(.headline)
        }
        .frame(maxHeight: .infinity)
    }
}

/// One row in the "Recent offloads" list.
private struct RecentRow: View {
    let entry: LedgerEntry

    var body: some View {
        HStack {
            Image(systemName: "film")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(URL(fileURLWithPath: entry.destinationPath).lastPathComponent)
                Text("\(entry.cardName) · \(entry.sourceRelativePath)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(entry.offloadedAt, format: .dateTime.year().month().day().hour().minute())
                    .font(.caption)
                Text(ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.destinationPath)])
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Show in Finder")
        }
    }
}
