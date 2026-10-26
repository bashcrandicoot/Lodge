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
                FolderLayout(root: url.lastPathComponent, plan: plan,
                             editable: !model.isBusy && model.session?.plan == nil)
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
                    .help("Choose a folder that isn't one of your favorites")
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

/// The folder tree at the destination, following the templates. Drag a level to move it,
/// drag a token chip onto the tree to add a level, or drop a Finder folder to copy there.
private struct FolderLayout: View {
    let root: String
    let plan: [PlannedFile]
    let editable: Bool

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The slot a level or token would land in (0 = first level, `levels.count` = after the last).
    @State private var dropSlot: Int?

    private struct Level: Identifiable {
        let index: Int
        let template: String
        /// The real folder name for the example clip, or nil when quick dump leaves it out.
        let name: String?
        var id: String { "\(index)-\(template)" }
    }

    private var example: PlannedFile? {
        plan.first { $0.role == .main && $0.category == .video } ?? plan.first { $0.role == .main } ?? plan.first
    }

    private var levels: [Level] {
        let templates = FolderTemplateEditor.levels(settings.folderTemplate)
        let rendered = (example?.folder ?? "").split(separator: "/").map(String.init)
        let kept = templates.map { !settings.quickDump || !QuickDump.strip($0).isEmpty }
        let keptCount = kept.filter { $0 }.count
        var next = 0
        return templates.enumerated().map { index, template in
            guard kept[index] else { return Level(index: index, template: template, name: nil) }
            defer { next += 1 }
            let name = rendered.count == keptCount && next < rendered.count ? rendered[next] : TemplateDescription.level(template)
            return Level(index: index, template: template, name: name)
        }
    }

    var body: some View {
        let levels = levels
        let shown = levels.filter { $0.name != nil }.count
        let mainFolders = Set(plan.filter { $0.role == .main }.map(\.folder)).count
        let otherFolders = max(0, mainFolders - 1)
        let proxies = plan.filter { $0.role == .proxy }.count
        let sidecars = plan.filter { $0.role == .sidecar }.count
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text("Layout")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if editable {
                    Text("Drag to rearrange")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.bottom, 3)
            plainRow(root, symbol: "folder.fill", indent: 0)
            ForEach(levels) { level in
                LevelRow(level: level.template, name: level.name, indent: level.index + 1,
                         editable: editable, showsSlotAbove: dropSlot == level.index,
                         remove: { edit { FolderTemplateEditor.remove($0, at: level.index) } })
                    .onDrop(of: [.plainText, .fileURL],
                            delegate: TreeDropDelegate(slot: level.index, dropSlot: $dropSlot, editable: editable,
                                                       apply: applyDrop, useFolder: model.useDroppedFolder))
            }
            Group {
                if let example {
                    plainRow(example.fileName, symbol: example.category.symbol, indent: shown + 1)
                }
                if proxies > 0 {
                    plainRow("Proxies", symbol: "folder", indent: shown + 1, detail: countText(proxies, "proxy", "proxies"))
                }
                if sidecars > 0 {
                    plainRow("Sidecars", symbol: "folder", indent: shown + 1, detail: countText(sidecars, "file", "files"))
                }
                if otherFolders > 0 {
                    Text("+ \(otherFolders) more \(otherFolders == 1 ? "folder" : "folders")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, CGFloat(shown) * 12 + 20)
                }
            }
            .overlay(alignment: .top) {
                if dropSlot == levels.count { DropSlotLine().offset(y: -2) }
            }
            // The file rows are the "after the last level" slot.
            .onDrop(of: [.plainText, .fileURL],
                    delegate: TreeDropDelegate(slot: levels.count, dropSlot: $dropSlot, editable: editable,
                                               apply: applyDrop, useFolder: model.useDroppedFolder))

            if editable {
                TokenPalette(add: { token in edit { FolderTemplateEditor.insert(token, into: $0) } })
                    .padding(.top, 8)
            }
        }
        .font(.system(.caption, design: .monospaced))
        .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.2), value: settings.folderTemplate)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: dropSlot)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Files are saved like \(([root] + levels.compactMap(\.name) + [example?.fileName ?? ""]).joined(separator: ", then "))")
    }

    private func countText(_ count: Int, _ one: String, _ many: String) -> String {
        "\(count) \(count == 1 ? one : many)"
    }

    private func edit(_ change: (String) -> String) {
        guard editable else { return }
        let updated = change(settings.folderTemplate)
        guard updated != settings.folderTemplate, NamingTemplates(folder: updated, file: settings.fileTemplate) != nil else {
            NSSound.beep()
            return
        }
        settings.folderTemplate = updated
    }

    private func applyDrop(_ payload: FolderTemplateEditor.Payload, slot: Int) {
        edit { FolderTemplateEditor.drop(payload, on: slot, in: $0) }
    }

    private func plainRow(_ text: String, symbol: String, indent: Int, detail: String? = nil) -> some View {
        HStack(spacing: 4) {
            Label {
                Text(text).lineLimit(1).truncationMode(.middle)
            } icon: {
                Image(systemName: symbol).foregroundStyle(.tint)
            }
            if let detail {
                Spacer(minLength: 4)
                Text(detail).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .padding(.leading, CGFloat(indent) * 12)
    }
}

/// One folder level: draggable, with a remove button on hover.
private struct LevelRow: View {
    let level: String
    /// nil = left out by quick dump.
    let name: String?
    let indent: Int
    let editable: Bool
    let showsSlotAbove: Bool
    let remove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "line.3.horizontal")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .opacity(editable && hovering ? 1 : 0)
                .frame(width: 10)
            Label {
                Text(name ?? TemplateDescription.level(level))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .strikethrough(name == nil, color: .secondary)
            } icon: {
                Image(systemName: "folder").foregroundStyle(.tint)
            }
            .opacity(name == nil ? 0.45 : 1)
            Spacer(minLength: 4)
            if name == nil {
                TreeTag("Quick dump")
            } else if hovering || !editable {
                Text(TemplateDescription.level(level))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if editable && hovering {
                Button(action: remove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove this folder level")
                .accessibilityLabel("Remove \(TemplateDescription.level(level)) level")
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.primary.opacity(editable && hovering ? 0.07 : 0)))
        .padding(.leading, CGFloat(indent) * 12 - 14)
        .overlay(alignment: .top) { if showsSlotAbove { DropSlotLine().offset(y: -2).padding(.leading, CGFloat(indent) * 12) } }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onDrag {
            NSItemProvider(object: (FolderTemplateEditor.levelPrefix + String(indent - 1)) as NSString)
        } preview: {
            DragChip(text: name ?? TemplateDescription.level(level), symbol: "folder")
        }
        .disabled(!editable)
        .help(editable ? "Drag to move this folder level" : "")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(name.map { "Folder \($0), \(TemplateDescription.level(level))" }
                            ?? "\(TemplateDescription.level(level)) folder, left out by quick dump")
    }
}

