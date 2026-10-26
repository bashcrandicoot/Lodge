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
    @EnvironmentObject private var settings: AppSettings
    @FocusState private var nameFocused: Bool

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
        return session.shootName.isEmpty ? .active : .done
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

    // MARK: Shoot name

    private var shootNameField: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Shoot Name")
                .font(.subheadline.weight(.semibold))
            TextField("Shoot Name", text: $session.shootNameInput, prompt: Text("e.g. Beach Shoot"))
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .focused($nameFocused)
                .disabled(session.phase != .ready || session.newClips.isEmpty)
                .accessibilityHint("Used in every file name, for example Beach Shoot becomes BeachShoot")
            if showsSanitizedHint {
                Text("Saved as “\(session.shootName)”")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var showsSanitizedHint: Bool {
        let typed = session.shootNameInput.trimmingCharacters(in: .whitespaces)
        return !session.shootName.isEmpty && typed != session.shootName
    }

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
            let name = session.shootName.isEmpty ? NamePreview.placeholderShootName : session.shootName
            let items = NamePreview.preview(
                clips: session.newClips,
                shootName: name,
                highestExisting: NamePreview.highestExisting(
                    destination: settings.destinationURL, clips: session.newClips, shootName: session.shootName))

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Name Preview")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(NamePreview.folders(for: items).map { $0 + "/" }.joined(separator: ", "))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            PreviewRow(item: item, isPlaceholder: session.shootName.isEmpty)
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
    let item: NamePreviewItem
    let isPlaceholder: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.newName)
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
        .accessibilityLabel("\(item.originalName) will be saved as \(item.newName) in \(item.folder)")
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
