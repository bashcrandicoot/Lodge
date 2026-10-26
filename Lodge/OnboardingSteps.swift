import SwiftUI
import AppKit

private func folderBlue(_ scheme: ColorScheme) -> Color {
    Color(hex: scheme == .dark ? 0x5BAEF7 : 0x1E90F5)
}

private func cardTitle(_ text: String) -> some View {
    Text(text).font(.system(size: 13, weight: .semibold))
}

// MARK: - 02 What's a preset?

struct OnboardingTemplateStep: View {
    @Environment(\.colorScheme) private var scheme
    let draft: OnboardingDraft

    private static let scattered: [(String, CGFloat, CGFloat, Double)] = [
        ("A001C003_230914_R2EK.MXF", 18, 40, -3), ("DCIM/", 200, 22, 2), ("DSC_0042.ARW", 160, 58, 3),
        ("ZOOM0001_TR1.WAV", 32, 82, -1), ("C0017.MP4", 170, 102, -2), ("IMG_8812.HEIC", 14, 124, 1),
        ("A001C004_230914_R2EK.MXF", 128, 146, 2), ("CLIP0003.XML", 24, 166, -1),
    ]

    var body: some View {
        let palette = OnboardingPalette(scheme)
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 0) {
                OnboardingCard {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Your card today").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                        ZStack(alignment: .topLeading) {
                            ForEach(Self.scattered, id: \.0) { name, x, y, angle in
                                Text(name)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6).padding(.vertical, 3)
                                    .background(palette.chip, in: RoundedRectangle(cornerRadius: 6))
                                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(palette.stroke))
                                    .rotationEffect(.degrees(angle))
                                    .offset(x: x, y: y - 20)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
                .frame(height: 252)

                VStack(spacing: 6) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(LinearGradient(colors: [Color(hex: 0x2E2150), Color(hex: 0x1A1433)], startPoint: .top, endPoint: .bottom))
                        RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.12))
                        Image("LodgeGlyph").resizable().aspectRatio(contentMode: .fit).frame(width: 42, height: 42)
                    }
                    .frame(width: 58, height: 58)
                    Text("Preset").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    Image(systemName: "arrow.right").font(.system(size: 18, weight: .light)).foregroundStyle(palette.tertiary)
                }
                .frame(width: 96)

                OnboardingCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("With Lodge").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                        PreviewTreeView(rows: PreviewTree.rows(root: draft.destinationPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Movies", plan: OnboardingSamples.plan(draft), filesPerFolder: 1),
                                        rowHeight: 20, rootSymbol: "folder")
                    }
                }
                .frame(height: 252)
            }
            HStack(spacing: 12) {
                value("square.3.layers.3d", tint: .accentColor, title: "Set it once",
                      text: "Destination, folders and naming saved as one preset you can switch to in a click.")
                value("checkmark.shield", tint: .green, title: "Copies you can trust",
                      text: "Every file is read back and checked with SHA-256 before Lodge calls it done.")
                value("arrow.triangle.2.circlepath", tint: Color(hex: 0x8E8CFF), title: "Same every time",
                      text: "Every shooter, every card, every project — one consistent structure.")
            }
        }
    }

    private func value(_ symbol: String, tint: Color, title: String, text: String) -> some View {
        OnboardingCard(padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                cardTitle(title)
                Text(text).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - 03 Destination

struct OnboardingDestinationStep: View {
    @Environment(\.colorScheme) private var scheme
    @Binding var draft: OnboardingDraft
    let drives: [OnboardingDrive]

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            OnboardingCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        cardTitle("Destination")
                        Spacer()
                        OnboardingChip(text: "Required")
                    }
                    VStack(spacing: 6) {
                        ForEach(drives) { drive in driveRow(drive) }
                        if drives.isEmpty {
                            Text("No drives found. Choose a folder below.")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    Text("Folder").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 6)
                    HStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "folder.fill").foregroundStyle(.secondary)
                            Text(draft.destinationPath ?? "No folder chosen")
                                .font(.system(size: 12.5, design: .monospaced))
                                .foregroundStyle(draft.destinationPath == nil ? .secondary : .primary)
                                .lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(OnboardingPalette(scheme).well, in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(OnboardingPalette(scheme).wellStroke))
                        Button("Choose…", action: choose).controlSize(.large)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 12) {
                OnboardingCard {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: "star.fill").foregroundStyle(.yellow)
                            cardTitle("Saved as a favorite")
                            Spacer()
                        }
                        Text("This folder joins your favorite destinations (Settings ▸ Destinations), so you can switch to it in one click.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Toggle("Make it my default destination", isOn: $draft.makeDefaultDestination)
                            .toggleStyle(.checkbox).padding(.top, 4)
                    }
                }
                OnboardingCard {
                    VStack(alignment: .leading, spacing: 8) {
                        cardTitle("When copying finishes")
                        checkbox("Eject the card once verified", detail: "Only after every file’s checksum matches.",
                                 isOn: $draft.ejectAfterOffload)
                        checkbox("Play a sound", detail: "A short chime when the offload is done.",
                                 isOn: $draft.playSuccessSound)
                    }
                }
                Label("Low on space? Lodge checks before it copies a byte.", systemImage: "info.circle")
                    .font(.system(size: 12.5)).foregroundStyle(OnboardingPalette(scheme).helper)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func checkbox(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13))
                Text(detail).font(.system(size: 11.5)).foregroundStyle(OnboardingPalette(scheme).helper)
            }
        }
        .toggleStyle(.checkbox)
    }

    private func isSelected(_ drive: OnboardingDrive) -> Bool {
        guard let path = draft.destinationPath else { return false }
        return path == drive.suggestedPath || path.hasPrefix(drive.suggestedPath + "/")
            || (!drive.isInternal && path.hasPrefix(drive.suggestedPath))
    }

    private func driveRow(_ drive: OnboardingDrive) -> some View {
        let palette = OnboardingPalette(scheme)
        let selected = isSelected(drive)
        return Button {
            draft.destinationPath = drive.suggestedPath
        } label: {
            HStack(spacing: 12) {
                Image(systemName: drive.isInternal ? "internaldrive" : "externaldrive")
                    .font(.system(size: 14))
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .frame(width: 34, height: 34)
                    .background(palette.chip, in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(drive.name).font(.system(size: 13, weight: .semibold))
                        Text("· \(drive.kind)").font(.system(size: 12)).foregroundStyle(palette.helper)
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(scheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08))
                            Capsule().fill(selected ? Color.accentColor : (scheme == .dark ? Color.white.opacity(0.45) : Color.black.opacity(0.3)))
                                .frame(width: proxy.size.width * drive.usedFraction)
                        }
                    }
                    .frame(height: 5)
                    Text(drive.spaceText).font(.system(size: 11)).foregroundStyle(palette.helper)
                }
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(selected ? Color.accentColor : palette.tertiary)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(selected ? Color.accentColor.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Color.accentColor.opacity(0.55) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func choose() {
        let start = draft.destinationPath.map { URL(fileURLWithPath: $0) }
        if let url = AppSettings.pickFolder(startingAt: start) { draft.destinationPath = url.path }
    }
}

