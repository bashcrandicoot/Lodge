import SwiftUI
import AppKit

// MARK: - Short-clip slider (Settings ▸ General and the preset editor)

/// "Skip videos shorter than": a 0–30 s slider in 1 s steps (0 = off), the value, and a
/// stepper for fine-tuning (up to 60 s).
struct ShortClipSlider: View {
    /// Seconds; 0 = don't skip short videos.
    @Binding var seconds: Int

    static let sliderRange = 0...30

    var body: some View {
        HStack(spacing: 10) {
            Slider(value: Binding(
                get: { Double(min(seconds, Self.sliderRange.upperBound)) },
                set: { seconds = Int($0.rounded()) }),
                   in: Double(Self.sliderRange.lowerBound)...Double(Self.sliderRange.upperBound), step: 1) {
                Text("Skip videos shorter than")
            } minimumValueLabel: {
                Text("Off").font(.caption).foregroundStyle(.secondary)
            } maximumValueLabel: {
                Text("30 s").font(.caption).foregroundStyle(.secondary)
            }
            .labelsHidden()
            Text(Self.label(seconds))
                .monospacedDigit()
                .foregroundStyle(seconds == 0 ? .secondary : .primary)
                .frame(width: 44, alignment: .trailing)
                .contentTransition(.numericText(value: Double(seconds)))
                .animation(.snappy(duration: 0.2), value: seconds)
            Stepper("", value: $seconds, in: 0...ShortClipRule.thresholdRange.upperBound)
                .labelsHidden()
                .accessibilityLabel("Skip videos shorter than, in seconds")
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue(seconds == 0 ? "Off" : DurationFormatting.threshold(Double(seconds)))
    }

    /// "Off", "5 s"
    static func label(_ seconds: Int) -> String {
        seconds <= 0 ? "Off" : "\(seconds) s"
    }
}

// MARK: - Main window switcher

/// The preset switcher at the right of the toolbar, next to Recent Offloads and Settings:
/// pick a preset, save the current setup as one, update the active one, or manage them in Settings.
struct PresetSwitcher: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var presets: PresetStore
    @Environment(\.openSettings) private var openSettings
    @State private var naming = false
    @State private var newName = ""

