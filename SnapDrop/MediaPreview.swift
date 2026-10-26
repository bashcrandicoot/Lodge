import AppKit
import Quartz
import SwiftUI

/// Which files are selected in the Media list or grid.
///
/// Selection is only for Quick Look: it picks what Space previews and what the arrow keys
/// step through. It never changes what gets offloaded.
struct MediaSelection: Equatable {
    enum Modifier: Equatable {
        /// A plain click: select just this file.
        case none
        /// ⌘-click: add or remove this file.
        case toggle
        /// ⇧-click: select everything from the last plain click to here.
        case extend
    }

    private(set) var selected: Set<String> = []
    /// Where ⇧-click ranges start.
    private(set) var anchor: String?
    /// The file previewed first (the last one clicked or reached with the arrow keys).
    private(set) var focus: String?

    var isEmpty: Bool { selected.isEmpty }

    func contains(_ id: String) -> Bool { selected.contains(id) }

    /// The selected files in on-screen order.
    func ordered(in order: [String]) -> [String] { order.filter(selected.contains) }

    mutating func click(_ id: String, modifier: Modifier, order: [String]) {
        switch modifier {
        case .none:
            selected = [id]
            anchor = id
            focus = id
        case .toggle:
            if selected.contains(id) {
                selected.remove(id)
                if focus == id { focus = ordered(in: order).last }
                if anchor == id { anchor = focus }
            } else {
                selected.insert(id)
                anchor = id
                focus = id
            }
        case .extend:
            guard let start = anchor.flatMap(order.firstIndex(of:)), let end = order.firstIndex(of: id) else {
                click(id, modifier: .none, order: order)
                return
            }
            selected = Set(order[min(start, end)...max(start, end)])
            focus = id
        }
    }

    /// Arrow keys: select the next (or previous) file in on-screen order.
    mutating func move(by offset: Int, order: [String]) {
        guard !order.isEmpty else { return }
        let next: Int
        if let focus, let index = order.firstIndex(of: focus) {
            next = min(max(index + offset, 0), order.count - 1)
        } else {
            next = offset < 0 ? order.count - 1 : 0
        }
        click(order[next], modifier: .none, order: order)
    }

    /// Quick Look moved to another file: follow it, keeping a multi-selection intact.
    mutating func follow(_ id: String) {
        if selected.count > 1 && selected.contains(id) {
            focus = id
        } else {
            selected = [id]
            anchor = id
            focus = id
        }
    }

    /// Drops files that are no longer shown (the filter or list changed).
    mutating func prune(to order: [String]) {
        let visible = Set(order)
        selected.formIntersection(visible)
        if let anchor, !visible.contains(anchor) { self.anchor = nil }
        if let focus, !visible.contains(focus) { self.focus = ordered(in: order).first }
    }

    mutating func clear() { self = MediaSelection() }
}

/// What Space (or double-click, or "Quick Look") shows.
enum PreviewQueue {
    enum Outcome: Equatable {
        /// Open Quick Look on `ids` (in on-screen order), starting at `start`.
        case preview(ids: [String], start: Int)
        /// The file can't be previewed: say so next to it.
        case unsupported(id: String)
        case nothing
    }

    /// With several files selected, Quick Look steps through just those; otherwise through
    /// every file shown, in the current filter's order. Files Quick Look can't open are skipped.
    static func make(order: [String], selection: Set<String>, focus: String?,
                     canPreview: (String) -> Bool) -> Outcome {
        let base = selection.count > 1 ? order.filter(selection.contains) : order
        guard !base.isEmpty else { return .nothing }
        let start = focus.flatMap { base.contains($0) ? $0 : nil } ?? base[0]
        let items = base.filter(canPreview)
        if !canPreview(start) {
            // One file asked for by name that can't be shown: say so. Otherwise start at the first one that can.
            let askedForOne = focus != nil && selection.count <= 1
            return askedForOne || items.isEmpty ? .unsupported(id: start) : .preview(ids: items, start: 0)
        }
        return .preview(ids: items, start: items.firstIndex(of: start) ?? 0)
    }
}

/// The grid shows a clip's sidecars (M01.XML…) as a badge on the clip's tile, not as tiles of their own.
enum TileFolding {
    struct Tile: Equatable {
        let id: String
        let sidecars: [String]
    }

