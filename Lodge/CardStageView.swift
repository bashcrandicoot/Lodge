import SwiftUI

/// Stage 1: the inserted cards. Click one to fill the rest of the funnel.
struct CardStageView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var watcher: VolumeWatcher

    var body: some View {
        StagePanel(number: 1, title: "Card", state: model.selectedCard == nil ? .active : .done) {
            if watcher.cards.isEmpty && model.selectedCard == nil {
                InsertCardPrompt()
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(cardsToShow) { card in
                            CardRow(
                                card: card,
                                isSelected: card.id == model.selectedCardID,
                                isRemoved: !watcher.cards.contains(card),
                                detail: detail(for: card)
                            ) {
                                model.select(card)
                            }
                            .disabled(model.isBusy)
                        }
                    }
                }
            }
        }
    }

    /// Mounted cards, plus the selected one if it was just ejected (so its summary still makes sense).
    private var cardsToShow: [CardVolume] {
        var cards = watcher.cards
        if let selected = model.selectedCard, !cards.contains(selected) {
            cards.insert(selected, at: 0)
        }
        return cards
    }

    private func detail(for card: CardVolume) -> String? {
        guard card.id == model.selectedCardID else { return nil }
        if model.isScanning { return "Scanning…" }
        guard let session = model.session else { return nil }
        // System files and the ignore list: never copied, never block formatting, just counted.
        return OffloadFormatting.cardDetail(newFiles: session.newClips.count,
                                            copied: session.phase == .finished ? session.summary?.copied : nil,
                                            ignored: session.inventory.ignored.count)
    }
}

/// Empty state shown until a card is inserted.
private struct InsertCardPrompt: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "sdcard")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tint)
                .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
                .accessibilityHidden(true)
            Text("Insert an SD Card")
                .font(.title3.weight(.semibold))
            Text("Lodge fills in the rest as soon as a card is mounted.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// One card in the list.
private struct CardRow: View {
    @Environment(\.theme) private var theme
    let card: CardVolume
    let isSelected: Bool
    let isRemoved: Bool
    let detail: String?
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Bumped when the card shows up or gets selected, to bounce its icon.
    @State private var bounces = 0
    /// The card springs in with a short accent glow when it's inserted.
    @State private var inserted = false
    @State private var glowing = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: action) { rowContent }
                .buttonStyle(.plain)
            if showsActions {
                CardActionsMenu()
                    .padding(.trailing, 8)
                    .transition(.opacity)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isSelected ? theme.accent.opacity(0.14) : Color.clear))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(theme.accent.opacity(glowing ? 0.7 : 0), lineWidth: 1.5)
                .shadow(color: theme.glow.opacity(glowing ? 0.55 : 0), radius: 8)
                .allowsHitTesting(false)
        }
        .hoverLift(cornerRadius: 9)
        .scaleEffect(inserted || reduceMotion ? 1 : 0.94)
        .opacity(inserted || reduceMotion ? 1 : 0)
        .contextMenu {
            if showsActions { CardActions() }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isSelected)
        .onAppear {
            guard !reduceMotion else { inserted = true; return }
            bounces += 1
            glowing = true
            withAnimation(.spring(duration: 0.45, bounce: 0.35)) { inserted = true }
            Task {
                try? await Task.sleep(for: .milliseconds(350))
                withAnimation(.easeOut(duration: 1.1)) { glowing = false }
            }
        }
        .onChange(of: isSelected) { _, selected in
            if selected && !reduceMotion { bounces += 1 }
        }
    }

    private var showsActions: Bool { isSelected && !isRemoved }

    private var rowContent: some View {
            HStack(spacing: 10) {
                Image(systemName: isRemoved ? "eject.circle" : "sdcard.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .symbolEffect(.bounce, value: bounces)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .help(detail?.contains("ignored") == true
                              ? "Ignored items (system files and your ignore list in Settings ▸ Files) aren’t copied and don’t stop the card being ready to format."
                              : "")
                    if showsActions {
                        FormatStatusLine()
                            .padding(.top, 2)
                            .transition(.opacity)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(card.name), \(subtitle)")
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var subtitle: String {
        if isRemoved { return "Ejected" }
        var parts: [String] = []
        if let detail { parts.append(detail) }
        if let total = VolumeInfo.totalBytes(at: card.url) {
            parts.append(OffloadFormatting.bytes(total))
        }
        return parts.isEmpty ? card.url.path : parts.joined(separator: " · ")
    }
}

/// The selected card's "…" menu.
private struct CardActionsMenu: View {
    var body: some View {
        Menu {
            CardActions()
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Card actions")
        .accessibilityLabel("Card actions")
    }
}

/// Shared by the "…" menu and the context menu.
private struct CardActions: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Button("Format Card…") { model.confirmFormatSelectedCard() }
            .disabled(!model.canFormatSelectedCard)
        Button("Forget This Card’s History…") { model.confirmForgetSelectedCardHistory() }
            .disabled(model.selectedCardHistoryCount == 0 || model.isBusy || model.formatState.isFormatting)
        Divider()
        Button("Eject Card") { model.ejectSelectedCard() }
            .disabled(model.isBusy || model.isEjecting || model.formatState.isFormatting)
    }
}

#if DEBUG
#Preview("Card stage – empty") {
    CardStageView()
        .demoEnvironment(DemoData.model(state: .empty))
        .frame(width: 260, height: 360)
        .padding()
}

#Preview("Card stage – card") {
    CardStageView()
        .demoEnvironment(DemoData.model(state: .ready))
        .frame(width: 260, height: 360)
        .padding()
}
#endif
