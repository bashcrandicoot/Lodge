import SwiftUI

/// Settings ▸ Naming: the folder and file templates, token chips, examples and a live example.
struct NamingSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @FocusState private var focused: TemplateField?
    /// The field token chips insert into (the last one that had focus).
    @State private var target: TemplateField = .file

    enum TemplateField: Hashable { case folder, file }

    var body: some View {
        Form {
            Section {
                templateEditor(
                    title: "Folder structure",
                    text: $settings.folderTemplate,
                    field: .folder,
                    issues: settings.folderIssues,
                    note: "“/” makes a subfolder. Leave empty to put files straight into the destination.")
                templateEditor(
                    title: "File name",
                    text: $settings.fileTemplate,
                    field: .file,
                    issues: settings.fileIssues,
                    note: "The extension (.mp4, .arw…) is always added, in lower case.",
                    trailing: ".ext")
            } header: {
                HStack {
                    Text("Templates")
                    Spacer()
                    presetsMenu
                }
            }

            Section {
                TokenChips { insert($0) }
            } header: {
                Text("Insert Token")
            } footer: {
                Text("Click a token to add it to the \(target == .folder ? "folder structure" : "file name").")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Example") {
                ExamplePaths()
            }
        }
        .formStyle(.grouped)
        .frame(width: 600, height: 620)
        .onChange(of: focused) { _, newValue in
            if let newValue { target = newValue }
        }
    }

    private var presetsMenu: some View {
        Menu("Examples") {
            ForEach(NamingPreset.all) { preset in
                Button {
                    settings.apply(preset)
                } label: {
                    if settings.folderTemplate == preset.folder && settings.fileTemplate == preset.file {
                        Label(preset.name, systemImage: "checkmark")
                    } else {
                        Text(preset.name)
                    }
                }
            }
            Divider()
            Button("Reset to Default") { settings.apply(NamingPreset.all[0]) }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .textCase(nil)
    }

    private func templateEditor(title: String, text: Binding<String>, field: TemplateField,
                                issues: [TemplateIssue], note: String, trailing: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            HStack(spacing: 6) {
                TextField(title, text: text, prompt: Text(field == .folder ? "Files go straight into the destination" : "{date}_{project}_{seq}"))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .labelsHidden()
                    .focused($focused, equals: field)
                    .autocorrectionDisabled()
                if let trailing {
                    Text(trailing)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            if issues.isEmpty {
                Text(note).font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(issues, id: \.message) { issue in
                    Label(issue.message, systemImage: issue.severity == .error
                          ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(issue.severity == .error ? Color.red : Color.orange)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func insert(_ token: TemplateToken) {
        switch target {
        case .folder: settings.folderTemplate += token.placeholder
        case .file: settings.fileTemplate += token.placeholder
        }
        focused = target
    }
}

/// A wrapping row of token buttons.
private struct TokenChips: View {
    @Environment(\.theme) private var theme
    let insert: (TemplateToken) -> Void

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(TemplateToken.allCases) { token in
                Button {
                    insert(token)
                } label: {
                    Text(token.placeholder)
                        .font(.system(.callout, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(theme.accent.opacity(0.12), in: Capsule())
                        .foregroundStyle(theme.accent)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(token.summary)
                .accessibilityLabel("Insert \(token.rawValue) token")
                .accessibilityHint(token.summary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// What the current templates produce for a sample video and photo.
private struct ExamplePaths: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var cameras: CameraStore

    var body: some View {
        if let naming = settings.naming {
            let plan = OffloadPlanner.plan(files: Self.samples, naming: naming, context: context, existingNames: { _ in [] })
            VStack(alignment: .leading, spacing: 8) {
                ForEach(plan) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: item.category.symbol)
                            .foregroundStyle(.tint)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(path(item))
                                .font(.system(.callout, design: .monospaced))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("from \(item.originalName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        } else {
            Label("Fix the problems above to see an example.", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        }
    }

    private func path(_ item: PlannedFile) -> String {
        let root = settings.destinationURL?.lastPathComponent ?? "Destination"
        return root + "/" + item.relativePath
    }

    private var context: NamingContext {
        let project = NamingContext.clean(settings.lastProject)
        let camera = (cameras.camera(id: cameras.lastCameraID) ?? cameras.cameras.first)?.tokenValue ?? ""
        return NamingContext(project: project.isEmpty ? "Coastline" : project,
                             camera: camera.isEmpty ? "FX3" : camera, card: "A7SIII")
    }

    static let samples: [Clip] = {
        var components = DateComponents()
        components.year = 2026; components.month = 10; components.day = 25
        components.hour = 14; components.minute = 30; components.second = 5
        let date = Calendar.current.date(from: components) ?? Date()
        return [
            Clip(url: URL(fileURLWithPath: "/Volumes/A7SIII/PRIVATE/M4ROOT/CLIP/C0001.MP4"),
                 relativePath: "PRIVATE/M4ROOT/CLIP/C0001.MP4", size: 0, creationDate: date, modificationDate: date),
            Clip(url: URL(fileURLWithPath: "/Volumes/A7SIII/DCIM/100MSDCF/DSC00012.ARW"),
                 relativePath: "DCIM/100MSDCF/DSC00012.ARW", size: 0,
                 creationDate: date.addingTimeInterval(60), modificationDate: date.addingTimeInterval(60)),
        ]
    }()
}

/// Lays out views left to right, wrapping onto new lines (like words in a paragraph).
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width && !current.indices.isEmpty {
                rows.append(current)
                current = Row(y: current.y + current.height + spacing)
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.indices.append(index)
            current.height = max(current.height, size.height)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

#if DEBUG
#Preview("Naming settings") {
    NamingSettingsView().demoEnvironment(DemoData.model(state: .ready))
}
#endif
