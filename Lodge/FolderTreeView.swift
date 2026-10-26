import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The folder tree at the destination: every folder the offload creates (per-type, Proxies and
/// Sidecars too), plus the folders already there. Each folder opens with its triangle
/// (Option-click opens or closes everything inside).
///
/// Editing the folder template:
/// - drag a level, or a token from the palette, between two folders to make a new level;
/// - drop it on the left or right side of a folder's name to put it side by side in that
///   level ("{project}_{date}"); drag a piece of a combined name back out between folders.
/// Finder folders dropped anywhere become the destination.
struct FolderLayout: View {
    let root: URL
    let plan: [PlannedFile]
    let editable: Bool

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var destinations: DestinationStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var listing = FolderListing()
    /// Folders opened or closed by hand; everything else uses `defaultExpanded`.
    @State private var expansion: [String: Bool] = [:]
    @State private var dropTarget: TreeDropTarget?
    @State private var contentHeight: CGFloat = 0

    /// At most this many folders that are already there are listed one by one; more are grouped.
    private static let othersShownInline = 4

    private var example: PlannedFile? {
        plan.first { $0.role == .main && $0.category == .video } ?? plan.first { $0.role == .main } ?? plan.first
    }

    var body: some View {
        let tree = FolderTree.build(rootName: root.lastPathComponent, plan: plan)
        let rows = rows(for: tree)
        let showsLegend = rows.contains { $0.isOnDisk }
        VStack(alignment: .leading, spacing: 2) {
            header(tree)
                .padding(.bottom, 3)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(rows) { row in
                        rowView(row)
                    }
                }
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: contentHeight)
            .layoutPriority(1)
            .padding(.horizontal, -4)

            if showsLegend {
                Legend()
                    .padding(.top, 4)
            }
            if editable {
                TokenPalette(add: { token in edit { FolderTemplateEditor.insert(token, into: $0) } })
                    .padding(.top, 8)
            }
        }
        .font(.system(.caption, design: .monospaced))
        .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.2), value: settings.folderTemplate)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: dropTarget)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: expansion)
        .onChange(of: refreshKey) { listing.refresh() }
        .onAppear(perform: applyLaunchExpansion)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Files are saved like \(([root.lastPathComponent] + chainNames + [example?.fileName ?? ""]).joined(separator: ", then "))")
    }

    // MARK: Header

    private func header(_ tree: FolderNode) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Layout")
                .font(.subheadline.weight(.semibold))
            Spacer()
            if editable {
                Text("Drag to rearrange")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Button { expandAll(tree) } label: {
                Image(systemName: "rectangle.expand.vertical")
            }
            .help("Expand All (or Option-click a triangle)")
            .accessibilityLabel("Expand all folders")
            Button { collapseAll(tree) } label: {
                Image(systemName: "rectangle.compress.vertical")
            }
            .help("Collapse All")
            .accessibilityLabel("Collapse all folders")
        }
        .buttonStyle(.borderless)
        .font(.subheadline)
    }

    // MARK: Rows

    /// The tree flattened into the rows that are showing.
    private func rows(for tree: FolderNode) -> [TreeRow] {
        let template = settings.folderTemplate
        let templateLevels = FolderTemplateEditor.levels(template)
        let kept = FolderTree.levelIndices(template: template, quickDump: settings.quickDump)
        // Quick dump leaves `{project}` levels out: show them, struck through, where they would be.
        var ghosts: [Int: [Int]] = [:]
        for index in templateLevels.indices where !kept.contains(index) {
            ghosts[kept.filter { $0 < index }.count, default: []].append(index)
        }
        let chain = chainPaths
        // The tree only lines up with the template when the plan follows it.
        let levelsMatch = settings.effectiveNaming != nil && (example.map { $0.folder.isEmpty ? 0 : $0.folder.split(separator: "/").count - ($0.role == .main ? 0 : 1) } ?? 0) == kept.count

        var rows: [TreeRow] = []
        func addOthers(_ names: [String], under path: String, depth: Int) {
            func addFolder(_ name: String, path: String, depth: Int) {
                let children = subfolders(path) ?? []
                let key = TreeRow.folderKey(path)
                rows.append(TreeRow(id: key, depth: depth, kind: .other(path: path, name: name),
                                    expanded: children.isEmpty ? nil : isExpanded(key, default: false)))
                guard !children.isEmpty, isExpanded(key, default: false) else { return }
                for child in FolderTree.otherFolders(onDisk: children, planned: []) {
                    addFolder(child, path: path + "/" + child, depth: depth + 1)
                }
            }
            if names.count <= Self.othersShownInline {
                for name in names { addFolder(name, path: join(path, name), depth: depth) }
            } else {
                let key = TreeRow.othersKey(path)
                let open = isExpanded(key, default: false)
                rows.append(TreeRow(id: key, depth: depth, kind: .otherGroup(path: path, count: names.count), expanded: open))
                if open { for name in names { addFolder(name, path: join(path, name), depth: depth + 1) } }
            }
        }

        func walk(_ node: FolderNode) {
            let key = TreeRow.folderKey(node.path)
            let level: Int? = levelsMatch && node.depth >= 1 && node.depth <= kept.count && !node.isRoleFolder
                ? kept[node.depth - 1] : nil
            let onDisk = node.depth == 0 ? (subfolders("") ?? []) : subfolders(node.path)
            let others = FolderTree.otherFolders(onDisk: onDisk ?? [], planned: node.children.map(\.name))
            let ghostLevels = chain.contains(node.path) ? (ghosts[node.depth] ?? []) : []
            let expandable = !node.children.isEmpty || !node.files.isEmpty || !others.isEmpty || !ghostLevels.isEmpty
            let open = expandable && isExpanded(key, default: node.depth == 0 || chain.contains(node.path))
            rows.append(TreeRow(id: key, depth: node.depth,
                                kind: .folder(node, level: level, exists: node.depth == 0 || onDisk != nil),
                                expanded: expandable ? open : nil))
            guard open else { return }
            for ghost in ghostLevels {
                rows.append(TreeRow(id: "g:\(ghost)", depth: node.depth + 1,
                                    kind: .ghost(level: ghost, template: templateLevels[ghost]), expanded: nil))
            }
            if node.files.count == 1, let file = node.files.first {
                rows.append(TreeRow(id: "file:" + file.id, depth: node.depth + 1, kind: .file(file), expanded: nil))
            } else if !node.files.isEmpty {
                let filesKey = TreeRow.filesKey(node.path)
                let filesOpen = isExpanded(filesKey, default: false)
                rows.append(TreeRow(id: filesKey, depth: node.depth + 1, kind: .files(path: node.path, files: node.files),
                                    expanded: filesOpen))
                if filesOpen {
                    for file in node.files {
                        rows.append(TreeRow(id: "file:" + file.id, depth: node.depth + 2, kind: .file(file), expanded: nil))
                    }
                }
            }
            for child in node.children { walk(child) }
            if !others.isEmpty { addOthers(others, under: node.path, depth: node.depth + 1) }
        }
        walk(tree)
        return rows
    }

    @ViewBuilder
    private func rowView(_ row: TreeRow) -> some View {
        let drop = dropAction(for: row)
        TreeRowView(
            row: row,
            content: content(for: row),
            editable: editable,
            acceptsTemplateDrops: editable && drop != nil,
            dropTarget: $dropTarget,
            toggle: { recursive in toggle(row, recursive: recursive) },
            perform: { payload, place in
                guard let action = dropAction(for: row)?(place) else { return }
                apply(payload, action)
            },
            useFolder: model.useDroppedFolder)
    }

    /// What a row looks like, and what editing it does.
    private func content(for row: TreeRow) -> TreeRowContent {
        switch row.kind {
        case .folder(let node, let level, let exists):
            if node.depth == 0 {
                return TreeRowContent(title: node.name, symbol: "folder.fill", style: .root,
                                      help: root.path)
            }
            if node.isRoleFolder {
                let role = node.files.first?.role
                return TreeRowContent(title: node.name, symbol: exists ? "folder.fill" : "folder",
                                      style: exists ? .existing : .new,
                                      detail: role == .proxy ? countText(node.fileCount, "proxy", "proxies")
                                                             : countText(node.fileCount, "file", "files"),
                                      help: exists ? "Already in \(root.lastPathComponent)" : "Lodge creates this folder")
            }
            var content = TreeRowContent(title: node.name, symbol: exists ? "folder.fill" : "folder",
                                         style: exists ? .existing : .new,
                                         help: exists ? "\(node.name) is already in \(root.lastPathComponent)"
                                                      : "Lodge creates \(node.name)")
            if let level {
                let template = FolderTemplateEditor.levels(settings.folderTemplate)[level]
                content.level = level
                content.description = TemplateDescription.level(template)
                if editable { content.segments = segments(of: template, level: level, in: node) }
                content.separator = InlineLevel(template).isCombined ? InlineLevel(template).separator : nil
                content.editing = editing(level: level)
            }
            return content
        case .ghost(let level, let template):
            var content = TreeRowContent(title: TemplateDescription.level(template), symbol: "folder", style: .ghost,
                                         help: "Quick dump leaves this folder out")
            content.level = level
            content.description = TemplateDescription.level(template)
            content.editing = editing(level: level)
            return content
        case .files(_, let files):
            let first = files[0]
            let open = row.expanded == true
            return TreeRowContent(title: open ? countText(files.count, "file", "files") : first.fileName,
                                  symbol: open ? "doc.on.doc" : first.category.symbol, style: .file,
                                  trailingNote: open ? nil : "+ \(files.count - 1) more",
                                  help: "\(countText(files.count, "file", "files")) go in this folder")
        case .file(let file):
            return TreeRowContent(title: file.fileName, symbol: file.category.symbol,
                                  style: file.role == .main ? .file : .sidecar,
                                  help: "From \(file.originalName)")
        case .other(_, let name):
            return TreeRowContent(title: name, symbol: "folder.fill", style: .other,
                                  help: "Already in \(root.lastPathComponent); not used by this offload")
        case .otherGroup(_, let count):
            return TreeRowContent(title: "\(count) other folders", symbol: "folder.fill", style: .other,
                                  help: "Folders already there that this offload doesn’t use")
        }
    }

    /// The side-by-side pieces of a level, as they come out for the files in `node`.
    private func segments(of template: String, level: Int, in node: FolderNode) -> [TreeSegment] {
        let inline = InlineLevel(template)
        let sample = firstFile(in: node)
        let context = model.session.map { model.namingContext(for: $0).fillingBlanks() } ?? .placeholders
        return inline.items.enumerated().map { index, item in
            let label = TemplateDescription.level(item)
            let leftOut = settings.quickDump && QuickDump.mentionsProject(item)
            let value = leftOut ? nil : sample.flatMap { FolderTree.render(piece: item, file: $0.clip, context: context) }
            let payload: FolderTemplateEditor.Payload = inline.isCombined ? .item(level: level, item: index) : .level(level)
            return TreeSegment(index: index, text: value.flatMap { $0.isEmpty ? nil : $0 } ?? label,
                               label: label, isPlaceholder: value?.isEmpty != false,
                               isLeftOut: leftOut, payload: payload,
                               separatorAfter: index < inline.items.count - 1 ? inline.separator : nil)
        }
    }

    private func firstFile(in node: FolderNode) -> PlannedFile? {
        node.files.first { $0.role == .main } ?? node.children.lazy.compactMap { firstFile(in: $0) }.first ?? node.files.first
    }

    /// Menu and button actions for a level row.
    private func editing(level: Int) -> TreeRowContent.Editing {
        TreeRowContent.Editing(
            remove: { edit { FolderTemplateEditor.remove($0, at: level) } },
            removeItem: { item in edit { FolderTemplateEditor.removeItem($0, level: level, item: item) } },
            extractItem: { item in edit { FolderTemplateEditor.extractItem($0, level: level, item: item, toSlot: level + 1) } },
            setSeparator: { separator in edit { FolderTemplateEditor.setSeparator(separator, in: $0, level: level) } })
    }

    // MARK: Drops

    /// Where a drop on a row's top or bottom edge, or on the side of one of its pieces, lands.
    /// nil = the row doesn't take template drops (folders that are already there).
    private func dropAction(for row: TreeRow) -> ((TreeDropPlace) -> DropAction?)? {
        let levelCount = FolderTemplateEditor.levels(settings.folderTemplate).count
        switch row.kind {
        case .folder(let node, let level, _):
            if node.depth == 0 { return { _ in .slot(0) } }
            guard let level else { return { _ in .slot(levelCount) } }
            return { place in
                switch place {
                case .above: return .slot(level)
                case .below: return .slot(level + 1)
                case .inline(let position): return .inline(level: level, position: position)
                }
            }
        case .ghost(let level, _):
            return { place in place == .above ? .slot(level) : .slot(level + 1) }
        case .files, .file:
            return { _ in .slot(levelCount) }
        case .other, .otherGroup:
            return nil
        }
    }

    private func apply(_ payload: FolderTemplateEditor.Payload, _ action: DropAction) {
        edit { template in
            switch action {
            case .slot(let slot):
                return FolderTemplateEditor.drop(payload, on: slot, in: template)
            case .inline(let level, let position):
                return FolderTemplateEditor.dropInline(payload, level: level, at: position, in: template)
            }
        }
    }

    private func edit(_ change: (String) -> String) {
        guard editable else { return }
        let updated = change(settings.folderTemplate)
        guard updated != settings.folderTemplate, NamingTemplates(folder: updated, file: settings.fileTemplate) != nil else {
            NSSound.beep()
            return
        }
        settings.folderTemplate = updated
    }

    // MARK: Expanding

    /// The folders down to the example file: open until changed by hand.
    private var chainPaths: Set<String> {
        var paths: Set<String> = [""]
        var path = ""
        for component in (example?.folder ?? "").split(separator: "/") {
            path = join(path, String(component))
            paths.insert(path)
        }
        return paths
    }

    private var chainNames: [String] {
        (example?.folder ?? "").split(separator: "/").map(String.init)
    }

    private func isExpanded(_ key: String, default value: Bool) -> Bool {
        expansion[key] ?? value
    }

    private func toggle(_ row: TreeRow, recursive: Bool) {
        let open = !(row.expanded ?? false)
        guard recursive else {
            expansion[row.id] = open
            return
        }
        switch row.kind {
        case .folder(let node, _, _):
            for key in keys(below: node) { expansion[key] = open }
        case .other(let path, _):
            expansion[row.id] = open
            // Folders already there are read one level at a time; go at most three deep.
            if open { expandOthers(path, depth: 3) }
        default:
            expansion[row.id] = open
        }
    }

    private func expandOthers(_ path: String, depth: Int) {
        guard depth > 0 else { return }
        for child in subfolders(path) ?? [] {
            let childPath = path + "/" + child
            expansion[TreeRow.folderKey(childPath)] = true
            expandOthers(childPath, depth: depth - 1)
        }
    }

    /// Every folder (and group of folders that are already there) in and below `node`.
    private func keys(below node: FolderNode) -> [String] {
        node.allPaths.flatMap { [TreeRow.folderKey($0), TreeRow.othersKey($0)] }
    }

    private func expandAll(_ tree: FolderNode) {
        var updated = expansion
        for key in keys(below: tree) { updated[key] = true }
        expansion = updated
    }

    /// Closes everything but the destination itself, so its first level still shows.
    private func collapseAll(_ tree: FolderNode) {
        var updated: [String: Bool] = [:]
        for key in keys(below: tree) { updated[key] = false }
        updated[TreeRow.folderKey("")] = true
        expansion = updated
    }

    private func applyLaunchExpansion() {
        #if DEBUG
        guard let mode = DemoData.launchExpandTree else { return }
        let tree = FolderTree.build(rootName: root.lastPathComponent, plan: plan)
        expandAll(tree)
        if mode == "files" {
            for path in tree.allPaths { expansion[TreeRow.filesKey(path)] = true }
        }
        #endif
    }

    // MARK: Disk

    private var refreshKey: String {
        "\(root.path)|\(model.isBusy)|\(model.session?.plan == nil)|\(destinations.mountRevision)"
    }

    private func subfolders(_ path: String) -> [String]? {
        _ = listing.revision
        return listing.subfolders(root: root, path: path, using: model.subfolderLister)
    }

    private func join(_ path: String, _ name: String) -> String {
        path.isEmpty ? name : path + "/" + name
    }

    private func countText(_ count: Int, _ one: String, _ many: String) -> String {
        "\(count) \(count == 1 ? one : many)"
    }
}

