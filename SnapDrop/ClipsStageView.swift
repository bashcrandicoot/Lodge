import SwiftUI

/// Stage 2 ("Media"): the files on the selected card, the name fields, and a live
/// preview of the names they'll get.
struct ClipsStageView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let session = model.session {
            ClipsStageContent(session: session)
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

    private var needs: NamingNeeds { NamingNeeds(settings.naming) }

    var body: some View {
        StagePanel(number: 2, title: "Media", state: stageState) {
            VStack(alignment: .leading, spacing: 14) {
                counts
                shootNameField
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
        let missing = (needs.project && session.project.isEmpty) || (needs.shoot && session.shootName.isEmpty)
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
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            Text(OffloadFormatting.bytes(session.newBytes))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel("Total size \(OffloadFormatting.bytes(session.newBytes))")
        }
    }

    // MARK: Project + shoot name

    private var shootNameField: some View {
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
            }
            GridRow {
                fieldLabel("Shoot")
                NameField(
                    title: "Shoot Name",
                    prompt: needs.shoot ? "e.g. Beach Shoot" : "Optional, not in the template",
                    text: $session.shootNameInput,
                    isDisabled: isLocked)
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
        if session.newClips.isEmpty {
            ContentUnavailableView {
                Label("All Caught Up", systemImage: "checkmark.seal")
            } description: {
                Text(session.allNewFiles.isEmpty
                     ? "Everything on this card has already been offloaded."
                     : "The new files on this card are types you turned off in Settings.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let plan = model.previewPlan(for: session)
            let placeholder = model.previewHasPlaceholders(for: session)
            let present = MediaCategory.allCases.filter { category in plan.contains { $0.category == category } }
            let activeFilter = filter.flatMap { present.contains($0) ? $0 : nil }
            let items = activeFilter.map { category in plan.filter { $0.category == category } } ?? plan

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Name Preview")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(folderSummary(plan))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
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
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            PreviewRow(item: item, isPlaceholder: placeholder)
                                .background(index.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.035))
                        }
                    }
                }
                .background(Color(nsColor: .textBackgroundColor).opacity(0.6),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor))
                }
            }
        }
    }

    private func folderSummary(_ plan: [PlannedFile]) -> String {
        let folders = PlanLayout.folders(plan)
        if folders.count == 1 { return folders[0].isEmpty ? "Destination folder" : folders[0] + "/" }
        return "\(folders.count) folders"
    }
}

/// "C0001.MP4  →  2026-10-25_BeachShoot_0001.mp4"
private struct PreviewRow: View {
    let item: PlannedFile
    let isPlaceholder: Bool

    private var accessibilityText: String {
        var text = "\(item.category.title), \(item.originalName) will be saved as \(item.relativePath)"
        if let primary = item.sidecarOf { text += ", alongside \(primary)" }
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
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, item.sidecarOf == nil ? 10 : 22)
        .padding(.trailing, 10)
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
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

    var body: some View {
        HStack(spacing: 6) {
            TextField(title, text: $text, prompt: Text(prompt))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
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
