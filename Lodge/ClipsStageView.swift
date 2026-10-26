import SwiftUI

/// Stage 2 ("Media"): the files on the selected card, the name fields, and a live
/// preview of the names they'll get.
struct ClipsStageView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let session = model.session {
            ClipsStageContent(session: session)
                .id(ObjectIdentifier(session))   // a new card starts fresh (filter, row animation)
        } else {
            StagePanel(number: 2, title: "Media", state: .pending) {
                VStack {
                    Spacer()
                    if model.isScanning {
                        ProgressView("Looking for media…")
                    } else {
                        Label("Media appears here once a card is inserted.", systemImage: "photo.on.rectangle.angled")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct ClipsStageContent: View {
    @ObservedObject var session: OffloadSession
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @FocusState private var nameFocused: Bool
    /// The preview's category filter (`nil` = everything).
    @State private var filter: MediaCategory?
    /// Which list the preview shows.
    @State private var scope: ListScope = .toCopy
    /// Turns true right after the list first appears, so its rows can fade in one by one.
    @State private var revealed = false
    /// Files picked for Quick Look (never changes what's offloaded).
    @State private var selection = MediaSelection()
    /// The file showing "No preview available".
    @State private var noPreviewID: String?
    /// The grid's width, for moving up and down a row with the arrow keys.
    @State private var gridWidth: CGFloat = 0
    @FocusState private var listFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.theme) private var theme

    private static let tileMinimum: CGFloat = 132
    private static let tileSpacing: CGFloat = 8

    private var needs: NamingNeeds { NamingNeeds(settings.effectiveNaming) }

    var body: some View {
        StagePanel(number: 2, title: "Media", state: stageState) {
            VStack(alignment: .leading, spacing: 14) {
                counts
                nameFields
                preview
            }
        }
        .background { QuickLookHost().frame(width: 0, height: 0) }
        .onChange(of: session.phase, initial: true) { _, phase in
            // Thumbnails wait their turn while the card is busy copying.
            model.thumbnails.isThrottled = phase == .running
        }
        .onChange(of: scope) { _, _ in
            selection.clear()
            QuickLookController.shared.close()
        }
        .task(id: noPreviewID) {
            guard noPreviewID != nil else { return }
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { noPreviewID = nil }
        }
        .onAppear {
            if session.phase == .ready && !session.newClips.isEmpty && !settings.quickDump { nameFocused = true }
            #if DEBUG
            // Screenshots: `-LodgeDemoScope skipped|offloaded` opens that list.
            if DemoData.launchState != nil, let raw = UserDefaults.standard.string(forKey: "LodgeDemoScope"),
               let demoScope = ListScope(rawValue: raw) {
                scope = demoScope
            }
            // `-LodgeDemoQuickLook <file name>` selects that file and opens Quick Look.
            if DemoData.launchState != nil, let name = UserDefaults.standard.string(forKey: "LodgeDemoQuickLook"),
               let clip = session.inventory.all.first(where: { $0.url.lastPathComponent == name }) {
                let order = demoPreviewOrder
                selection.click(clip.id, modifier: .none, order: order)
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    showPreview(order: order, focus: clip.id)
                }
            }
            #endif
        }
    }

    private var stageState: StageState {
        if session.phase != .ready { return .done }
        if session.newClips.isEmpty { return .done }
        let missing = (needs.project && session.project.isEmpty)
            || (needs.camera && model.cameraTokenValue(for: session).isEmpty)
        return missing ? .active : .done
    }

    // MARK: Counts

    private var counts: some View {
        let counts = session.categoryCounts
        return HStack(alignment: .top, spacing: 6) {
            FlowLayout(spacing: 6) {
                ForEach(MediaCategory.allCases.filter { counts[$0, default: 0] > 0 }) { category in
                    CountPill(text: category.countText(counts[category, default: 0]), systemImage: category.symbol)
                }
                if session.newClips.isEmpty {
                    CountPill(text: "Nothing new", systemImage: "tray")
                }
                if session.alreadyOffloadedCount > 0 {
                    CountPill(text: "\(session.alreadyOffloadedCount) already offloaded",
                              systemImage: "checkmark.circle", tint: .secondary)
                }
                if session.missingCopyCount > 0 {
                    Button { scope = .offloaded } label: {
                        CountPill(text: "\(session.missingCopyCount) missing at destination",
                                  systemImage: "exclamationmark.triangle.fill", tint: .orange)
                    }
                    .buttonStyle(.plain)
                    .help("These files were offloaded before, but their copies are gone or changed size. They aren’t copied again unless you choose Re-offload.")
                }
                if !session.skippedShort.isEmpty && session.phase == .ready {
                    Button { scope = .skipped } label: {
                        CountPill(text: shortChipText, systemImage: "timer", tint: .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Videos shorter than \(DurationFormatting.threshold(session.shortRule.threshold)) stay on the card with their sidecars. Change this in Settings ▸ General.")
                }
                if session.offloadedInView > 0 && session.phase == .ready {
                    ReoffloadMenu(session: session)
                }
            }
            Spacer(minLength: 0)
            CountUpText(value: Double(session.newBytes)) { OffloadFormatting.bytes(Int64($0.rounded())) }
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel("Total size \(OffloadFormatting.bytes(session.newBytes))")
        }
    }

    private var shortChipText: String {
        let count = session.skippedShort.clips.count
        return count == 1 ? "1 short clip skipped" : "\(count) short clips skipped"
    }

    // MARK: Project + camera

    private var nameFields: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
            GridRow {
                fieldLabel("Project")
                NameField(
                    title: "Project",
                    prompt: settings.quickDump ? "Not needed for a quick dump"
                        : needs.project ? "e.g. Coastline" : "Optional, not in the template",
                    text: $session.projectInput,
                    isDisabled: isLocked || settings.quickDump,
                    recents: settings.recentProjects,
                    clearRecents: settings.clearRecentProjects,
                    focus: $nameFocused)
            }
            GridRow {
                fieldLabel("Camera")
                CameraField(selection: session.cameraID, isUsed: needs.camera, isDisabled: isLocked)
            }
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                QuickDumpToggle(isDisabled: session.phase != .ready)
            }
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.trailing)
    }

    private var isLocked: Bool { session.phase != .ready || session.newClips.isEmpty }

    // MARK: Preview

    @ViewBuilder
    private var preview: some View {
        if session.inventory.fileCount == 0 {
            ContentUnavailableView {
                Label("Card Is Empty", systemImage: "sdcard")
            } description: {
                Text("There's nothing on this card to offload.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let scopes = availableScopes
            let shown = scopes.contains(scope) ? scope : .toCopy
            VStack(alignment: .leading, spacing: 6) {
                switch shown {
                case .toCopy: toCopyList(scopes: scopes)
                case .offloaded: offloadedList(scopes: scopes)
                case .skipped: skippedList(scopes: scopes)
                }
            }
        }
    }

    private var availableScopes: [ListScope] {
        var scopes: [ListScope] = [.toCopy]
        if session.offloadedInView > 0 && session.phase == .ready { scopes.append(.offloaded) }
        if !session.skippedShort.isEmpty && session.phase == .ready { scopes.append(.skipped) }
        return scopes
    }

    /// "Name Preview", or a pop-up to switch lists when there's more than one.
    @ViewBuilder
    private func listHeader(scopes: [ListScope], trailing: String) -> some View {
        HStack {
            if scopes.count > 1 {
                Menu {
                    Picker("Show", selection: $scope) {
                        ForEach(scopes, id: \.self) { scope in
                            Text(title(of: scope)).tag(scope)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } label: {
                    Text(title(of: scopes.contains(scope) ? scope : .toCopy))
                        .font(.subheadline.weight(.semibold))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Switch between the files to copy, files offloaded before and skipped short clips")
                .accessibilityLabel("Show list")
            } else {
                Text(title(of: .toCopy))
                    .font(.subheadline.weight(.semibold))
            }
            Spacer()
            Text(trailing)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            MediaLayoutPicker(layout: $settings.mediaLayout)
        }
    }

    private var layout: MediaLayout { settings.mediaLayout }

    private func title(of scope: ListScope) -> String {
        switch scope {
        case .toCopy: return "Name Preview"
        case .offloaded: return "Already Offloaded (\(session.offloadedInView))"
        case .skipped: return "Short Clips Skipped (\(session.skippedShort.clips.count))"
        }
    }

    @ViewBuilder
    private func toCopyList(scopes: [ListScope]) -> some View {
        if session.newClips.isEmpty {
            listHeader(scopes: scopes, trailing: "")
            nothingToCopy
        } else {
            let plan = model.previewPlan(for: session)
            let placeholder = model.previewHasPlaceholders(for: session)
            let present = MediaCategory.allCases.filter { category in plan.contains { $0.category == category } }
            let activeFilter = filter.flatMap { present.contains($0) ? $0 : nil }
            let items = activeFilter.map { category in plan.filter { $0.category == category } } ?? plan

            listHeader(scopes: scopes, trailing: folderSummary(plan))
            if present.count > 1 {
                Picker("Show", selection: $filter) {
                    Text("All").tag(MediaCategory?.none)
                    ForEach(present) { category in
                        Label(category.title, systemImage: category.symbol).tag(Optional(category))
                    }
                }
                .pickerStyle(.segmented)
                .themeControlTint()
                .labelsHidden()
                .controlSize(.small)
                .accessibilityLabel("Show file type")
            }
            if layout == .grid {
                toCopyGrid(items, placeholder: placeholder)
            } else {
                toCopyRows(items, placeholder: placeholder)
            }
        }
    }

    private func toCopyRows(_ items: [PlannedFile], placeholder: Bool) -> some View {
        let order = items.map(\.id)
        let thumbnails = settings.showListThumbnails ? model.thumbnails : nil
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        PreviewRow(item: item, isPlaceholder: placeholder,
                                   isActive: isRunning && item.id == session.progress.currentID,
                                   isVerified: session.verifiedIDs.contains(item.id),
                                   isReoffload: session.reoffloadingIDs.contains(item.id),
                                   duration: session.duration(of: item.clip),
                                   isIncludedShort: session.isIncludedShortClip(item.clip),
                                   thumbnails: thumbnails)
                            .background(rowBackground(index: index, id: item.id))
                            .staggeredReveal(index: index, revealed: revealed, reduceMotion: reduceMotion)
                            .modifier(itemInteractions(item.clip, order: order))
                            .id(item.id)
                    }
                }
            }
            .onAppear {
                revealed = true
                scrollToCurrent(proxy, animated: false)
            }
            .onChange(of: session.progress.currentID) { _, _ in
                scrollToCurrent(proxy, animated: !reduceMotion)
            }
        }
        .listBox()
        .modifier(listKeys(order: order, columns: 1))
    }

    private func toCopyGrid(_ items: [PlannedFile], placeholder: Bool) -> some View {
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let tiles = TileFolding.fold(items.map(\.id), primaryOf: SidecarMatcher.match(items.map(\.clip), rules: session.fileRules).primary)
        let order = tiles.map(\.id)
        // While copying a sidecar, keep its clip's tile in view.
        let tileOf = Dictionary(tiles.flatMap { tile in ([tile.id] + tile.sidecars).map { ($0, tile.id) } },
                                uniquingKeysWith: { first, _ in first })
        return ScrollViewReader { proxy in
            ScrollView {
                grid {
                    ForEach(Array(tiles.enumerated()), id: \.element.id) { index, tile in
                        if let item = byID[tile.id] {
                            MediaTile(info: tileInfo(item, sidecars: tile.sidecars.compactMap { byID[$0] }, placeholder: placeholder),
                                      provider: model.thumbnails,
                                      isSelected: selection.contains(item.id))
                                .staggeredReveal(index: index, revealed: revealed, reduceMotion: reduceMotion)
                                .modifier(itemInteractions(item.clip, order: order))
                                .id(item.id)
                        }
                    }
                }
            }
            .onAppear {
                revealed = true
                scrollToCurrent(proxy, animated: false, tileOf: tileOf)
            }
            .onChange(of: session.progress.currentID) { _, _ in
                scrollToCurrent(proxy, animated: !reduceMotion, tileOf: tileOf)
            }
        }
        .listBox()
        .modifier(listKeys(order: order, columns: gridColumns))
    }

    /// What a "to copy" tile shows: copying (with its sidecars), verified, re-offload…
    private func tileInfo(_ item: PlannedFile, sidecars: [PlannedFile], placeholder: Bool) -> MediaTileInfo {
        let group = [item] + sidecars
        var info = MediaTileInfo(clip: item.clip, name: item.fileName,
                                 detail: item.originalName + " · " + OffloadFormatting.bytes(group.reduce(0) { $0 + $1.size }),
                                 duration: session.duration(of: item.clip),
                                 sidecars: sidecars.count)
        info.isPlaceholderName = placeholder
        info.isReoffload = session.reoffloadingIDs.contains(item.id)
        info.isIncludedShort = session.isIncludedShortClip(item.clip)
        let current = session.progress.currentID
        if group.allSatisfy({ session.verifiedIDs.contains($0.id) }) {
            info.status = .verified
        } else if isRunning, group.contains(where: { $0.id == current }) {
            let total = group.reduce(Int64(0)) { $0 + $1.size }
            let done = group.filter { session.verifiedIDs.contains($0.id) }.reduce(Int64(0)) { $0 + $1.size }
                + session.progress.currentFileBytes
            info.status = .copying(total > 0 ? min(1, Double(done) / Double(total)) : 0)
        }
        return info
    }

    /// Nothing will be copied: say why, and offer the way out.
    private var nothingToCopy: some View {
        ContentUnavailableView {
            if session.missingCopyCount == 0 && !session.skippedShort.isEmpty {
                Label("Only Short Clips", systemImage: "timer")
            } else if session.missingCopyCount > 0 {
                Label("Copies Missing", systemImage: "exclamationmark.triangle")
            } else {
                Label("All Caught Up", systemImage: "checkmark.seal")
            }
        } description: {
            if session.missingCopyCount == 0 && !session.skippedShort.isEmpty {
                Text(session.skippedShort.clips.count == 1
                     ? "The only new video is shorter than \(DurationFormatting.threshold(session.shortRule.threshold))."
                     : "The \(session.skippedShort.clips.count) new videos are all shorter than \(DurationFormatting.threshold(session.shortRule.threshold)).")
            } else if session.missingCopyCount > 0 {
                Text(session.missingCopyCount == 1
                     ? "1 file was offloaded before, but its copy is no longer at the destination."
                     : "\(session.missingCopyCount) files were offloaded before, but their copies are no longer at the destination.")
            } else {
                Text(session.allNewFiles.isEmpty
                     ? "Everything on this card has already been offloaded."
                     : "The new files on this card are types you turned off in Settings.")
            }
        } actions: {
            if session.missingCopyCount > 0 && session.phase == .ready {
                Button("Re-offload Missing Copies") { model.setReoffloadMode(.missing) }
            }
            if !session.skippedShort.isEmpty && session.phase == .ready {
                Button("Include All Short Clips") { session.includeAllShort = true }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Files offloaded before: where their copy is, or that it's missing.
    @ViewBuilder
    private func offloadedList(scopes: [ListScope]) -> some View {
        let entries = model.ledger.entriesByKey()
        let included = { (clip: Clip) in session.includedCategories.contains(clip.category) }
        // Missing copies first: they're the ones that need attention.
        let files = Offloader.order(session.inventory.missing.filter(included))
            + Offloader.order(session.inventory.offloaded.filter(included))
        listHeader(scopes: scopes, trailing: session.missingCopiesInView > 0
                   ? "\(session.missingCopiesInView) missing" : "All copies present")
        if layout == .grid {
            let byID = Dictionary(files.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let tiles = TileFolding.fold(files.map(\.id), primaryOf: SidecarMatcher.match(Offloader.order(files), rules: session.fileRules).primary)
            let order = tiles.map(\.id)
            ScrollView {
                grid {
                    ForEach(tiles, id: \.id) { tile in
                        if let clip = byID[tile.id] {
                            MediaTile(info: offloadedInfo(clip, entry: entries[clip.ledgerKey(volumeIdentity: session.card.identity)],
                                                          sidecars: tile.sidecars.compactMap { byID[$0] }),
                                      provider: model.thumbnails,
                                      isSelected: selection.contains(clip.id))
                                .modifier(itemInteractions(clip, order: order))
                        }
                    }
                }
            }
            .listBox()
            .modifier(listKeys(order: order, columns: gridColumns))
        } else {
            let order = files.map(\.id)
            let thumbnails = settings.showListThumbnails ? model.thumbnails : nil
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(files.enumerated()), id: \.element.id) { index, clip in
                        OffloadedRow(clip: clip,
                                     entry: entries[clip.ledgerKey(volumeIdentity: session.card.identity)],
                                     isMissing: session.offloadedStatus(of: clip) == true,
                                     isReoffload: session.reoffloadingIDs.contains(clip.id),
                                     thumbnails: thumbnails)
                            .background(rowBackground(index: index, id: clip.id))
                            .modifier(itemInteractions(clip, order: order))
                    }
                }
            }
            .listBox()
            .modifier(listKeys(order: order, columns: 1))
        }
    }

    private func offloadedInfo(_ clip: Clip, entry: LedgerEntry?, sidecars: [Clip]) -> MediaTileInfo {
        let isMissing = session.offloadedStatus(of: clip) == true
        let name = entry.map { ($0.destinationPath as NSString).lastPathComponent } ?? clip.url.lastPathComponent
        var info = MediaTileInfo(clip: clip, name: name,
                                 detail: isMissing ? "Copy missing" : clip.url.lastPathComponent,
                                 duration: session.duration(of: clip), sidecars: sidecars.count)
        info.status = isMissing || sidecars.contains(where: { session.offloadedStatus(of: $0) == true }) ? .missing : .offloaded
        info.isReoffload = session.reoffloadingIDs.contains(clip.id)
        return info
    }

    /// Short videos left on the card: include them one by one or all at once.
    @ViewBuilder
    private func skippedList(scopes: [ListScope]) -> some View {
        let skipped = session.skippedShort
        HStack {
            listHeader(scopes: scopes, trailing: "")
            Button("Include All") {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { session.includeAllShort = true }
            }
            .controlSize(.small)
            .help("Offload every short clip on this card")
        }
        let order = skipped.clips.map(\.id)
        if layout == .grid {
            ScrollView {
                grid {
                    ForEach(skipped.clips) { clip in
                        let sidecars = skipped.sidecarCounts[clip.relativePath, default: 0]
                        MediaTile(info: MediaTileInfo(clip: clip, name: clip.url.lastPathComponent,
                                                      detail: OffloadFormatting.bytes(clip.size),
                                                      duration: session.duration(of: clip),
                                                      sidecars: sidecars, status: .skipped),
                                  provider: model.thumbnails,
                                  isSelected: selection.contains(clip.id))
                            .accessibilityAction(named: "Include Anyway") { include(clip) }
                            .modifier(itemInteractions(clip, order: order))
                    }
                }
            }
            .listBox()
            .modifier(listKeys(order: order, columns: gridColumns))
        } else {
            let thumbnails = settings.showListThumbnails ? model.thumbnails : nil
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(skipped.clips.enumerated()), id: \.element.id) { index, clip in
                        SkippedRow(clip: clip, duration: session.duration(of: clip),
                                   sidecars: skipped.sidecarCounts[clip.relativePath, default: 0],
                                   thumbnails: thumbnails,
                                   include: { include(clip) })
                            .background(rowBackground(index: index, id: clip.id))
                            .modifier(itemInteractions(clip, order: order))
                    }
                }
            }
            .listBox()
            .modifier(listKeys(order: order, columns: 1))
        }
    }

    // MARK: Grid, selection and Quick Look

    private func grid<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.tileMinimum, maximum: 200), spacing: Self.tileSpacing)],
                  spacing: Self.tileSpacing, content: content)
            .padding(Self.tileSpacing)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { gridWidth = proxy.size.width }
                        .onChange(of: proxy.size.width) { _, width in gridWidth = width }
                }
            }
    }

    /// How many tiles fit across (for ↑/↓).
    private var gridColumns: Int {
        let usable = gridWidth - 2 * Self.tileSpacing + Self.tileSpacing
        return max(1, Int(usable / (Self.tileMinimum + Self.tileSpacing)))
    }

    /// The zebra stripe, or the selection highlight.
    @ViewBuilder
    private func rowBackground(index: Int, id: String) -> some View {
        if selection.contains(id) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(theme.accent.opacity(listFocused ? 0.2 : 0.1))
                .padding(.horizontal, 3)
        } else if !index.isMultiple(of: 2) {
            Color.primary.opacity(0.035)
        }
    }

    /// Click to select (⌘/⇧ for more), double-click for Quick Look, right-click for the menu.
    private func itemInteractions(_ clip: Clip, order: [String]) -> ItemInteractions {
        ItemInteractions(
            fileName: clip.url.lastPathComponent,
            showsNoPreview: Binding(get: { noPreviewID == clip.id },
                                    set: { if !$0, noPreviewID == clip.id { noPreviewID = nil } }),
            click: { click(clip.id, order: order) },
            menu: { AnyView(rowMenu(for: clip, order: order)) })
    }

    private func click(_ id: String, order: [String]) {
        let event = NSApp.currentEvent
        let flags = event?.modifierFlags ?? []
        let modifier: MediaSelection.Modifier = flags.contains(.command) ? .toggle : flags.contains(.shift) ? .extend : .none
        selection.click(id, modifier: modifier, order: order)
        listFocused = true
        noPreviewID = nil
        if modifier == .none && (event?.clickCount ?? 1) >= 2 {
            showPreview(order: order, focus: id)
        } else if QuickLookController.isVisible {
            showPreview(order: order, focus: selection.focus)   // like Finder: the panel follows the selection
        }
    }

    /// Space, arrows and Escape while the list or grid has keyboard focus.
    private func listKeys(order: [String], columns: Int) -> ListKeys {
        ListKeys(
            focus: $listFocused,
            order: order,
            space: {
                if QuickLookController.isVisible {
                    QuickLookController.shared.close()
                } else {
                    showPreview(order: order, focus: selection.focus)
                }
            },
            move: { offset in
                selection.move(by: offset == .up ? -columns : offset == .down ? columns : offset == .left ? -1 : 1, order: order)
                noPreviewID = nil
                if QuickLookController.isVisible { showPreview(order: order, focus: selection.focus) }
            },
            escape: {
                selection.clear()
                noPreviewID = nil
            },
            orderChanged: { new in
                selection.prune(to: new)
                QuickLookController.shared.close()
            })
    }

    private func showPreview(order: [String], focus: String?) {
        let clips = Dictionary(session.inventory.all.map { ($0.relativePath, $0) }, uniquingKeysWith: { first, _ in first })
        let outcome = PreviewQueue.make(order: order, selection: selection.selected, focus: focus) { id in
            clips[id].map { MediaPreviewSupport.canPreview(fileName: $0.url.lastPathComponent) } ?? false
        }
        switch outcome {
        case let .preview(ids, start):
            noPreviewID = nil
            let items = ids.compactMap { clips[$0].map(previewItem) }
            QuickLookController.shared.show(items, start: start) { id in
                selection.follow(id)
            }
        case .unsupported(let id):
            QuickLookController.shared.close()
            if !selection.contains(id) { selection.click(id, modifier: .none, order: order) }
            noPreviewID = id
        case .nothing:
            NSSound.beep()
        }
    }

    private func previewItem(for clip: Clip) -> MediaPreviewItem {
        var url = clip.url
        #if DEBUG
        // Demo files don't exist: preview a picture drawn in the theme instead.
        if model.thumbnails.usesPlaceholders, let image = DemoData.previewImage(for: clip, theme: theme) { url = image }
        #endif
        return MediaPreviewItem(id: clip.relativePath, url: url, title: clip.url.lastPathComponent)
    }

    #if DEBUG
    /// The order the current list or grid shows (for the Quick Look screenshot).
    private var demoPreviewOrder: [String] {
        let items = model.previewPlan(for: session)
        guard layout == .grid else { return items.map(\.id) }
        return TileFolding.fold(items.map(\.id), primaryOf: SidecarMatcher.match(items.map(\.clip), rules: session.fileRules).primary).map(\.id)
    }
    #endif

    private func include(_ clip: Clip) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { session.toggleIncludeShort(clip) }
    }

    /// Right-click on a file: Quick Look, re-offload just this one, include or skip a short clip, or show its copy.
    @ViewBuilder
    private func rowMenu(for clip: Clip, order: [String]) -> some View {
        Button("Quick Look") {
            if !selection.contains(clip.id) { selection.click(clip.id, modifier: .none, order: order) }
            showPreview(order: order, focus: clip.id)
        }
        Divider()
        if session.phase == .ready && session.isShortClip(clip) {
            if session.skippedShort.ids.contains(clip.relativePath) {
                Button("Include Anyway") { include(clip) }
                Button("Include All Short Clips") { session.includeAllShort = true }
            } else {
                Button("Skip This Short Clip") { include(clip) }
            }
        }
        if session.phase == .ready, let missing = session.offloadedStatus(of: clip) {
            let picked = session.reoffloadIDs.contains(clip.relativePath)
            let byMode = session.reoffloadMode == .everything || (session.reoffloadMode == .missing && missing)
            if picked {
                Button("Don’t Re-offload This File") { session.toggleReoffload(clip) }
            } else if !byMode {
                Button("Re-offload This File") { session.toggleReoffload(clip) }
            }
            if let entry = model.ledger.entriesByKey()[clip.ledgerKey(volumeIdentity: session.card.identity)],
               !missing {
                Button("Show Copy in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.destinationPath)])
                }
            }
        }
    }

    private var isRunning: Bool { session.phase == .running }

    /// Keeps the file being copied in view.
    private func scrollToCurrent(_ proxy: ScrollViewProxy, animated: Bool, tileOf: [String: String] = [:]) {
        let current = session.progress.currentID
        guard isRunning, !current.isEmpty else { return }
        withAnimation(animated ? .easeInOut(duration: 0.35) : nil) {
            proxy.scrollTo(tileOf[current] ?? current, anchor: .center)
        }
    }

    private func folderSummary(_ plan: [PlannedFile]) -> String {
        let folders = PlanLayout.folders(plan)
        if folders.count == 1 { return folders[0].isEmpty ? "Destination folder" : folders[0] + "/" }
        return "\(folders.count) folders"
    }
}

