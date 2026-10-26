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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Bumped each time the stage becomes active, to play a short "look here" pop.
    @State private var activations = 0

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
                // A soft accent glow along the border of the stage that needs attention
                // (on the border only, so the text inside stays sharp).
                .shadow(color: Color.accentColor.opacity(state == .active ? 0.45 : 0), radius: 7)
                .allowsHitTesting(false)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: state)
        // Settles back to full size, so text stays crisp once the pop is over.
        .phaseAnimator([CGFloat(1), 1.018], trigger: activations) { panel, scale in
            panel.scaleEffect(scale)
        } animation: { _ in
            .spring(duration: 0.3, bounce: 0.35)
        }
        .onChange(of: state) { _, newState in
            if newState == .active && !reduceMotion { activations += 1 }
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
                        .transition(.scale.combined(with: .opacity))
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

/// The arrow between two stages. It lights up when the flow can continue,
/// and carries a stream of dots while files are being copied.
struct FunnelArrow: View {
    let lit: Bool
    var flowing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showsStream: Bool { flowing && !reduceMotion }

    var body: some View {
        ZStack {
            Image(systemName: "chevron.right")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(lit ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                .opacity(showsStream ? 0.3 : 1)
            if showsStream {
                FlowStream()
                    .frame(width: 32, height: 12)
                    .transition(.opacity)
            }
        }
        .frame(width: 28)
        .frame(maxHeight: .infinity)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: lit)
        .animation(.easeInOut(duration: 0.3), value: showsStream)
        .accessibilityHidden(true)
    }
}

/// A small rounded "pill" used for counts like "12 new".
struct CountPill: View {
    let text: String
    let systemImage: String
    var tint: Color = .accentColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Label {
            Text(text).contentTransition(.numericText())
        } icon: {
            Image(systemName: systemImage)
        }
            .animation(reduceMotion ? nil : .snappy, value: text)
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
        FunnelArrow(lit: true, flowing: true)
        StagePanel(number: 2, title: "Media", state: .active) { Text("Active") }
        FunnelArrow(lit: false)
        StagePanel(number: 3, title: "Destination", state: .pending) { Text("Pending") }
    }
    .padding()
    .frame(width: 700, height: 200)
}
#endif