// MARK: - Row model

private struct TreeRow: Identifiable {
    enum Kind {
        /// A folder the offload uses. `level` is the template level it shows, if it shows one.
        case folder(FolderNode, level: Int?, exists: Bool)
        /// A level quick dump leaves out.
        case ghost(level: Int, template: String)
        /// The files in a folder (opens to list them).
        case files(path: String, files: [PlannedFile])
        case file(PlannedFile)
        /// A folder that's already there and isn't used by this offload.
        case other(path: String, name: String)
        /// Several of those, grouped.
        case otherGroup(path: String, count: Int)
    }

    let id: String
    let depth: Int
    let kind: Kind
    /// nil = nothing to open.
    let expanded: Bool?

    static func folderKey(_ path: String) -> String { "f:" + path }
    static func filesKey(_ path: String) -> String { "n:" + path }
    static func othersKey(_ path: String) -> String { "o:" + path }

    /// Shows a folder that's already on disk (for the legend).
    var isOnDisk: Bool {
        switch kind {
        case .folder(let node, _, let exists): return exists && node.depth > 0
        case .other, .otherGroup: return true
        default: return false
        }
    }
}

/// One side-by-side piece of a level name ("Coastline" in "Coastline_2026-10-25").
private struct TreeSegment: Identifiable {
    let index: Int
    /// What it comes out as ("Coastline"), or its label when it has no value.
    let text: String
    /// "Project"
    let label: String
    let isPlaceholder: Bool
    /// Quick dump leaves it out.
    let isLeftOut: Bool
    let payload: FolderTemplateEditor.Payload
    /// The separator shown after it, if another piece follows.
    let separatorAfter: String?

