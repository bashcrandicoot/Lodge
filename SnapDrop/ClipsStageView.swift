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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var needs: NamingNeeds { NamingNeeds(settings.naming) }

    var body: some View {
        StagePanel(number: 2, title: "Media", state: stageState) {
            VStack(alignment: .leading, spacing: 14) {
                counts
                nameFields
                preview
            }
        }
        .onAppear {
            if session.phase == .ready && !session.newClips.isEmpty { nameFocused = true }
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
                if session.offloadedInView > 0 && session.phase == .ready {
                    ReoffloadMenu(session: session)
                }
            }
            Spacer(minLength: 0)
            Text(OffloadFormatting.bytes(session.newBytes))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel("Total size \(OffloadFormatting.bytes(session.newBytes))")
        }
    }

    // MARK: Project + camera

    private var nameFields: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
            GridRow {
                fieldLabel("Project")
                NameField(
                    title: "Project",
                    prompt: needs.project ? "e.g. Coastline" : "Optional, not in the template",
                    text: $session.projectInput,
                    isDisabled: isLocked,
                    recents: settings.recentProjects,
                    clearRecents: settings.clearRecentProjects)
                    .focused($nameFocused)
            }
            GridRow {
                fieldLabel("Camera")
                CameraField(selection: session.cameraID, isUsed: needs.camera, isDisabled: isLocked)
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
                }
            }
        }
    }

    private var availableScopes: [ListScope] {
        var scopes: [ListScope] = [.toCopy]
        if session.offloadedInView > 0 && session.phase == .ready { scopes.append(.offloaded) }
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
                .help("Switch between the files to copy and the files offloaded before")
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
        }
    }

    private func title(of scope: ListScope) -> String {
        switch scope {
        case .toCopy: return "Name Preview"
        case .offloaded: return "Already Offloaded (\(session.offloadedInView))"
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
                .labelsHidden()
                .controlSize(.small)
                .accessibilityLabel("Show file type")
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            PreviewRow(item: item, isPlaceholder: placeholder,
                                       isActive: isRunning && item.id == session.progress.currentID,
                                       isVerified: session.verifiedIDs.contains(item.id),
                                       isReoffload: session.reoffloadingIDs.contains(item.id))
                                .background(index.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.035))
                                .staggeredReveal(index: index, revealed: revealed, reduceMotion: reduceMotion)
                                .contextMenu { rowMenu(for: item.clip) }
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
        }
    }

    /// Nothing will be copied: say why, and offer the way out.
    private var nothingToCopy: some View {
        ContentUnavailableView {
            if session.missingCopyCount > 0 {
                Label("Copies Missing", systemImage: "exclamationmark.triangle")
            } else {
                Label("All Caught Up", systemImage: "checkmark.seal")
            }
        } description: {
            if session.missingCopyCount > 0 {
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
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(files.enumerated()), id: \.element.id) { index, clip in
                    OffloadedRow(clip: clip,
                                 entry: entries[clip.ledgerKey(volumeIdentity: session.card.identity)],
                                 isMissing: session.offloadedStatus(of: clip) == true,
                                 isReoffload: session.reoffloadingIDs.contains(clip.id))
                        .background(index.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.035))
                        .contextMenu { rowMenu(for: clip) }
                }
            }
        }
        .listBox()
    }

    /// Right-click on a file: re-offload just this one, or show its existing copy.
    @ViewBuilder
    private func rowMenu(for clip: Clip) -> some View {
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
    private func scrollToCurrent(_ proxy: ScrollViewProxy, animated: Bool) {
        let current = session.progress.currentID
        guard isRunning, !current.isEmpty else { return }
        withAnimation(animated ? .easeInOut(duration: 0.35) : nil) {
            proxy.scrollTo(current, anchor: .center)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var accessibilityText: String {
        var text = "\(item.category.title), \(item.originalName) will be saved as \(item.relativePath)"
        if let primary = item.sidecarOf { text += ", alongside \(primary)" }
        if isReoffload { text += ", re-offload: a new copy" }
        if isVerified { text += ", copied and verified" } else if isActive { text += ", copying now" }
        return text
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: item.category.symbol)
                .foregroundStyle(item.sidecarOf == nil ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 16)
                .accessibilityHidden(true)
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

/// A file offloaded before: where its copy is, or that it's missing.
private struct OffloadedRow: View {
    let clip: Clip
    let entry: LedgerEntry?
    let isMissing: Bool
    let isReoffload: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: clip.category.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .accessibilityHidden(true)
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
        .background(Color.accentColor.opacity(isActive ? 0.14 : 0), in: Capsule())
        .help("Copy files again that were offloaded before. New copies never overwrite old ones.")
        .accessibilityLabel(isActive ? "Re-offloading \(session.reoffloadingIDs.count) files" : "Re-offload")
    }

    /// On = this mode; turning "Everything" on asks first (see `AppModel.setReoffloadMode`).
    private func modeBinding(_ mode: ReoffloadMode) -> Binding<Bool> {
        Binding(get: { session.reoffloadMode == mode },
                set: { model.setReoffloadMode($0 ? mode : .off) })
    }
}

/// Which list the Media stage shows.
private enum ListScope: Hashable {
    case toCopy, offloaded
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

    @Environment(\.theme) private var theme
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            TextField(title, text: $text, prompt: Text(prompt))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .focused($focused)
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