/// "C0001.MP4  →  2026-10-25_Coastline_0001.mp4"
private struct PreviewRow: View {
    @Environment(\.theme) private var theme
    let item: PlannedFile
    let isPlaceholder: Bool
    /// The file being copied right now.
    var isActive = false
    /// Copied and checked against the card.
    var isVerified = false
    /// Offloaded before and being copied again.
    var isReoffload = false
    /// The video's length, if known.
    var duration: Double?
    /// A short clip the user chose to offload anyway.
    var isIncludedShort = false
    /// Draws a small thumbnail instead of the file-type symbol (Settings ▸ Appearance).
    var thumbnails: ThumbnailProvider?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var accessibilityText: String {
        var text = "\(item.category.title), \(item.originalName) will be saved as \(item.relativePath)"
        if let primary = item.sidecarOf { text += ", alongside \(primary)" }
        if let duration { text += ", \(DurationFormatting.short(duration)) long" }
        if isIncludedShort { text += ", short clip included anyway" }
        if isReoffload { text += ", re-offload: a new copy" }
        if isVerified { text += ", copied and verified" } else if isActive { text += ", copying now" }
        return text
    }

    var body: some View {
        HStack(alignment: thumbnails == nil ? .firstTextBaseline : .center, spacing: 8) {
            RowIcon(clip: item.clip, isSidecar: item.sidecarOf != nil, thumbnails: thumbnails, tinted: item.sidecarOf == nil)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.fileName)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(isPlaceholder ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 4) {
                    Image(systemName: "arrow.turn.down.right")
                        .imageScale(.small)
                    Text(item.originalName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("·")
                    Text(OffloadFormatting.bytes(item.size))
                        .monospacedDigit()
                    if let duration {
                        Text("· " + DurationFormatting.short(duration))
                            .monospacedDigit()
                            .fixedSize()
                    }
                    if isIncludedShort {
                        Label("short", systemImage: "timer")
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.tint)
                            .lineLimit(1)
                            .fixedSize()
                            .help("Shorter than the “Skip short videos” limit, included anyway")
                    }
                    if let primary = item.sidecarOf {
                        Text("· goes with \(primary)")
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if isReoffload {
                        Label("re-offload", systemImage: "arrow.clockwise")
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.tint)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            status
                .frame(width: 18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, item.sidecarOf == nil ? 10 : 22)
        .padding(.trailing, 10)
        .padding(.vertical, 6)
        .background {
            if isActive {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(theme.accent.opacity(0.13))
                    .overlay(alignment: .leading) {
                        Capsule().fill(theme.accent).frame(width: 3).padding(.vertical, 5)
                    }
                    .padding(.horizontal, 3)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: isActive)
        .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.55), value: isVerified)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }
}

extension PreviewRow {
    /// Trailing status: a spinner while copying, then a green check that pops in.
    @ViewBuilder
    fileprivate var status: some View {
        if isVerified {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .transition(reduceMotion ? .opacity : .scale(scale: 0.2).combined(with: .opacity))
        } else if isActive {
            ProgressView()
                .controlSize(.mini)
                .transition(.opacity)
        }
    }
}

/// A short video left on the card, with an Include button.
private struct SkippedRow: View {
    let clip: Clip
    let duration: Double?
    let sidecars: Int
    var thumbnails: ThumbnailProvider?
    let include: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            RowIcon(clip: clip, isSidecar: false, thumbnails: thumbnails, tinted: false)
                .opacity(thumbnails == nil ? 1 : 0.55)
            VStack(alignment: .leading, spacing: 2) {
                Text(clip.url.lastPathComponent)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 4) {
                    Image(systemName: "timer").imageScale(.small)
                    Text(duration.map(DurationFormatting.short) ?? "Short")
                        .monospacedDigit()
                    Text("· " + OffloadFormatting.bytes(clip.size))
                        .monospacedDigit()
                    if sidecars > 0 {
                        Text(sidecars == 1 ? "· 1 sidecar" : "· \(sidecars) sidecars")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button("Include", action: include)
                .controlSize(.small)
                .help("Offload this clip anyway")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(clip.url.lastPathComponent), short clip"
                            + (duration.map { ", \(DurationFormatting.short($0)) long" } ?? "") + ", skipped")
        .accessibilityAction(named: "Include Anyway", include)
    }
}

/// A file offloaded before: where its copy is, or that it's missing.
private struct OffloadedRow: View {
    let clip: Clip
    let entry: LedgerEntry?
    let isMissing: Bool
    let isReoffload: Bool
    var thumbnails: ThumbnailProvider?

