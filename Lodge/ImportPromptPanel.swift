import SwiftUI
import AppKit

/// The fallback for the import notification (when notifications are off for Lodge): a small
/// floating panel in the top-right corner, under the menu bar. It never activates Lodge or
/// takes the keyboard; its buttons work with a single click.
@MainActor
final class ImportPromptPanel {
    private let panel: NSPanel

    init(card: CardVolume, title: String, index: Int, onChoice: @escaping (ImportPrompter.Choice) -> Void) {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 96),
                        styleMask: [.nonactivatingPanel, .borderless],
                        backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.title = title
        let host = NSHostingView(rootView: ImportPromptPanelView(title: title, onChoice: onChoice))
        host.frame.size = host.fittingSize
        panel.contentView = host
        panel.setContentSize(host.fittingSize)
        position(index: index)
    }

    /// Top-right of the screen with the menu bar, stacked when several cards come in.
    private func position(index: Int) {
        guard let screen = NSScreen.screens.first ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let y = visible.maxY - 10 - CGFloat(index) * (size.height + 8) - size.height
        panel.setFrameOrigin(NSPoint(x: visible.maxX - size.width - 10, y: y))
    }

    func show() { panel.orderFrontRegardless() }
    func close() { panel.close() }
    var window: NSWindow { panel }
}

struct ImportPromptPanelView: View {
    let title: String
    var onChoice: (ImportPrompter.Choice) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).lineLimit(1)
                    Text(ImportPrompter.message).font(.callout).foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Button("Import") { onChoice(.importCard) }
                        .keyboardShortcut(.defaultAction)
                    Button("Ignore") { onChoice(.ignore) }
                    Spacer(minLength: 0)
                    Button("Don’t ask for this card") { onChoice(.dontAsk) }
                        .buttonStyle(.link)
                        .font(.caption)
                }
                .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 340, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}
