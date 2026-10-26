import SwiftUI

/// Where a funnel stage is: not reached yet, needs attention now, or done.
enum StageState {
    case pending, active, done

    var accessibilityText: String {
        switch self {
        case .pending: return "not started"
        case .active: return "needs your attention"
        case .done: return "complete"
        }
    }
}

/// A rounded "card" for one stage of the Card → Clips → Destination funnel.
struct StagePanel<Content: View>: View {
    let number: Int
    let title: String
    let state: StageState
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StageHeader(number: number, title: title, state: state)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(state == .active ? Color.accentColor.opacity(0.55) : Color(nsColor: .separatorColor),
                              lineWidth: state == .active ? 1.5 : 1)
        }
    }
}

/// "① Card" style header with a status badge.
struct StageHeader: View {
    let number: Int
    let title: String
    let state: StageState

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(badgeColor.opacity(state == .pending ? 0.15 : 1))
                if state == .done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(number)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(state == .pending ? Color.secondary : Color.white)
                }
            }
            .frame(width: 22, height: 22)

            Text(title)
                .font(.headline)
                .foregroundStyle(state == .pending ? .secondary : .primary)
            Spacer()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(number), \(title), \(state.accessibilityText)")
        .accessibilityAddTraits(.isHeader)
    }

    private var badgeColor: Color {
        switch state {
        case .pending: return .secondary
        case .active: return .accentColor
        case .done: return .green
        }
    }
}

/// The arrow between two stages. It lights up when the flow can continue.
struct FunnelArrow: View {
    let lit: Bool

    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(lit ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            .frame(width: 28)
            .frame(maxHeight: .infinity)
            .accessibilityHidden(true)
    }
}

/// A small rounded "pill" used for counts like "12 new".
struct CountPill: View {
    let text: String
    let systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        Label(text, systemImage: systemImage)
            .lineLimit(1)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.14), in: Capsule())
            .foregroundStyle(tint)
    }
}

#if DEBUG
#Preview("Stage panel") {
    HStack {
        StagePanel(number: 1, title: "Card", state: .done) { Text("Done") }
        FunnelArrow(lit: true)
        StagePanel(number: 2, title: "Media", state: .active) { Text("Active") }
        FunnelArrow(lit: false)
        StagePanel(number: 3, title: "Destination", state: .pending) { Text("Pending") }
    }
    .padding()
    .frame(width: 700, height: 200)
}
#endif
