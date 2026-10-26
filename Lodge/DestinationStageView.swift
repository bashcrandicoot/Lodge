import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Stage 3: where the clips go, how much space is free, and the folder layout.
struct DestinationStageView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.theme) private var theme
    /// A Finder folder is being dragged over the stage.
    @State private var folderTargeted = false

    var body: some View {
        StagePanel(number: 3, title: "Destination", state: settings.destinationURL == nil ? .active : .done) {
            if let url = settings.destinationURL {
                chosen(url)
            } else {
                ContentUnavailableView {
                    Label("No Destination", systemImage: "folder.badge.plus")
                } description: {
                    Text("Choose the folder your media is copied into, or drop one here from Finder.")
                } actions: {
                    Button("Choose Folder…", action: choose)
                        .buttonStyle(.themeProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // Drop a folder from Finder anywhere on the stage to copy into it.
        .onDrop(of: [.fileURL], isTargeted: $folderTargeted) { providers in
            FolderDrop.load(providers) { url in model.useDroppedFolder(url) }
        }
        .overlay { if folderTargeted && !model.isBusy { FolderDropHighlight() } }
        .scaleEffect(folderTargeted && !model.isBusy && !reduceMotion ? 1.015 : 1)
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(duration: 0.3, bounce: 0.35), value: folderTargeted)
    }

    private func choose() {
        model.chooseOtherDestination()
    }

    private func chosen(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            DestinationPicker(url: url)

            // Until a card is scanned there's nothing to lay out, so just show the folder.
            SpaceInfo(url: url, required: plan.isEmpty ? nil : model.session?.newBytes)

            // The tree stays empty until a card is loaded and has something to copy.
            if !plan.isEmpty {
                FolderLayout(root: url, plan: plan,
                             editable: !model.isBusy && model.session?.plan == nil)
                    .layoutPriority(1)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }

            Spacer(minLength: 0)

            Label("Drop a folder from Finder here to copy into it", systemImage: "arrow.down.to.line.compact")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .accessibilityHidden(true)

            HStack {
                Button("Change…", action: choose)
                    .disabled(model.isBusy)
                    .help("Choose a folder that isn’t one of your favorites")
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Label("Show", systemImage: "arrow.up.forward.app")
                }
                .disabled(!DestinationStore.isFolder(url.path))
                .help("Show the destination folder in Finder")
            }
            .controlSize(.small)
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.4), value: plan.isEmpty)
    }

    /// The planned names (with placeholders) once a scanned card has something to copy.
    private var plan: [PlannedFile] {
        guard let session = model.session, session.plan != nil || !session.newClips.isEmpty else { return [] }
        return model.previewPlan(for: session)
    }
}

/// The current destination; click it for your favorites.
private struct DestinationPicker: View {
    let url: URL
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var destinations: DestinationStore
    @State private var showingList = false
    @State private var hovering = false