/// Where a dragged level or token will land.
private struct DropSlotLine: View {
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            Circle().strokeBorder(theme.accent, lineWidth: 1.5).frame(width: 6, height: 6)
            Capsule().fill(theme.accent).frame(height: 2)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.6, anchor: .leading)))
        .allowsHitTesting(false)
    }
}

private struct TreeTag: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.secondary.opacity(0.15), in: Capsule())
    }
}

/// Tokens you can drag onto the tree (or click to add as the last level).
private struct TokenPalette: View {
    let add: (TemplateToken) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Add a level")
                .font(.caption2)
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 4) {
                ForEach(FolderTemplateEditor.levelTokens) { token in
                    TokenChip(token: token, add: add)
                }
            }
        }
    }
}

private struct TokenChip: View {
    let token: TemplateToken
    let add: (TemplateToken) -> Void
    @State private var hovering = false

    var body: some View {
        let title = TemplateDescription.level(token.placeholder)
        Button { add(token) } label: {
            Text(title)
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(hovering ? 0.14 : 0.08), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .onDrag {
            NSItemProvider(object: (FolderTemplateEditor.tokenPrefix + token.rawValue) as NSString)
        } preview: {
            DragChip(text: title, symbol: "folder.badge.plus")
        }
        .help("\(token.summary). Drag onto the tree, or click to add it as the last folder.")
        .accessibilityLabel("Add \(title) folder level")
    }
}

private struct DragChip: View {
    let text: String
    let symbol: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: Capsule())
    }
}

/// Drops on the tree: a level or token (plain-text payload) edits the template;
/// a Finder folder becomes the destination.
private struct TreeDropDelegate: DropDelegate {
    let slot: Int
    @Binding var dropSlot: Int?
    let editable: Bool
    let apply: (FolderTemplateEditor.Payload, Int) -> Void
    let useFolder: @MainActor (URL) -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL]) || (editable && info.hasItemsConforming(to: [.plainText]))
    }

    func dropEntered(info: DropInfo) {
        if editable && !info.hasItemsConforming(to: [.fileURL]) { dropSlot = slot }
    }

    func dropExited(info: DropInfo) {
        if dropSlot == slot { dropSlot = nil }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: info.hasItemsConforming(to: [.fileURL]) ? .copy : .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dropSlot = nil
        if info.hasItemsConforming(to: [.fileURL]) {
            return FolderDrop.load(info.itemProviders(for: [.fileURL]), use: useFolder)
        }
        guard editable, let provider = info.itemProviders(for: [.plainText]).first else { return false }
        let slot = slot
        let apply = apply
        _ = provider.loadObject(ofClass: String.self) { text, _ in
            guard let text, let payload = FolderTemplateEditor.payload(text) else { return }
            Task { @MainActor in
                apply(payload, slot)
                Haptics.dropAccepted()
            }
        }
        return true
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