    var id: Int { index }
}

private struct TreeRowContent {
    enum Style { case root, new, existing, other, ghost, file, sidecar }

    struct Editing {
        let remove: () -> Void
        let removeItem: (Int) -> Void
        let extractItem: (Int) -> Void
        let setSeparator: (String) -> Void
    }

    var title: String
    var symbol: String
    var style: Style
    var detail: String?
    var trailingNote: String?
    var help: String
    /// Set on rows that show a template level.
    var level: Int?
    var description: String?
    var segments: [TreeSegment] = []
    /// The separator of a combined level.
    var separator: String?
    var editing: Editing?

    init(title: String, symbol: String, style: Style, detail: String? = nil, trailingNote: String? = nil, help: String) {
        self.title = title
        self.symbol = symbol
        self.style = style
        self.detail = detail
        self.trailingNote = trailingNote
        self.help = help
    }
}

enum TreeDropPlace: Equatable {
    case above, below
    /// Side by side, before the piece at this position.
    case inline(Int)
}

private struct TreeDropTarget: Equatable {
    var row: String
    var place: TreeDropPlace
}

private enum DropAction {
    case slot(Int)
    case inline(level: Int, position: Int)
}

// MARK: - Row view

private struct TreeRowView: View {
    let row: TreeRow
    let content: TreeRowContent
    let editable: Bool
    let acceptsTemplateDrops: Bool
    @Binding var dropTarget: TreeDropTarget?
    let toggle: (_ recursive: Bool) -> Void
    let perform: (FolderTemplateEditor.Payload, TreeDropPlace) -> Void
    let useFolder: @MainActor (URL) -> Bool