// MARK: - 04 Folder structure

struct OnboardingFoldersStep: View {
    @Environment(\.colorScheme) private var scheme
    @Binding var draft: OnboardingDraft
    @State private var selectedLevel: Int?

    private var levels: [String] { FolderTemplateEditor.levels(draft.folderTemplate) }

    var body: some View {
        let palette = OnboardingPalette(scheme)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ForEach(OnboardingStarter.allCases) { starter in starterButton(starter, palette: palette) }
            }
            HStack(alignment: .top, spacing: 14) {
                OnboardingCard(padding: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        row(depth: 0, symbol: "externaldrive", content: AnyView(
                            Text(rootName).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)),
                            chip: "Destination", selected: false)
                        ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                            levelRow(index: index, level: level)
                        }
                        row(depth: levels.count + 1, symbol: "folder.fill", content: AnyView(
                            Text("MP4 · MXF · WAV · ARW…").font(.system(size: 12, design: .monospaced)).foregroundStyle(palette.helper)),
                            chip: "Automatic", selected: false)
                        if levels.isEmpty {
                            Text("Flat: files go straight into the destination (one folder per type).")
                                .font(.system(size: 12)).foregroundStyle(palette.helper).padding(.leading, 12).padding(.top, 4)
                        }
                        Divider().padding(.top, 6)
                        HStack(spacing: 8) {
                            Menu {
                                ForEach(FolderTemplateEditor.levelTokens) { token in
                                    Button(token.placeholder) {
                                        draft.folderTemplate = FolderTemplateEditor.insert(token, into: draft.folderTemplate)
                                        selectedLevel = levels.count - 1
                                    }
                                }
                            } label: { Label("Folder", systemImage: "plus") }
                                .menuStyle(.button).fixedSize().controlSize(.small)
                            Button {
                                if let index = selectedLevel { remove(index) }
                            } label: { Label("Remove", systemImage: "minus") }
                                .controlSize(.small).disabled(selectedLevel == nil)
                            Spacer()
                            Text("Lodge adds one folder per file type inside the last level")
                                .font(.system(size: 11.5)).foregroundStyle(palette.helper)
                        }
                        .padding(.horizontal, 6).padding(.top, 4)
                    }
                }
                tokensPanel(palette)
                    .frame(width: 250)
            }
            if !draft.folderIssues.isEmpty {
                Label(draft.folderIssues.map(\.message).joined(separator: " "), systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12)).foregroundStyle(.orange)
            }
        }
    }

    private var rootName: String {
        draft.destinationPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Destination"
    }

    private func starterButton(_ starter: OnboardingStarter, palette: OnboardingPalette) -> some View {
        let selected = draft.starter == starter
        return Button {
            draft.choose(starter)
            selectedLevel = nil
        } label: {
            Label(starter.title, systemImage: starter.symbol)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(selected ? Color.accentColor.opacity(0.16) : (starter == .blank ? .clear : palette.chip),
                            in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(selected ? Color.accentColor.opacity(0.7) : (starter == .blank ? palette.tertiary.opacity(0.6) : palette.stroke)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func levelRow(index: Int, level: String) -> some View {
        HStack(spacing: 0) {
            row(depth: index + 1, symbol: "folder.fill", content: AnyView(TemplatePills(text: level)),
                chip: nil, selected: selectedLevel == index)
        }
        .contentShape(Rectangle())
        .onTapGesture { selectedLevel = selectedLevel == index ? nil : index }
        .contextMenu {
            Button("Move Up") { move(index, by: -1) }.disabled(index == 0)
            Button("Move Down") { move(index, by: 1) }.disabled(index == levels.count - 1)
            Button("Remove") { remove(index) }
        }
        .overlay(alignment: .trailing) {
            if selectedLevel == index {
                HStack(spacing: 2) {
                    Button { move(index, by: -1) } label: { Image(systemName: "chevron.up") }.disabled(index == 0)
                    Button { move(index, by: 1) } label: { Image(systemName: "chevron.down") }.disabled(index == levels.count - 1)
                }
                .buttonStyle(.borderless).padding(.trailing, 10)
            }
        }
    }

    private func row(depth: Int, symbol: String, content: AnyView, chip: String?, selected: Bool) -> some View {
        let palette = OnboardingPalette(scheme)
        return HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(symbol == "folder.fill" ? folderBlue(scheme) : palette.helper)
            content
            Spacer()
            if let chip { OnboardingChip(text: chip) }
        }
        .padding(.leading, 10 + CGFloat(depth) * 18)
        .padding(.trailing, 8)
        .frame(height: 36)
        .background(selected ? palette.rowSelected : .clear, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(selected ? Color.accentColor.opacity(0.6) : .clear))
    }

    private func tokensPanel(_ palette: OnboardingPalette) -> some View {
        OnboardingCard {
            VStack(alignment: .leading, spacing: 7) {
                (Text("Tokens").font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary)
                 + Text(" · click to add a level").font(.system(size: 12)).foregroundColor(palette.helper))
                ForEach(FolderTemplateEditor.levelTokens) { token in
                    Button {
                        draft.folderTemplate = FolderTemplateEditor.insert(token, into: draft.folderTemplate,
                                                                            at: selectedLevel.map { $0 + 1 })
                        selectedLevel = (selectedLevel.map { $0 + 1 }) ?? levels.count - 1
                    } label: {
                        HStack {
                            TokenPill(label: token.placeholder, token: token)
                            Spacer()
                            Text(Self.example(token)).font(.system(size: 11.5)).foregroundStyle(palette.helper)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Text("Dates are written YYYY-MM-DD, from each file’s capture date.")
                    .font(.system(size: 11.5)).foregroundStyle(palette.helper)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 4)
            }
        }
    }

    static func example(_ token: TemplateToken) -> String {
        switch token {
        case .project: "Typed in Lodge"
        case .camera: "Chosen in Lodge"
        case .date: "2026-10-26"
        case .year: "2026"
        case .month: "10"
        case .day: "26"
        case .type: "Video · Audio…"
        case .card: "Volume name"
        case .time: "091400"
        case .original: "Camera’s name"
        case .seq: "0001"
        case .ext: "mxf"
        }
    }

    private func move(_ index: Int, by offset: Int) {
        draft.folderTemplate = FolderTemplateEditor.move(draft.folderTemplate, from: index, to: index + offset)
        selectedLevel = max(0, min(index + offset, levels.count - 1))
    }

    private func remove(_ index: Int) {
        draft.folderTemplate = FolderTemplateEditor.remove(draft.folderTemplate, at: index)
        selectedLevel = nil
    }
}

// MARK: - 05 Naming & safety

struct OnboardingNamingStep: View {
    @Environment(\.colorScheme) private var scheme
    @Binding var draft: OnboardingDraft
    @FocusState private var patternFocused: Bool

    private static let quickAdd: [TemplateToken] = [.date, .project, .camera, .card, .original, .time, .seq]

    var body: some View {
        let palette = OnboardingPalette(scheme)
        HStack(alignment: .top, spacing: 16) {
            OnboardingCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        cardTitle("Rename files")
                        Spacer()
                        Toggle("Rename files", isOn: $draft.renameFiles).toggleStyle(.switch).labelsHidden().controlSize(.small)
                    }
                    if draft.renameFiles {
                        HStack(spacing: 8) {
                            TextField("Pattern", text: $draft.fileTemplate)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13, design: .monospaced))
                                .focused($patternFocused)
                            Text(".{ext}").font(.system(size: 13, design: .monospaced)).foregroundStyle(palette.helper)
                        }
                        .padding(.horizontal, 10)
                        .frame(minHeight: 40)
                        .background(palette.well, in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(palette.wellStroke))
                        HStack(spacing: 6) {
                            TemplatePills(text: draft.fileTemplate, size: 11.5)
                        }
                        FlowLayout(spacing: 6) {
                            Text("Quick add:").font(.system(size: 12)).foregroundStyle(palette.helper)
                            ForEach(Self.quickAdd) { token in
                                Button { draft.fileTemplate += (draft.fileTemplate.isEmpty || draft.fileTemplate.hasSuffix("_") ? "" : "_") + token.placeholder } label: {
                                    TokenPill(label: token.placeholder, token: token, size: 11.5).fixedSize()
                                }
                                .buttonStyle(.plain)
                                .help("Add \(token.placeholder): \(token.summary)")
                            }
                        }
                    } else {
                        Text("Files keep the names the camera gave them ({original}).")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    livePreview(palette)
                    if !draft.fileIssues.isEmpty {
                        Label(draft.fileIssues.map(\.message).joined(separator: " "), systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12)).foregroundStyle(.orange)
                    }
                    Label("Sidecars (.XML, .XMP, .THM…) are kept with their clip and follow its new name.", systemImage: "paperclip")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 511)

            VStack(spacing: 12) {
                OnboardingCard {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.shield").foregroundStyle(palette.green)
                            cardTitle("Every copy is verified")
                            Spacer()
                            OnboardingChip(text: "Always on", green: true)
                        }
                        Text("Lodge reads each file back from the destination and compares SHA-256 checksums before it calls the offload done.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                OnboardingCard {
                    VStack(alignment: .leading, spacing: 8) {
                        cardTitle("Files Lodge already has")
                        statement("arrow.uturn.right", "Files already offloaded are skipped",
                                  "Lodge remembers every verified copy, so plugging a card in again only copies what’s new.")
                        statement("lock", "Nothing is ever overwritten",
                                  "If a name is taken, Lodge uses the next number (or adds _2).")
                        Divider().padding(.vertical, 2)
                        HStack {
                            Toggle("Skip clips shorter than", isOn: $draft.skipShortClips).toggleStyle(.checkbox)
                            Stepper(value: $draft.shortClipSeconds, in: 1...60) {
                                Text("\(draft.shortClipSeconds) s").font(.system(size: 13, design: .monospaced))
                            }
                            .disabled(!draft.skipShortClips)
                        }
                        Text("Accidental record-button taps stay on the card.")
                            .font(.system(size: 11.5)).foregroundStyle(palette.helper).padding(.leading, 20)
                    }
                }
            }
            .frame(width: 409)
        }
    }

    private func statement(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13))
                Text(detail).font(.system(size: 11.5)).foregroundStyle(OnboardingPalette(scheme).helper)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func livePreview(_ palette: OnboardingPalette) -> some View {
        let plan = OnboardingSamples.plan(draft).filter { $0.sidecarOf == nil }.prefix(4)
        return VStack(alignment: .leading, spacing: 6) {
            Label("Live preview", systemImage: "eye").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            ForEach(Array(plan)) { file in
                HStack(spacing: 10) {
                    Text(file.originalName).strikethrough().foregroundStyle(palette.helper)
                        .frame(width: 175, alignment: .leading)
                    Image(systemName: "arrow.right").foregroundStyle(palette.helper)
                    Text(file.fileName).foregroundStyle(.primary)
                }
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.well, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(palette.stroke))
    }
}

