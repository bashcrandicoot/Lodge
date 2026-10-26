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
        return "\(OffloadFormatting.clipCount(session.newClips.count)) new"
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
            Text("SnapDrop fills in the rest as soon as a card is mounted.")
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
    let card: CardVolume
    let isSelected: Bool
    let isRemoved: Bool
    let detail: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isRemoved ? "eject.circle" : "sdcard.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