    @Environment(\.theme) private var theme
    @State private var hovering = false
    @State private var segmentFrames: [Int: CGRect] = [:]
    @State private var rowHeight: CGFloat = 18

    static let space = "lodgeTreeRow"
    private var indent: CGFloat { CGFloat(row.depth) * 12 }
    private var isLevel: Bool { content.level != nil && content.style != .ghost }
    private var draggable: Bool { editable && content.level != nil }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            disclosure
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                icon
                    .overlay(alignment: .leading) { handle }
                    .modifier(LevelDrag(enabled: draggable, payload: content.level.map { .level($0) },
                                        title: content.description ?? content.title))
                name
            }
            .opacity(content.style == .ghost ? 0.45 : 1)
            Spacer(minLength: 4)
            trailing
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.primary.opacity(editable && hovering && content.level != nil ? 0.07 : 0)))
        .padding(.leading, indent)
        .overlay(alignment: .top) {
            if dropTarget == TreeDropTarget(row: row.id, place: .above) {
                DropSlotLine().offset(y: -2).padding(.leading, indent + 14)
            }
        }
        .overlay(alignment: .bottom) {
            if dropTarget == TreeDropTarget(row: row.id, place: .below) {
                DropSlotLine().offset(y: 2).padding(.leading, indent + 26)
            }
        }
        .overlay(alignment: .topLeading) { inlineMarker }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowHeight = $0 }
        .coordinateSpace(.named(Self.space))
        .onDrop(of: [.plainText, .fileURL],
                delegate: RowDropDelegate(rowID: row.id, editable: acceptsTemplateDrops,
                                          inline: editable && isLevel && !content.segments.isEmpty,
                                          frames: content.segments.compactMap { segmentFrames[$0.index] },
                                          rowHeight: rowHeight, target: $dropTarget,
                                          perform: perform, useFolder: useFolder))
        .contextMenu { menu }
        .help(helpText)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: Parts

    @ViewBuilder
    private var disclosure: some View {
        if let expanded = row.expanded {
            Button {
                toggle(NSEvent.modifierFlags.contains(.option))
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .frame(width: 10, height: 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(expanded ? "Collapse (Option-click to collapse everything inside)"
                           : "Expand (Option-click to expand everything inside)")
            .accessibilityLabel(expanded ? "Collapse \(content.title)" : "Expand \(content.title)")
        } else {
            Color.clear.frame(width: 10, height: 1)
        }
    }

    @ViewBuilder
    private var icon: some View {
        let image = Image(systemName: content.symbol)
        switch content.style {
        case .root, .new, .ghost, .file: image.foregroundStyle(.tint)
        case .existing: image.foregroundStyle(.secondary)
        case .other, .sidecar: image.foregroundStyle(.tertiary)
        }
    }

    /// The grip shown to the left of a level while the pointer is over it.
    private var handle: some View {
        Image(systemName: "line.3.horizontal")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .opacity(editable && hovering && content.level != nil ? 1 : 0)
            .offset(x: -27)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var name: some View {
        if isLevel && !content.segments.isEmpty {
            SegmentFlow {
                ForEach(content.segments) { segment in
                    SegmentView(segment: segment, editable: editable, editing: content.editing,
                                combined: content.segments.count > 1)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: {
                            segmentFrames[segment.index] = $0
                        }
                    if let separator = segment.separatorAfter, !separator.isEmpty {
                        Text(separator == " " ? "\u{00A0}" : separator)
                            .foregroundStyle(segment.isLeftOut || segment.isPlaceholder ? .tertiary : .primary)
                            .accessibilityHidden(true)
                    }
                }
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(content.title)
                    .strikethrough(content.style == .ghost, color: .secondary)
                    .foregroundStyle(content.style == .other || content.style == .sidecar ? .secondary : .primary)
                if let note = content.trailingNote {
                    Text(" " + note).foregroundStyle(.secondary)
                }
            }
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if content.style == .ghost {
            TreeTag("Quick dump")
        } else if let detail = content.detail {
            Text(detail).foregroundStyle(.secondary).fixedSize()
        }
        if content.level != nil {
            if editable && hovering {
                if let separator = content.separator, let editing = content.editing {
                    SeparatorMenu(separator: separator, set: editing.setSeparator)
                } else if content.style != .ghost, let description = content.description {
                    Text(description).font(.caption2).foregroundStyle(.secondary).fixedSize()
                }
                if let editing = content.editing {
                    Button(action: editing.remove) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove this folder level")
                    .accessibilityLabel("Remove \(content.description ?? content.title) level")
                }
            } else if !editable, content.style != .ghost, let description = content.description {
                Text(description).font(.caption2).foregroundStyle(.secondary).fixedSize()
            }
        }
    }

    /// The vertical line where a piece dropped side by side would go.
    @ViewBuilder
    private var inlineMarker: some View {
        if let target = dropTarget, target.row == row.id, case .inline(let position) = target.place {
            let frames = content.segments.compactMap { segmentFrames[$0.index] }
            if !frames.isEmpty {
                let anchor = position < frames.count ? frames[position] : frames[frames.count - 1]
                let x: CGFloat = {
                    if position == 0 { return frames[0].minX - 1.5 }
                    if position >= frames.count { return frames[frames.count - 1].maxX + 1.5 }
                    return (frames[position - 1].maxX + frames[position].minX) / 2
                }()
                Capsule()
                    .fill(theme.accent)
                    .frame(width: 2, height: anchor.height + 4)
                    .offset(x: x - 1, y: anchor.minY - 2)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private var menu: some View {
        if editable, let editing = content.editing {
            if let separator = content.separator {
                Picker("Separator", selection: Binding(get: { separator }, set: editing.setSeparator)) {
                    ForEach(InlineLevel.separators, id: \.self) { option in
                        Text("\(InlineLevel.name(ofSeparator: option))  \(InlineLevel.symbol(ofSeparator: option))").tag(option)
                    }
                }
            }
            Button("Remove Folder Level", action: editing.remove)
        }
    }

    private var helpText: String {
        guard editable, content.level != nil else { return content.help }
        if content.style == .ghost { return content.help }
        return "\(content.help). Drag to move this level; drop a token on the side of a name to combine them."
    }

    private var accessibilityText: String {
        switch content.style {
        case .ghost: return "\(content.title) folder, left out by quick dump"
        case .existing: return "Folder \(content.title), already there"
        case .new: return "Folder \(content.title), will be created"
        case .other: return "\(content.title), already there, not used"
        default: return content.title
        }
    }
}

/// Dragging a level by its folder icon.
private struct LevelDrag: ViewModifier {
    let enabled: Bool
    let payload: FolderTemplateEditor.Payload?
    let title: String

    func body(content: Content) -> some View {
        if enabled, let payload {
            content.onDrag {
                NSItemProvider(object: FolderTemplateEditor.text(for: payload) as NSString)
            } preview: {
                DragChip(text: title, symbol: "folder")
            }
        } else {
            content
        }
    }
}

/// One piece of a level's name. Drag it to move it (side by side, or out to its own level).
private struct SegmentView: View {
    let segment: TreeSegment
    let editable: Bool
    let editing: TreeRowContent.Editing?
    let combined: Bool
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        let text = Text(segment.text)
            .strikethrough(segment.isLeftOut, color: .secondary)
            .foregroundStyle(segment.isLeftOut || segment.isPlaceholder ? .secondary : .primary)
        if editable {
            text
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .background(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(theme.accent.opacity(hovering && combined ? 0.16 : 0))
                        .padding(-1))
                .onHover { hovering = $0 }
                .onDrag {
                    NSItemProvider(object: FolderTemplateEditor.text(for: segment.payload) as NSString)
                } preview: {
                    DragChip(text: segment.label, symbol: combined ? "rectangle.split.2x1" : "folder")
                }
                .contextMenu {
                    if let editing, combined {
                        Button("Move “\(segment.label)” to Its Own Level") { editing.extractItem(segment.index) }
                        Button("Remove “\(segment.label)”") { editing.removeItem(segment.index) }
                        Divider()
                    }
                    if let editing {
                        Button("Remove Folder Level", action: editing.remove)
                    }
                }
                .help(combined ? "\(segment.label). Drag to reorder, or drag between folders to make it its own level."
                               : "\(segment.label). Drag to move this level.")
                .opacity(segment.isLeftOut ? 0.45 : 1)
        } else {
            text
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// "_" ▾: what goes between the pieces of a combined level.
private struct SeparatorMenu: View {
    let separator: String
    let set: (String) -> Void

    var body: some View {
        Menu {
            ForEach(InlineLevel.separators, id: \.self) { option in
                Button {
                    set(option)
                } label: {
                    if option == separator {
                        Label("\(InlineLevel.name(ofSeparator: option))  \(InlineLevel.symbol(ofSeparator: option))",
                              systemImage: "checkmark")
                    } else {
                        Text("\(InlineLevel.name(ofSeparator: option))  \(InlineLevel.symbol(ofSeparator: option))")
                    }
                }
            }
        } label: {
            Text(InlineLevel.symbol(ofSeparator: separator))
                .font(.caption2.weight(.semibold))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .fixedSize()
        .help("What goes between the names side by side")
        .accessibilityLabel("Separator, \(InlineLevel.name(ofSeparator: separator))")
    }
}

/// Lays pieces out left to right and wraps onto more lines rather than cutting anything off.
/// A piece wider than the row wraps inside itself.
private struct SegmentFlow: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let placed = arrange(width: width, subviews: subviews)
        let height = placed.map { $0.frame.maxY }.max() ?? 0
        let used = placed.map { $0.frame.maxX }.max() ?? 0
        return CGSize(width: proposal.width.map { min($0, used) } ?? used, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for item in arrange(width: bounds.width, subviews: subviews) {
            subviews[item.index].place(at: CGPoint(x: bounds.minX + item.frame.minX, y: bounds.minY + item.frame.minY),
                                       proposal: ProposedViewSize(item.frame.size))
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [(index: Int, frame: CGRect)] {
        var result: [(Int, CGRect)] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for index in subviews.indices {
            var size = subviews[index].sizeThatFits(.unspecified)
            if size.width > width {
                size = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
            }
            if x > 0 && x + size.width > width {
                x = 0
                y += lineHeight
                lineHeight = 0
            }
            result.append((index, CGRect(origin: CGPoint(x: x, y: y), size: size)))
            x += size.width
            lineHeight = max(lineHeight, size.height)
        }
        return result
    }
}

/// Drops on a row: near its top or bottom edge make a new level there; on the side of a
/// piece of its name, the dragged token goes side by side. Finder folders become the destination.
private struct RowDropDelegate: DropDelegate {
    let rowID: String
    let editable: Bool
    let inline: Bool
    let frames: [CGRect]
    let rowHeight: CGFloat
    @Binding var target: TreeDropTarget?
    let perform: (FolderTemplateEditor.Payload, TreeDropPlace) -> Void
    let useFolder: @MainActor (URL) -> Bool

    /// Where a drop at `location` (in the row's own coordinates) lands.
    static func place(at location: CGPoint, frames: [CGRect], rowHeight: CGFloat, inline: Bool) -> TreeDropPlace {
        let edge = min(6, rowHeight * 0.3)
        if inline, !frames.isEmpty, location.y > edge, location.y < rowHeight - edge,
           location.x >= frames[0].minX - 6 {
            // The nearest piece, then which half of it.
            let nearest = frames.indices.min { a, b in
                distance(location, frames[a]) < distance(location, frames[b])
            } ?? 0
            return .inline(location.x < frames[nearest].midX ? nearest : nearest + 1)
        }
        return location.y < rowHeight / 2 ? .above : .below
    }

    private static func distance(_ point: CGPoint, _ rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy * 4
    }

    private func isTemplateDrag(_ info: DropInfo) -> Bool {
        editable && !info.hasItemsConforming(to: [.fileURL]) && info.hasItemsConforming(to: [.plainText])
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL]) || isTemplateDrag(info)
    }

    func dropEntered(info: DropInfo) {
        if isTemplateDrag(info) { target = TreeDropTarget(row: rowID, place: Self.place(at: info.location, frames: frames, rowHeight: rowHeight, inline: inline)) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        if isTemplateDrag(info) {
            let next = TreeDropTarget(row: rowID, place: Self.place(at: info.location, frames: frames, rowHeight: rowHeight, inline: inline))
            if next != target { target = next }
        }
        return DropProposal(operation: info.hasItemsConforming(to: [.fileURL]) ? .copy : .move)
    }

    func dropExited(info: DropInfo) {
        if target?.row == rowID { target = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        let place = Self.place(at: info.location, frames: frames, rowHeight: rowHeight, inline: inline)
        target = nil
        if info.hasItemsConforming(to: [.fileURL]) {
            return FolderDrop.load(info.itemProviders(for: [.fileURL]), use: useFolder)
        }
        guard editable, let provider = info.itemProviders(for: [.plainText]).first else { return false }
        let perform = perform
        _ = provider.loadObject(ofClass: String.self) { text, _ in
            guard let text, let payload = FolderTemplateEditor.payload(text) else { return }
            Task { @MainActor in
                perform(payload, place)
                Haptics.dropAccepted()
            }
        }
        return true
    }
}

/// "New" and "Already there" folder icons.
private struct Legend: View {
    var body: some View {
        HStack(spacing: 10) {
            Label { Text("New") } icon: { Image(systemName: "folder").foregroundStyle(.tint) }
            Label { Text("Already there") } icon: { Image(systemName: "folder.fill").foregroundStyle(.secondary) }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
        .accessibilityElement(children: .combine)
    }
}

/// Where a dragged level or token will land.
private struct DropSlotLine: View {
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            Circle().strokeBorder(theme.accent, lineWidth: 1.5).frame(width: 6, height: 6)
            Capsule().fill(theme.accent).frame(height: 2)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.6, anchor: .leading)))
        .allowsHitTesting(false)
    }
}

private struct TreeTag: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.secondary.opacity(0.15), in: Capsule())
    }
}

/// Tokens you can drag onto the tree (or click to add as the last level).
private struct TokenPalette: View {
    let add: (TemplateToken) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Add a level")
                .font(.caption2)
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 4) {
                ForEach(FolderTemplateEditor.levelTokens) { token in
                    TokenChip(token: token, add: add)
                }
            }
        }
    }
}

private struct TokenChip: View {
    let token: TemplateToken
    let add: (TemplateToken) -> Void
    @State private var hovering = false

    var body: some View {
        let title = TemplateDescription.level(token.placeholder)
        Button { add(token) } label: {
            Text(title)
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(hovering ? 0.14 : 0.08), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .onDrag {
            NSItemProvider(object: FolderTemplateEditor.text(for: .token(token)) as NSString)
        } preview: {
            DragChip(text: title, symbol: "folder.badge.plus")
        }
        .help("\(token.summary). Drag between folders for a new level, or onto the side of a folder’s name to combine them. Click to add it as the last folder.")
        .accessibilityLabel("Add \(title) folder level")
    }
}

private struct DragChip: View {
    let text: String
    let symbol: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: Capsule())
    }
}