// MARK: - 06 Review & save

struct OnboardingReviewStep: View {
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var store: OnboardingStore

    var body: some View {
        let palette = OnboardingPalette(scheme)
        let draft = store.draft
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Preset name").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Image(systemName: draft.starter.symbol).foregroundStyle(.secondary)
                    TextField("Preset name", text: Binding(
                        get: { store.draft.presetName },
                        set: { store.draft.presetName = $0; store.draft.nameEdited = true }))
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 10).frame(height: 30)
                .background(palette.well, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(palette.wellStroke))

                OnboardingCard(padding: 0) {
                    VStack(spacing: 0) {
                        summary("externaldrive", "Destination", destinationText, edit: .destination)
                        Divider()
                        summary("square.3.layers.3d", "Folders", folderText, edit: .folders, mono: true)
                        Divider()
                        summary("doc", "File names", draft.effectiveFileTemplate, edit: .naming, mono: true)
                        Divider()
                        summary("checkmark.shield", "Safety", safetyText, edit: .naming, green: true)
                        Divider()
                        summary("eject", "After copying", afterText, edit: .destination)
                    }
                }
                Toggle("Switch to this preset now", isOn: $store.draft.useNow).toggleStyle(.checkbox)
                    .font(.system(size: 13))
            }
            .frame(width: 330)

            OnboardingCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Live preview", systemImage: "eye").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Text("Sample:").font(.system(size: 11.5)).foregroundStyle(palette.helper)
                        TokenPill(label: "Northwind", token: .project, size: 11)
                        TokenPill(label: "FX6", token: .camera, size: 11)
                        TokenPill(label: "A001", token: .card, size: 11)
                    }
                    PreviewTreeView(rows: PreviewTree.rows(root: rootText, plan: OnboardingSamples.plan(draft), filesPerFolder: 2))
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.shield")
                        Text("Every file SHA-256 verified after copying")
                    }
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(palette.greenText)
                    .padding(.top, 2)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private var rootText: String {
        guard let path = store.draft.destinationPath else { return "Destination" }
        let parts = path.split(separator: "/").suffix(2)
        return parts.joined(separator: " / ")
    }

    private var destinationText: String {
        guard let path = store.draft.destinationPath else { return "Not chosen" }
        let parts = path.split(separator: "/")
        if parts.first == "Volumes", parts.count >= 2 { return parts.dropFirst().joined(separator: " › ") }
        return (path as NSString).abbreviatingWithTildeInPath
    }

    private var folderText: String {
        let draft = store.draft
        return draft.folderTemplate.isEmpty ? "\(draft.starter.title) · flat" : draft.folderTemplate
    }

    private var safetyText: String {
        let draft = store.draft
        let skip = draft.skipShortClips ? " · skip < \(draft.shortClipSeconds) s" : ""
        return "SHA-256 · no overwrites\(skip)"
    }

    private var afterText: String {
        let draft = store.draft
        var parts: [String] = []
        parts.append(draft.ejectAfterOffload ? "Eject card" : "Keep card mounted")
        if draft.playSuccessSound { parts.append("play sound") }
        return parts.joined(separator: " · ")
    }

    private func summary(_ symbol: String, _ key: String, _ value: String, edit: OnboardingStep,
                         mono: Bool = false, green: Bool = false) -> some View {
        let palette = OnboardingPalette(scheme)
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(green ? palette.green : Color.secondary).frame(width: 18).padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(key).font(.system(size: 11)).foregroundStyle(palette.helper)
                Text(value)
                    .font(mono ? .system(size: 12, design: .monospaced) : .system(size: 13, weight: .medium))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Edit") { store.go(to: edit) }
                .buttonStyle(.link).font(.system(size: 12, weight: .medium))
        }
        .padding(10)
    }
}