    var body: some View {
        HStack(alignment: thumbnails == nil ? .firstTextBaseline : .center, spacing: 8) {
            RowIcon(clip: clip, isSidecar: false, thumbnails: thumbnails, tinted: false)
                .opacity(thumbnails == nil ? 1 : 0.55)
            VStack(alignment: .leading, spacing: 2) {
                Text(clip.url.lastPathComponent)
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Group {
                    if isMissing {
                        Label("Copy missing at the destination", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    } else if let entry {
                        Text("Copy: " + (entry.destinationPath as NSString).abbreviatingWithTildeInPath)
                            .truncationMode(.middle)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            if isReoffload {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .foregroundStyle(.tint)
                    .help("Will be copied again as a new copy")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(clip.url.lastPathComponent), "
                            + (isMissing ? "copy missing at the destination" : "offloaded")
                            + (isReoffload ? ", will be re-offloaded" : ""))
    }
}

/// "Re-offload…": copy missing copies, or the whole card, again.
private struct ReoffloadMenu: View {
    @ObservedObject var session: OffloadSession
    @EnvironmentObject private var model: AppModel
    @Environment(\.theme) private var theme

    private var isActive: Bool { !session.reoffloadingIDs.isEmpty }

    var body: some View {
        Menu {
            Toggle("Re-offload Missing Copies" + (session.missingCopiesInView > 0 ? " (\(session.missingCopiesInView))" : ""),
                   isOn: modeBinding(.missing))
                .disabled(session.missingCopiesInView == 0)
            Toggle("Re-offload Everything on This Card…", isOn: modeBinding(.everything))
            if isActive {
                Divider()
                Button("Don’t Re-offload") {
                    session.reoffloadIDs = []
                    model.setReoffloadMode(.off)
                }
            }
        } label: {
            Label(isActive ? "Re-offloading \(session.reoffloadingIDs.count)" : "Re-offload…",
                  systemImage: "arrow.clockwise")
                .font(.caption.weight(.medium))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(Color.primary.opacity(isActive ? 0 : 0.06), in: Capsule())
        .background(theme.accent.opacity(isActive ? 0.14 : 0), in: Capsule())
        .help("Copy files again that were offloaded before. New copies never overwrite old ones.")
        .accessibilityLabel(isActive ? "Re-offloading \(session.reoffloadingIDs.count) files" : "Re-offload")
    }

    /// On = this mode; turning "Everything" on asks first (see `AppModel.setReoffloadMode`).
    private func modeBinding(_ mode: ReoffloadMode) -> Binding<Bool> {
        Binding(get: { session.reoffloadMode == mode },
                set: { model.setReoffloadMode($0 ? mode : .off) })
    }
}

/// A list row's leading picture: the file-type symbol, or a small thumbnail.
private struct RowIcon: View {
    let clip: Clip
    let isSidecar: Bool
    let thumbnails: ThumbnailProvider?
    let tinted: Bool

    var body: some View {
        Group {
            if let thumbnails, !isSidecar {
                MediaThumbnail(clip: clip, provider: thumbnails, points: 44, compact: true)
                    .frame(width: 40, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.1))
                    }
            } else {
                Image(systemName: clip.category.symbol)
                    .foregroundStyle(tinted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .frame(width: thumbnails == nil ? 16 : 40)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Click, double-click, right-click and the "No preview" note for one file in the list or grid.
private struct ItemInteractions: ViewModifier {
    let fileName: String
    let showsNoPreview: Binding<Bool>
    let click: () -> Void
    let menu: () -> AnyView

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture(perform: click)
            .contextMenu { menu() }
            .popover(isPresented: showsNoPreview, arrowEdge: .bottom) {
                NoPreviewPopover(fileName: fileName)
            }
    }
}

/// Keyboard control of the list or grid: Space for Quick Look, arrows to move, Escape to deselect.
private struct ListKeys: ViewModifier {
    enum Direction { case up, down, left, right }

    var focus: FocusState<Bool>.Binding
    let order: [String]
    let space: () -> Void
    let move: (Direction) -> Void
    let escape: () -> Void
    let orderChanged: ([String]) -> Void

    func body(content: Content) -> some View {
        content
            .focusable()
            .focusEffectDisabled()
            .focused(focus)
            .onKeyPress(.space) { space(); return .handled }
            .onKeyPress(.upArrow) { move(.up); return .handled }
            .onKeyPress(.downArrow) { move(.down); return .handled }
            .onKeyPress(.leftArrow) { move(.left); return .handled }
            .onKeyPress(.rightArrow) { move(.right); return .handled }
            .onKeyPress(.escape) { escape(); return .handled }
            .onChange(of: order) { _, new in orderChanged(new) }
            .accessibilityHint("Press Space to preview the selected file with Quick Look")
    }
}

/// Which list the Media stage shows.
private enum ListScope: String, Hashable {
    case toCopy, offloaded, skipped
}

private extension View {
    /// The rounded box around a file list.
    func listBox() -> some View {
        background(Color(nsColor: .textBackgroundColor).opacity(0.6),
                   in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor))
            }
    }
}

/// A text field for a name token, with an optional "recent" menu.
private struct NameField: View {
    let title: String
    let prompt: String
    @Binding var text: String
    let isDisabled: Bool
    var recents: [String] = []
    var clearRecents: (() -> Void)?
    var focus: FocusState<Bool>.Binding

    @Environment(\.theme) private var theme
    private var focused: Bool { focus.wrappedValue }

    var body: some View {
        HStack(spacing: 6) {
            TextField(title, text: $text, prompt: Text(prompt))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .focused(focus)
                // The system focus ring always uses the accent colour asset; draw one in the theme instead.
                .focusEffectDisabled()
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(theme.accent.opacity(focused ? 0.75 : 0), lineWidth: 2.5)
                        .padding(-2)
                        .allowsHitTesting(false)
                        .animation(.easeOut(duration: 0.15), value: focused)
                }
                .disabled(isDisabled)
                .accessibilityLabel(title)
                .accessibilityHint("Used in file and folder names when the naming template includes it")
            if !recents.isEmpty {
                Menu {
                    ForEach(recents, id: \.self) { name in
                        Button(name) { text = name }
                    }
                    if let clearRecents {
                        Divider()
                        Button("Clear Recent Projects", action: clearRecents)
                    }
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(isDisabled)
                .help("Recent projects")
                .accessibilityLabel("Recent projects")
            }
        }
    }
}

/// Pop-up menu for the camera, with a shortcut to the camera list in Settings.
private struct CameraField: View {
    let selection: UUID?
    let isUsed: Bool
    let isDisabled: Bool
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var cameras: CameraStore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Menu {
            if cameras.cameras.isEmpty {
                Text("No cameras yet")
            } else {
                Picker("Camera", selection: Binding(get: { selection }, set: { model.selectCamera($0) })) {
                    ForEach(cameras.cameras) { camera in
                        Text(camera.displayName).tag(Optional(camera.id))
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Divider()
            Button(cameras.cameras.isEmpty ? "Add Cameras…" : "Edit Cameras…") {
                UserDefaults.standard.set(SettingsTab.cameras.rawValue, forKey: SettingsTab.storageKey)
                openSettings()
            }
        } label: {
            Text(label)
        }
        .fixedSize()
        .disabled(isDisabled)
        .help("The camera these files came from. Fills the {camera} token.")
        .accessibilityLabel("Camera, \(selected?.displayName ?? "none chosen")")
    }

    private var selected: Camera? { cameras.camera(id: selection) }

    private var label: String {
        if let selected { return selected.displayName }
        if cameras.cameras.isEmpty { return "Add a camera…" }
        return isUsed ? "Choose a camera…" : "None (optional)"
    }
}

#if DEBUG
#Preview("Clips stage") {
    ClipsStageView()
        .demoEnvironment(DemoData.model(state: .ready))
        .frame(width: 480, height: 420)
        .padding()
}
#endif

/// "Quick dump: skip project name": for just getting the footage off the camera.
private struct QuickDumpToggle: View {
    let isDisabled: Bool
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            Toggle(isOn: Binding(
                get: { settings.quickDump },
                set: { value in withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { settings.quickDump = value } })) {
                Text("Quick dump: skip project name")
            }
            .toggleStyle(.checkbox)
            .disabled(isDisabled)
            .fixedSize()
        }
        .help("Leaves {project} out of folder and file names, so you don't need to type one. Numbering carries on from what's already there.")
    }
}
