import SwiftUI

/// Stage 2: the clips on the selected card, the shoot name, and a live preview
/// of the names they'll get.
struct ClipsStageView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let session = model.session {
            ClipsStageContent(session: session)
        } else {
            StagePanel(number: 2, title: "Clips", state: .pending) {
                VStack {
                    Spacer()
                    if model.isScanning {
                        ProgressView("Looking for clips…")
                    } else {
                        Label("Clips appear here once a card is inserted.", systemImage: "film.stack")
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

    private var needs: NamingNeeds { NamingNeeds(settings.naming) }

    var body: some View {
        StagePanel(number: 2, title: "Clips", state: stageState) {
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
        return missing ? .active : .done
    }

    // MARK: Counts

    private var counts: some View {
        HStack(spacing: 6) {
            CountPill(text: "\(session.newClips.count) new", systemImage: "film.stack")
            if session.alreadyOffloadedCount > 0 {
                CountPill(text: "\(session.alreadyOffloadedCount) already offloaded",
                          systemImage: "checkmark.circle", tint: .secondary)
            }
            Spacer()
            Text(OffloadFormatting.bytes(session.newBytes))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel("Total size \(OffloadFormatting.bytes(session.newBytes))")
        }
    }

    // MARK: Project + shoot name

    private var shootNameField: some View {
        HStack(alignment: .top, spacing: 10) {
            NameField(
                title: "Project",
                prompt: "e.g. Coastline",
                text: $session.projectInput,
                cleaned: session.project,
                isUsed: needs.project,
                isDisabled: isLocked,
                recents: settings.recentProjects,
                clearRecents: settings.clearRecentProjects)
            NameField(
                title: "Shoot Name",
                prompt: "e.g. Beach Shoot",
                text: $session.shootNameInput,
                cleaned: session.shootName,
                isUsed: needs.shoot,
                isDisabled: isLocked)
                .focused($nameFocused)
        }
    }

    private var isLocked: Bool { session.phase != .ready || session.newClips.isEmpty }

    // MARK: Preview

    @ViewBuilder
    private var preview: some View {
        if session.newClips.isEmpty {
            ContentUnavailableView {
                Label("All Caught Up", systemImage: "checkmark.seal")
            } description: {
                Text("Every clip on this card has already been offloaded.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let items = model.previewPlan(for: session)
            let placeholder = model.previewHasPlaceholders(for: session)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Name Preview")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(PlanLayout.folders(items).map { $0.isEmpty ? "/" : $0 + "/" }.joined(separator: ", "))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
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
}

/// "C0001.MP4  →  2026-10-25_BeachShoot_0001.mp4"
private struct PreviewRow: View {
    let item: PlannedFile
    let isPlaceholder: Bool

    var body: some View {
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
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.originalName) will be saved as \(item.relativePath)")
    }
}

/// A labelled text field for a name token, with an optional "recent" menu.
private struct NameField: View {
    let title: String
    let prompt: String
    @Binding var text: String
    let cleaned: String
    let isUsed: Bool
    let isDisabled: Bool
    var recents: [String] = []
    var clearRecents: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                if !isUsed {
                    Text("not in template")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
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
                    .help("Recent \(title.lowercased())s")
                    .accessibilityLabel("Recent \(title.lowercased())s")
                }
            }
            TextField(title, text: $text, prompt: Text(prompt))
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .disabled(isDisabled)
                .accessibilityHint("Used in file and folder names when the naming template includes it")
            Text(hint.isEmpty ? " " : hint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hint: String {
        let typed = text.trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty, typed != cleaned else { return isUsed ? "" : "Optional" }
        return "Saved as “\(cleaned)”"
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
