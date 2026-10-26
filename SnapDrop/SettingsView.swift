import SwiftUI
import AppKit

/// The Settings window (SnapDrop ▸ Settings…, or ⌘,).
struct SettingsView: View {
    /// Which tab is showing. Stored so "Edit Cameras…" can open straight to Cameras.
    @AppStorage(SettingsTab.storageKey) private var tab: SettingsTab = .general

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            AppearanceSettingsView()
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
                .tag(SettingsTab.appearance)
            DestinationsSettingsView()
                .tabItem { Label("Destinations", systemImage: "externaldrive") }
                .tag(SettingsTab.destinations)
            NamingSettingsView()
                .tabItem { Label("Naming", systemImage: "textformat") }
                .tag(SettingsTab.naming)
            CamerasSettingsView()
                .tabItem { Label("Cameras", systemImage: "camera") }
                .tag(SettingsTab.cameras)
        }
    }
}

enum SettingsTab: String {
    case general, appearance, destinations, naming, cameras
    static let storageKey = "settingsTab"
}

/// Destination and what happens after an offload.
struct GeneralSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Destination") {
                LabeledContent("Folder") {
                    HStack {
                        Text(settings.destinationPath.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "Not chosen")
                            .foregroundStyle(settings.destinationPath == nil ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Choose…") {
                            model.chooseOtherDestination()
                        }
                        .disabled(model.isBusy)
                    }
                }
                Text("Save the folders you use often in the Destinations tab. Folder and file names are set in the Naming tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                ForEach(MediaCategory.allCases) { category in
                    Toggle(isOn: Binding(
                        get: { settings.includedCategories.contains(category) },
                        set: { settings.setCategory(category, included: $0) })) {
                        Label(category.settingsTitle, systemImage: category.symbol)
                    }
                }
            } header: {
                Text("Files to Offload")
            } footer: {
                Text("Sidecar files (like C0001M01.XML) get the same name as their clip when Other is on. System files such as .Spotlight-V100 and ._ files are never copied.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section {
                Toggle("Skip short videos", isOn: $settings.skipShortClips)
                Stepper(value: $settings.shortClipSeconds, in: ShortClipRule.thresholdRange) {
                    LabeledContent("Shorter than") {
                        Text(DurationFormatting.threshold(Double(settings.shortClipSeconds)))
                            .monospacedDigit()
                    }
                }
                .disabled(!settings.skipShortClips)
            } header: {
                Text("Short Clips")
            } footer: {
                Text("Accidental takes stay on the card, with their sidecar files. Include them from the Media list any time. Clips whose length can’t be read (like BRAW or R3D) are always offloaded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("After Offload") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Eject card after offload", isOn: $settings.ejectAfterOffload)
                    Text("Only when every file was copied and verified.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Play a sound when an offload finishes", isOn: $settings.playSuccessSound)
            }
        }
        .formStyle(.grouped)
        .themeControlTint()
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Theme swatches and Light / Dark / System.
struct AppearanceSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.theme) private var theme

    var body: some View {
        Form {
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 70, maximum: 90), spacing: 12)], spacing: 12) {
                    ForEach(ThemePalette.all) { palette in
                        Button {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.45)) {
                                settings.themeID = palette.id
                            }
                        } label: {
                            ThemeSwatch(palette: palette, isSelected: settings.themeID == palette.id)
                        }
                        .buttonStyle(.plain)
                        .help(palette.name)
                    }
                }
                .padding(.vertical, 4)
                HStack {
                    Text("Preview")
                        .foregroundStyle(.secondary)
                    Spacer()
                    ShimmerProgressBar(fraction: 0.62)
                        .frame(width: 140)
                    Button {} label: { Label("Offload 12 Files", systemImage: "arrow.down.circle.fill") }
                        .buttonStyle(.themeProminent)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            } header: {
                Text("Theme")
            } footer: {
                Text(theme.isPlain
                     ? "Increase Contrast or Reduce Transparency is on, so SnapDrop uses solid colours from the theme instead of gradients."
                     : "Default is neutral black and white. The colour themes tint the buttons, progress, highlights and the window’s background.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Appearance") {
                Picker("Appearance", selection: $settings.appearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
            }
            Section {
                Picker("Show files as", selection: $settings.mediaLayout) {
                    ForEach(MediaLayout.allCases) { layout in
                        Label(layout.title, systemImage: layout.symbol).tag(layout)
                    }
                }
                Toggle("Show thumbnails in the list", isOn: $settings.showListThumbnails)
                    .disabled(settings.mediaLayout == .grid)
            } header: {
                Text("Media")
            } footer: {
                Text("Select files and press Space to preview them with Quick Look. Thumbnails are only read from the card, never written to it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .themeControlTint()
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
    }
}

#if DEBUG
#Preview("Settings") {
    SettingsView().demoEnvironment(DemoData.model(state: .ready))
}
#endif