    var body: some View {
        let favorite = model.currentFavorite
        let connected = DestinationStore.isFolder(url.path)
        let title = favorite?.displayName ?? url.lastPathComponent
        Button { showingList.toggle() } label: {
            HStack(spacing: 10) {
                Group {
                    if connected {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            .resizable()
                    } else {
                        Image(systemName: "externaldrive.badge.xmark")
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(.secondary)
                            .padding(4)
                    }
                }
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Text(connected ? (url.path as NSString).abbreviatingWithTildeInPath : "Not connected")
                        .font(.caption)
                        .foregroundStyle(connected ? Color.secondary : Color.orange)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(hovering || showingList ? 0.06 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .padding(-6)
        .disabled(model.isBusy)
        .popover(isPresented: $showingList, arrowEdge: .bottom) {
            FavoritesList(close: { showingList = false })
                .environmentObject(model)
                .environmentObject(destinations)
        }
        .help("Choose where files are copied")
        .accessibilityLabel("Destination, \(title)\(connected ? "" : ", not connected")")
        .accessibilityHint("Shows your favorite destinations")
    }
}

/// The popover: favorites (with free space), then "Choose Other Folder…" and "Edit Favorites…".
private struct FavoritesList: View {
    let close: () -> Void
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var destinations: DestinationStore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Favorites")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 4)
            if destinations.favorites.isEmpty {
                Text("Save folders you use often to switch between them here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            ForEach(destinations.favorites) { favorite in
                FavoriteRow(favorite: favorite,
                            isCurrent: favorite.id == model.currentFavorite?.id,
                            isDefault: favorite.id == destinations.defaultFavorite?.id,
                            isConnected: destinations.isConnected(favorite)) {
                    model.useFavorite(favorite)
                    close()
                }
            }
            Divider().padding(.vertical, 4)
            if model.currentFavorite == nil, let path = model.settings.destinationPath {
                PopoverAction(title: "Add “\(URL(fileURLWithPath: path).lastPathComponent)” to Favorites",
                              symbol: "star") {
                    model.addCurrentDestinationToFavorites()
                }
            }
            PopoverAction(title: "Choose Other Folder…", symbol: "folder") {
                close()
                model.chooseOtherDestination()
            }
            PopoverAction(title: "Edit Favorites…", symbol: "slider.horizontal.3") {
                close()
                UserDefaults.standard.set(SettingsTab.destinations.rawValue, forKey: SettingsTab.storageKey)
                openSettings()
            }
        }
        .padding(6)
        .frame(width: 320)
        // Re-read "Not connected" when a drive comes or goes while this is open.
        .id(destinations.mountRevision)
    }
}

private struct FavoriteRow: View {
    let favorite: FavoriteDestination
    let isCurrent: Bool
    let isDefault: Bool
    let isConnected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: favorite.symbol)
                    .foregroundStyle(isConnected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(favorite.displayName)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        if isDefault {
                            Text("Default")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.15), in: Capsule())
                        }
                    }
                    Text(isConnected ? favorite.abbreviatedPath : "Not connected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 6)
                if isConnected, let free = VolumeInfo.availableBytes(at: favorite.url) {
                    Text("\(OffloadFormatting.bytes(free)) free")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tint)
                    .opacity(isCurrent ? 1 : 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(hovering && isConnected ? 0.08 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isConnected)
        .opacity(isConnected ? 1 : 0.55)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
        .help(isConnected ? favorite.path : "\(favorite.path) isn’t connected")
    }
}

private struct PopoverAction: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(hovering ? 0.08 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// "812 GB available · needs 21.6 GB"
private struct SpaceInfo: View {
    let url: URL
    let required: Int64?

    @Environment(\.theme) private var theme
    private var plainTheme: Bool { theme.isPlain }

    private var gaugeFill: AnyShapeStyle {
        plainTheme ? AnyShapeStyle(theme.accent)
                   : AnyShapeStyle(LinearGradient(colors: theme.gaugeColors, startPoint: .leading, endPoint: .trailing))
    }

    var body: some View {
        let available = VolumeInfo.availableBytes(at: url)
        let total = VolumeInfo.totalBytes(at: url)
        VStack(alignment: .leading, spacing: 4) {
            if let available, let total, total > 0 {
                CapacityBar(fraction: Double(total - available) / Double(total),
                            fill: isShort(available) ? AnyShapeStyle(Color.red) : gaugeFill)
                    .accessibilityElement()
                    .accessibilityLabel("Destination space used")
                    .accessibilityValue("\(Int((Double(total - available) / Double(total) * 100).rounded())) percent")
            }
            HStack {
                Text(available.map { "\(OffloadFormatting.bytes($0)) available" } ?? "Free space unknown")
                Spacer()
                if let required, required > 0 {
                    Text("needs \(OffloadFormatting.bytes(required))")
                        .foregroundStyle(available.map(isShort) == true ? Color.red : Color.secondary)
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

/// A slim capacity bar drawn in SwiftUI, so it follows the theme
/// (the system gauge always uses the app's accent colour asset).
private struct CapacityBar: View {
    let fraction: Double
    let fill: AnyShapeStyle

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule()
                    .fill(fill)
                    .frame(width: max(6, proxy.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 6)
        .animation(.easeInOut(duration: 0.3), value: fraction)
    }
}

/// Reads a dropped Finder item (on the main actor) and hands over the folder.
enum FolderDrop {
    static func load(_ providers: [NSItemProvider], use: @escaping @MainActor (URL) -> Bool) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) })
        else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in
                if use(url) { Haptics.dropAccepted() } else { NSSound.beep() }
            }
        }
        return true
    }
}

/// The accent outline shown while a folder is dragged over the Destination stage.
private struct FolderDropHighlight: View {
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.accent.opacity(0.10))
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(theme.accent, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
            VStack(spacing: 8) {
                Image(systemName: "folder.fill.badge.plus")
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(theme.accent)
                Text("Copy Files Here")
                    .font(.headline)
            }
            .padding(18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .allowsHitTesting(false)
        .transition(.opacity)
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