    var body: some View {
        let active = presets.activePreset
        let edited = model.activePresetIsEdited
        Menu {
            if presets.presets.isEmpty {
                Text("No presets yet")
            }
            ForEach(presets.presets) { preset in
                Button {
                    model.applyPreset(preset)
                } label: {
                    if preset.id == active?.id {
                        Label(preset.displayName, systemImage: "checkmark")
                    } else {
                        Text(preset.displayName)
                    }
                }
                .help(preset.summary)
            }
            Divider()
            Button("Save Current Setup as Preset…") {
                newName = presets.uniqueName(active.map { $0.displayName + " Copy" } ?? "New Preset")
                naming = true
            }
            if let active, edited {
                Button("Update “\(active.displayName)”") { model.updateActivePresetFromCurrentSetup() }
            }
            Divider()
            Button("Manage Presets…") {
                UserDefaults.standard.set(SettingsTab.presets.rawValue, forKey: SettingsTab.storageKey)
                openSettings()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up")
                Text(active?.displayName ?? "No Preset")
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    // A very long name can't push the toolbar into overflow at the minimum width.
                    .frame(maxWidth: 220)
                if edited {
                    Text("Edited")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .menuIndicator(.visible)
        .fixedSize()
        .disabled(model.isBusy)
        .help(active.map { "Preset: \($0.summary)" } ?? "Save your destination, naming and file rules as a preset to switch in one click")
        .accessibilityLabel("Preset, \(active?.displayName ?? "none")\(edited ? ", edited" : "")")
        .alert("Save Preset", isPresented: $naming) {
            TextField("Name", text: $newName)
            Button("Save") { model.saveCurrentSetupAsPreset(named: newName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saves the destination, naming, camera, short-clip setting, quick dump and file rules.")
        }
    }
}

// MARK: - Settings ▸ Presets

struct PresetsSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var presets: PresetStore
    @State private var selection: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Presets")
                    .font(.headline)
                Text("A preset saves where files go, how they’re named, the camera, short-clip skipping, quick dump and the file rules. Switch presets from the menu at the top right of the main window.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 0) {
                    list
                    Divider()
                    controlBar
                }
                .frame(width: 190)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.separator))

                Group {
                    if let id = selection, presets.preset(id: id) != nil {
                        PresetEditor(id: id)
                            .id(id)
                    } else {
                        ContentUnavailableView {
                            Label("No Preset Selected", systemImage: "square.stack.3d.up")
                        } description: {
                            Text(presets.presets.isEmpty ? "Click + to save the current setup as a preset." : "Select a preset to edit it.")
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            if let error = presets.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(20)
        .frame(width: 640, height: 540)
        .onAppear { if selection == nil { selection = presets.activeID ?? presets.presets.first?.id } }
    }

    private var list: some View {
        List(selection: $selection) {
            ForEach(presets.presets) { preset in
                HStack(spacing: 6) {
                    Image(systemName: "square.stack.3d.up")
                        .foregroundStyle(.tint)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(preset.displayName).lineLimit(1)
                        if preset.id == presets.activeID {
                            Text(model.activePresetIsEdited ? "In use · edited" : "In use")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 2)
                .tag(preset.id)
                .contextMenu {
                    Button("Apply") { model.applyPreset(preset) }
                    Button("Duplicate") { presets.duplicate(preset.id) }
                    Divider()
                    Button("Delete", role: .destructive) { delete(preset.id) }
                }
            }
            .onMove { presets.move(fromOffsets: $0, toOffset: $1) }
        }
        .listStyle(.inset(alternatesRowBackgrounds: false))
        .scrollContentBackground(.hidden)
        .onDeleteCommand { if let selection { delete(selection) } }
    }

    private var controlBar: some View {
        HStack(spacing: 0) {
            Button {
                let preset = presets.add(model.currentSetupAsPreset(name: "New Preset"))
                selection = preset.id
            } label: {
                Image(systemName: "plus").frame(width: 24, height: 20)
            }
            .help("Save the current setup as a new preset")
            .accessibilityLabel("Add preset")
            Divider().frame(height: 16)
            Button { if let selection { delete(selection) } } label: {
                Image(systemName: "minus").frame(width: 24, height: 20)
            }
            .disabled(selection == nil)
            .help("Delete the selected preset")
            .accessibilityLabel("Delete preset")
            Divider().frame(height: 16)
            Button {
                if let selection {
                    presets.duplicate(selection)
                    self.selection = presets.presets.last?.id
                }
            } label: {
                Image(systemName: "plus.square.on.square").frame(width: 24, height: 20)
            }
            .disabled(selection == nil)
            .help("Duplicate the selected preset")
            .accessibilityLabel("Duplicate preset")
            Spacer()
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    private func delete(_ id: UUID) {
        let index = presets.presets.firstIndex { $0.id == id } ?? 0
        presets.delete([id])
        selection = presets.presets.indices.contains(index) ? presets.presets[index].id : presets.presets.last?.id
    }
}

/// Edits one preset. Changes to the preset in use apply right away (unless the main window
/// setup was changed since, which the switcher shows as "Edited").
private struct PresetEditor: View {
    let id: UUID
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var presets: PresetStore
    @EnvironmentObject private var destinations: DestinationStore
    @EnvironmentObject private var cameras: CameraStore

    private var preset: OffloadPreset { presets.preset(id: id) ?? OffloadPreset(id: id, name: "") }
    private var isActive: Bool { presets.activeID == id }

    var body: some View {
        let preset = preset
        Form {
            TextField("Name", text: Binding(
                get: { self.preset.name },
                set: { presets.rename(id, to: $0) }))
            Picker("Destination", selection: binding(\.destinationPath)) {
                Text("Keep current folder").tag(String?.none)
                Divider()
                ForEach(destinations.favorites) { favorite in
                    Text(favorite.displayName).tag(Optional(favorite.path))
                }
                if let path = preset.destinationPath, destinations.favorite(forPath: path) == nil {
                    Text((path as NSString).abbreviatingWithTildeInPath).tag(Optional(path))
                }
            }
            LabeledContent("Folders") {
                TextField("Folders", text: binding(\.folderTemplate), prompt: Text("None: straight into the destination"))
                    .labelsHidden()
                    .font(.system(.body, design: .monospaced))
            }
            LabeledContent("Files") {
                TextField("Files", text: binding(\.fileTemplate))
                    .labelsHidden()
                    .font(.system(.body, design: .monospaced))
            }
            if NamingTemplates(folder: preset.folderTemplate, file: preset.fileTemplate) == nil {
                Label("These templates aren’t valid. Check them in the Naming tab.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Picker("Camera", selection: binding(\.cameraID)) {
                Text("Suggested for the card").tag(UUID?.none)
                Divider()
                ForEach(cameras.cameras) { camera in
                    Text(camera.name).tag(Optional(camera.id))
                }
            }
            LabeledContent("Short clips") {
                ShortClipSlider(seconds: Binding(
                    get: { self.preset.skipShortClips ? self.preset.shortClipSeconds : 0 },
                    set: { value in
                        change { preset in
                            if value <= 0 {
                                preset.skipShortClips = false
                            } else {
                                preset.skipShortClips = true
                                preset.shortClipSeconds = value
                            }
                        }
                    }))
            }
            Toggle(isOn: binding(\.quickDump)) {
                HStack(spacing: 4) {
                    Text("Quick dump")
                    InfoHint(text: QuickDumpHelp.text, subject: "Quick dump")
                }
            }
            .accessibilityHint(QuickDumpHelp.text)
            LabeledContent("File rules") {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(Self.rulesSummary(preset.fileRules))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                    Button("Use Current File Rules") { change { $0.fileRules = settings.fileRules } }
                        .controlSize(.small)
                        .disabled(preset.fileRules == settings.fileRules)
                }
            }
            HStack {
                Button("Update from Current Setup") {
                    var updated = model.currentSetupAsPreset(name: preset.name)
                    updated.id = id
                    presets.update(updated)
                }
                .help("Replace this preset’s settings with what the main window uses now")
                Spacer()
                if isActive && !model.activePresetIsEdited {
                    Label("In Use", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                } else {
                    Button("Apply") { model.applyPreset(self.preset) }
                        .buttonStyle(.themeProminent)
                        .disabled(model.isBusy)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(-20)
        .padding(.horizontal, 0)
    }

    static func rulesSummary(_ rules: FileRules) -> String {
        let proxies = rules.proxyExtensions.isEmpty ? "none" : rules.proxyExtensions.map { "." + $0 }.joined(separator: " ")
        let sidecars = rules.sidecarExtensions.isEmpty ? "none" : rules.sidecarExtensions.map { "." + $0 }.joined(separator: " ")
        let ignored = rules.ignorePatterns.count
        return "Proxies \(proxies)\nSidecars \(sidecars)\n\(ignored) ignore \(ignored == 1 ? "rule" : "rules")"
    }

    private func binding<T>(_ keyPath: WritableKeyPath<OffloadPreset, T>) -> Binding<T> {
        Binding(get: { self.preset[keyPath: keyPath] },
                set: { value in change { $0[keyPath: keyPath] = value } })
    }

    /// Saves a change; the preset in use (if the setup still matches it) follows right away.
    private func change(_ edit: (inout OffloadPreset) -> Void) {
        guard var updated = presets.preset(id: id) else { return }
        let followsSetup = isActive && !model.activePresetIsEdited && !model.isBusy
        edit(&updated)
        presets.update(updated)
        if followsSetup { model.applyPreset(updated) }
    }
}

// MARK: - Settings ▸ Files

/// Proxy and sidecar extensions, and the ignore list.
struct FilesSettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section {
                EditableList(items: Binding(get: { settings.fileRules.proxyExtensions },
                                            set: { settings.fileRules.proxyExtensions = FileRules.cleanExtensions($0) }),
                             prompt: "Add an extension, e.g. lrv", prefix: ".", clean: FileRules.cleanExtension)
            } header: {
                Text("Proxies")
            } footer: {
                footnote("Low-res copies like GoPro .LRV and DJI .LRF go into a Proxies folder inside the shoot folder, named after their clip. They’re never treated as footage and never skipped on their own: they follow their clip.")
            }
            Section {
                EditableList(items: Binding(get: { settings.fileRules.sidecarExtensions },
                                            set: { settings.fileRules.sidecarExtensions = FileRules.cleanExtensions($0) }),
                             prompt: "Add an extension, e.g. thm", prefix: ".", clean: FileRules.cleanExtension)
            } header: {
                Text("Sidecars")
            } footer: {
                footnote("Thumbnails, metadata and telemetry (.THM, .XML, .SRT) go into a Sidecars folder. Audio recorded with a clip (.WAV) goes in the WAV folder with the clip’s name.")
            }
            Section {
                EditableList(items: Binding(get: { settings.fileRules.ignorePatterns },
                                            set: { settings.fileRules.ignorePatterns = FileRules.cleanPatterns($0) }),
                             prompt: "Add a name or pattern, e.g. *.tmp", prefix: "",
                             clean: { FileRules.cleanPatterns([$0]).first },
                             warning: { FileRules.ignoresMainMedia($0) ? "would hide footage" : nil })
                let risky = settings.fileRules.ignorePatterns.filter(FileRules.ignoresMainMedia)
                if !risky.isEmpty {
                    Label("\(risky.joined(separator: ", ")) matches photos or videos. Those files won’t be offloaded, and formatting the card erases them.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Ignore List")
            } footer: {
                footnote("Ignored files are never copied and don’t stop a card being ready to format. The card shows how many there are. Use * and ? as wildcards, or .ext for an extension.")
            }
            HStack {
                Spacer()
                Button("Restore Defaults") { settings.fileRules = .standard }
                    .disabled(settings.fileRules == .standard)
            }
        }
        .formStyle(.grouped)
        .themeControlTint()
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Removable chips plus an "Add" field.
private struct EditableList: View {
    @Binding var items: [String]
    let prompt: String
    let prefix: String
    let clean: (String) -> String?
    var warning: (String) -> String? = { _ in nil }
    @State private var draft = ""
    @State private var invalid = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if items.isEmpty {
                Text("None")
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(items, id: \.self) { item in
                        Chip(text: prefix + item, warning: warning(item) != nil) {
                            withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                                items.removeAll { $0 == item }
                            }
                        }
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                }
            }
            HStack {
                TextField("Add", text: $draft, prompt: Text(prompt))
                    .labelsHidden()
                    .onSubmit(add)
                    .onChange(of: draft) { _, _ in invalid = false }
                Button("Add", action: add)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if invalid {
                Text("That can’t be used here.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }

    private func add() {
        guard let value = clean(draft) else {
            invalid = !draft.trimmingCharacters(in: .whitespaces).isEmpty
            return
        }
        if !items.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { items.append(value) }
        }
        draft = ""
    }
}

private struct Chip: View {
    let text: String
    let warning: Bool
    let remove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 4) {
            if warning {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            Text(text)
                .font(.system(.callout, design: .monospaced))
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(hovering ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help("Remove \(text)")
            .accessibilityLabel("Remove \(text)")
        }
        .padding(.leading, 8)
        .padding(.trailing, 5)
        .padding(.vertical, 3)
        .background(Color.primary.opacity(0.07), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
    }
}

#if DEBUG
#Preview("Presets settings") {
    PresetsSettingsView().demoEnvironment(DemoData.model(state: .ready))
}

#Preview("Files settings") {
    FilesSettingsView().demoEnvironment(DemoData.model(state: .ready))
}
#endif
