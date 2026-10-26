import SwiftUI

// Small animated pieces used around the main window. Each one checks Reduce Motion
// (System Settings → Accessibility → Display) and stays still when it's on.

/// Dots streaming left to right along a funnel arrow while files are copying.
struct FlowStream: View {
    var dotCount = 4
    /// Seconds for one dot to cross the arrow.
    var period: Double = 1.1
    @Environment(\.theme) private var theme
    private var plainTheme: Bool { theme.isPlain }

    var body: some View {
        TimelineView(.animation) { context in
            Canvas { canvas, size in
                let time = context.date.timeIntervalSinceReferenceDate
                let midY = size.height / 2
                for index in 0..<dotCount {
                    let phase = (time / period + Double(index) / Double(dotCount))
                        .truncatingRemainder(dividingBy: 1)
                    let x = phase * size.width
                    let radius = 1.6 + 1.2 * sin(phase * .pi)
                    canvas.opacity = sin(phase * .pi)
                    canvas.fill(Path(ellipseIn: CGRect(x: x - radius, y: midY - radius,
                                                       width: radius * 2, height: radius * 2)),
                                // Each dot warms from magenta to orange as it crosses.
                                with: .color(plainTheme ? theme.accent : theme.sweep(phase)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// A rounded progress bar whose filled part has a soft light sweeping across it.
struct ShimmerProgressBar: View {
    let fraction: Double
    var shimmering = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.theme) private var theme
    private var plainTheme: Bool { theme.isPlain }

    var body: some View {
        GeometryReader { geometry in
            let clamped = max(0, min(1, fraction.isFinite ? fraction : 0))
            let filled = clamped > 0 ? max(geometry.size.height, clamped * geometry.size.width) : 0
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.09))
                Capsule()
                    .fill(plainTheme
                          ? AnyShapeStyle(theme.accent)
                          : AnyShapeStyle(LinearGradient(colors: theme.progressColors,
                                                         startPoint: .leading, endPoint: .trailing)))
                    .overlay {
                        if shimmering && !reduceMotion && !plainTheme {
                            ShimmerSweep()
                        }
                    }
                    .clipShape(Capsule())
                    .frame(width: filled)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: filled)
            }
        }
        .frame(height: 7)
    }
}

/// The moving highlight inside `ShimmerProgressBar`.
private struct ShimmerSweep: View {
    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation) { context in
                let band = min(120, max(40, geometry.size.width * 0.35))
                let travel = geometry.size.width + band * 2
                let phase = context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 1.6) / 1.6
                LinearGradient(colors: [.white.opacity(0), .white.opacity(0.45), .white.opacity(0)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: band)
                    .offset(x: phase * travel - band)
            }
        }
        .allowsHitTesting(false)
    }
}

/// A ring and a few sparks that burst once from behind the completion checkmark.
struct CompletionBurst: View {
    let color: Color
    @State private var fired = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(fired ? 0 : 0.55), lineWidth: fired ? 0.5 : 3)
                .scaleEffect(fired ? 2.1 : 0.7)
            ForEach(0..<8, id: \.self) { index in
                Capsule()
                    .fill(color)
                    .frame(width: 3, height: fired ? 4 : 8)
                    .offset(y: fired ? -32 : -14)
                    .opacity(fired ? 0 : 0.9)
                    .rotationEffect(.degrees(Double(index) * 45 + 22.5))
            }
        }
        .frame(width: 34, height: 34)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(.easeOut(duration: 0.75).delay(0.1)) { fired = true }
        }
    }
}

extension View {
    /// Rows fade and slide in one after another when `revealed` turns true.
    /// Only the first rows are delayed, so long lists don't feel slow.
    func staggeredReveal(index: Int, revealed: Bool, reduceMotion: Bool) -> some View {
        self
            .opacity(revealed ? 1 : 0)
            .offset(x: revealed || reduceMotion ? 0 : 14)
            .animation(reduceMotion
                       ? .easeOut(duration: 0.2)
                       : .spring(duration: 0.45, bounce: 0.15).delay(Double(min(index, 14)) * 0.035),
                       value: revealed)
    }
}

#if DEBUG
#Preview("Motion pieces") {
    VStack(spacing: 24) {
        FlowStream().frame(width: 28, height: 20)
        ShimmerProgressBar(fraction: 0.6).frame(width: 300)
        ZStack {
            CompletionBurst(color: ResolvedTheme().burst)
            Image(systemName: "checkmark.circle.fill").font(.system(size: 30))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, ResolvedTheme().borderGradient)
        }
    }
    .padding(40)
}
#endif
