import SwiftUI
import AppKit

/// Stage 3: where the clips go, how much space is free, and the folder layout.
struct DestinationStageView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var watcher: VolumeWatcher

    var body: some View {
        StagePanel(number: 3, title: "Destination", state: settings.destinationURL == nil ? .active : .done) {
            if let url = settings.destinationURL {
                chosen(url)
            } else {
                ContentUnavailableView {
                    Label("No Destination", systemImage: "folder.badge.plus")
                } description: {
                    Text("Choose the folder your clips are copied into. You only need to do this once.")
                } actions: {
                    Button("Choose Folder…", action: choose)
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func choose() {
        settings.chooseDestination()
        watcher.refresh()
    }

    private func chosen(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 36, height: 36)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(url.lastPathComponent)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Text((url.path as NSString).abbreviatingWithTildeInPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }
            .accessibilityElement(children: .combine)

            SpaceInfo(url: url, required: model.session?.newBytes)

            FolderLayout(
                root: url.lastPathComponent,
                folders: plannedFolders,
                example: exampleFileName)

            Spacer(minLength: 0)

            HStack {
                Button("Change…", action: choose)
                    .disabled(model.isBusy)
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Label("Show", systemImage: "arrow.up.forward.app")
                }
                .help("Show the destination folder in Finder")
            }
            .controlSize(.small)
        }
    }

    private var shootName: String {
        let name = model.session?.shootName ?? ""
        return name.isEmpty ? NamePreview.placeholderShootName : name
    }

    private var previewItems: [NamePreviewItem] {
        guard let session = model.session else { return [] }
        return NamePreview.preview(clips: session.newClips, shootName: shootName)
    }

    private var plannedFolders: [String] {
        let folders = NamePreview.folders(for: previewItems)
        return folders.isEmpty ? ["YYYY-MM-DD/\(shootName)"] : folders
    }

    private var exampleFileName: String {
        previewItems.first?.newName ?? "YYYY-MM-DD_\(shootName)_0001.mp4"
    }
}

/// "812 GB available · needs 21.6 GB"
private struct SpaceInfo: View {
    let url: URL
    let required: Int64?

    var body: some View {
        let available = VolumeInfo.availableBytes(at: url)
        let total = VolumeInfo.totalBytes(at: url)
        VStack(alignment: .leading, spacing: 4) {
            if let available, let total, total > 0 {
                Gauge(value: Double(total - available), in: 0...Double(total)) {
                    EmptyView()
                }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(isShort(available) ? .red : .accentColor)
                .accessibilityLabel("Destination space used")
            }
            HStack {
                Text(available.map { "\(OffloadFormatting.bytes($0)) available" } ?? "Free space unknown")
                Spacer()
                if let required, required > 0 {
                    Text("needs \(OffloadFormatting.bytes(required))")
                        .foregroundStyle(available.map(isShort) == true ? .red : .secondary)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func isShort(_ available: Int64) -> Bool {
        guard let required else { return false }
        return available < required
    }
}

/// A tiny tree showing how files are laid out at the destination.
private struct FolderLayout: View {
    let root: String
    let folders: [String]
    let example: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Layout")
                .font(.subheadline.weight(.semibold))
                .padding(.bottom, 2)
            row(root, symbol: "folder.fill", indent: 0)
            ForEach(folders.prefix(3), id: \.self) { folder in
                let parts = folder.split(separator: "/").map(String.init)
                if parts.count == 2 {
                    row(parts[0], symbol: "folder", indent: 1)
                    row(parts[1], symbol: "folder", indent: 2)
                }
            }
            row(example, symbol: "film", indent: 3)
        }
        .font(.system(.caption, design: .monospaced))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Files are saved as \(root), then date folder, then shoot folder, for example \(example)")
    }

    private func row(_ text: String, symbol: String, indent: Int) -> some View {
        Label {
            Text(text).lineLimit(1).truncationMode(.middle)
        } icon: {
            Image(systemName: symbol).foregroundStyle(.tint)
        }
        .padding(.leading, CGFloat(indent) * 14)
    }
}

#if DEBUG
#Preview("Destination stage") {
    DestinationStageView()
        .demoEnvironment(DemoData.model(state: .ready))
        .frame(width: 280, height: 420)
        .padding()
}

#Preview("Destination stage – not chosen") {
    DestinationStageView()
        .demoEnvironment(DemoData.model(state: .empty))
        .frame(width: 280, height: 420)
        .padding()
}
#endif
