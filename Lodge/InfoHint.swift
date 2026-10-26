import SwiftUI

/// A small ⓘ next to a control. Hovering it for a moment (or clicking it) shows `text` in a
/// little popover; the same text is the tooltip and what VoiceOver reads.
struct InfoHint: View {
    let text: String
    /// What the hint is about, for VoiceOver ("Quick dump").
    let subject: String

    @State private var showing = false
    @State private var hoverTask: Task<Void, Never>?

    var body: some View {
        Button { showing.toggle() } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
                .imageScale(.small)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(text)
        .onHover { inside in
            hoverTask?.cancel()
            hoverTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(inside ? 450 : 150))
                guard !Task.isCancelled else { return }
                showing = inside
            }
        }
        .onDisappear { hoverTask?.cancel() }
        #if DEBUG
        // Screenshots: `-LodgeDemoInfoHint "Quick dump"` renders this hint's popover to a PNG
        // (SwiftUI's popover closes at once while Lodge is in the background).
        .background {
            if DemoData.launchState != nil,
               UserDefaults.standard.string(forKey: "LodgeDemoInfoHint") == subject {
                DemoHintRenderer(text: text)
            }
        }
        #endif
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 240, alignment: .leading)
                .padding(12)
        }
        .accessibilityLabel("About \(subject)")
        .accessibilityHint(text)
    }
}

enum QuickDumpHelp {
    static let text = "Skips the project name and dumps all the footage straight into a dated folder."
}

#if DEBUG
/// Screenshots only: draws the hint's popover offscreen into `/tmp/lodge-infohint.png` (2x)
/// and logs where the ⓘ is in the window, so it can be laid over a window capture.
private struct DemoHintRenderer: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            guard let window = view.window else { return }
            let dark = window.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let renderer = ImageRenderer(content: HintBubble(text: text)
                .environment(\.colorScheme, dark ? .dark : .light))
            renderer.scale = 2
            guard let image = renderer.cgImage else { return }
            let rep = NSBitmapImageRep(cgImage: image)
            try? rep.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: "/tmp/lodge-infohint.png"))
            let anchor = view.convert(view.bounds, to: nil)
            NSLog("LodgeDemoInfoHint anchor=%@ window=%@", NSStringFromRect(anchor), NSStringFromRect(window.frame))
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// A popover-shaped bubble with the arrow on top, like the real hint.
private struct HintBubble: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let fill = colorScheme == .dark ? Color(white: 0.19) : Color.white
        VStack(spacing: 0) {
            Triangle().fill(fill).frame(width: 20, height: 9)
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 240, alignment: .leading)
                .padding(12)
                .background(fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private struct Triangle: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: rect.midX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                path.closeSubpath()
            }
        }
    }
}
#endif