    /// `ids` in on-screen order; `primaryOf` maps a sidecar to its clip. Sidecars whose clip isn't
    /// shown (e.g. the "Other" filter) stay as tiles.
    static func fold(_ ids: [String], primaryOf: [String: String]) -> [Tile] {
        let shown = Set(ids)
        var sidecars: [String: [String]] = [:]
        for id in ids {
            if let primary = primaryOf[id], shown.contains(primary) { sidecars[primary, default: []].append(id) }
        }
        return ids.compactMap { id in
            if let primary = primaryOf[id], shown.contains(primary) { return nil }
            return Tile(id: id, sidecars: sidecars[id] ?? [])
        }
    }
}

// MARK: - Quick Look panel

/// One file in the Quick Look panel.
final class MediaPreviewItem: NSObject, QLPreviewItem {
    let id: String
    let url: URL
    let title: String

    init(id: String, url: URL, title: String) {
        self.id = id
        self.url = url
        self.title = title
    }

    var previewItemURL: URL! { url }
    var previewItemTitle: String! { title }
}

/// Drives the shared Quick Look panel (`QLPreviewPanel`) for the main window.
///
/// The panel looks for a controller along the key window's responder chain; `QuickLookHost`
/// puts this object there.
@MainActor
final class QuickLookController: NSResponder, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookController()

    private(set) var items: [MediaPreviewItem] = []
    private var startIndex = 0
    /// Called with the file Quick Look moved to (arrow keys in the panel).
    private var onMove: ((String) -> Void)?
    private var indexObservation: NSKeyValueObservation?
    private weak var controlledPanel: QLPreviewPanel?

    static var isVisible: Bool {
        QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible
    }

    func show(_ items: [MediaPreviewItem], start: Int, onMove: @escaping (String) -> Void) {
        guard !items.isEmpty else { return }
        self.items = items
        self.startIndex = min(max(start, 0), items.count - 1)
        self.onMove = onMove
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible, controlledPanel === panel {
            panel.reloadData()
            panel.currentPreviewItemIndex = startIndex
        } else {
            panel.updateController()
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func close() {
        if Self.isVisible, controlledPanel != nil { QLPreviewPanel.shared().orderOut(nil) }
        items = []
        onMove = nil
    }

    /// Puts the controller in `window`'s responder chain (once).
    func attach(to window: NSWindow) {
        var responder: NSResponder? = window.nextResponder
        while let current = responder {
            if current === self { return }
            responder = current.nextResponder
        }
        nextResponder = window.nextResponder
        window.nextResponder = self
    }

    // MARK: Panel control

    nonisolated override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        MainActor.assumeIsolated { !items.isEmpty }
    }

    nonisolated override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { begin(panel) }
    }

    nonisolated override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { end(panel) }
    }

    private func begin(_ panel: QLPreviewPanel) {
        controlledPanel = panel
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.currentPreviewItemIndex = startIndex
        indexObservation = panel.observe(\.currentPreviewItemIndex, options: [.new]) { [weak self] panel, _ in
            let index = panel.currentPreviewItemIndex
            MainActor.assumeIsolated {
                guard let self, self.items.indices.contains(index) else { return }
                self.onMove?(self.items[index].id)
            }
        }
    }

    private func end(_ panel: QLPreviewPanel) {
        indexObservation = nil
        panel.dataSource = nil
        panel.delegate = nil
        controlledPanel = nil
    }

    // MARK: QLPreviewPanelDataSource

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { items.count }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        MainActor.assumeIsolated { items.indices.contains(index) ? items[index] : nil }
    }

    // MARK: QLPreviewPanelDelegate

    /// Space closes the panel again, like in Finder.
    nonisolated func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown, event.charactersIgnoringModifiers == " " else { return false }
        MainActor.assumeIsolated { panel.orderOut(nil) }
        return true
    }
}

/// An invisible view that hands the window to `QuickLookController`.
struct QuickLookHost: NSViewRepresentable {
    func makeNSView(context: Context) -> HostView { HostView() }
    func updateNSView(_ nsView: HostView, context: Context) {}

    final class HostView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { QuickLookController.shared.attach(to: window) }
        }
    }
}
