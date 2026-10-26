import SwiftUI
import AppKit
import Sparkle

/// The Settings window (Lodge ▸ Settings…, or ⌘,).
struct SettingsView: View {
    /// Sparkle's updater, for the Updates toggles in General (nil hides them).
    var updater: SPUUpdater?

    /// Which tab is showing. Stored so "Edit Cameras…" can open straight to Cameras.
    @AppStorage(SettingsTab.storageKey) private var tab: SettingsTab = .general

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettingsView(updater: updater)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            AppearanceSettingsView()
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
                .tag(SettingsTab.appearance)
            PresetsSettingsView()
                .tabItem { Label("Presets", systemImage: "square.stack.3d.up") }
                .tag(SettingsTab.presets)
            DestinationsSettingsView()
                .tabItem { Label("Destinations", systemImage: "externaldrive") }
                .tag(SettingsTab.destinations)
            NamingSettingsView()
                .tabItem { Label("Naming", systemImage: "textformat") }
                .tag(SettingsTab.naming)
            FilesSettingsView()
                .tabItem { Label("Files", systemImage: "doc.on.doc") }
                .tag(SettingsTab.files)
            CamerasSettingsView()
                .tabItem { Label("Cameras", systemImage: "camera") }
                .tag(SettingsTab.cameras)
        }
    }
}

enum SettingsTab: String {
    case general, appearance, presets, destinations, naming, files, cameras
    static let storageKey = "settingsTab"
}

/// What gets offloaded and what happens after. (Where files go is the default favorite in
/// the Destinations tab: the main window's destination picker is the one place to change it.)
struct GeneralSettingsView: View {
    var updater: SPUUpdater?
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
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
                Text("Sidecars (like C0001M01.XML) and proxies (like GoPro .LRV) get their clip’s name and their own folders when Other is on. Change the lists and the ignore list in the Files tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section {
                LabeledContent("Skip videos shorter than") {
                    ShortClipSlider(seconds: $settings.shortClipSliderSeconds)
                        .frame(width: 290)
                }
            } header: {
                Text("Short Clips")
            } footer: {
                Text("Off keeps every clip. Accidental takes stay on the card, with their sidecars and proxies. Include them from the Media list any time. Clips whose length can’t be read (like BRAW or R3D) are always offloaded.")
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
            MenuBarSettingsSection(loginItem: model.loginItem)
            if let updater {
                UpdateSettingsSection(updater: updater)
            }
            Section {
            } footer: {
                SettingsCreditsFooter()
            }
        }
        .formStyle(.grouped)
        .themeControlTint()
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Settings ▸ General ▸ Menu Bar: keep running, ask to import, the icon, open at login,
/// and the cards Lodge doesn't ask about.
struct MenuBarSettingsSection: View {
    @ObservedObject var loginItem: LoginItem
    @EnvironmentObject private var settings: AppSettings

    static let promptStyleHint = "While a Focus such as Do Not Disturb is on, macOS keeps notifications in Notification Center without showing them. The floating panel always shows. To get notifications during a Focus, allow Lodge in System Settings ▸ Focus."

    static let hiddenIconHint = "With the icon hidden, Lodge keeps running in the background and still asks to import. Open Lodge from Finder, the Dock or Spotlight to show its window, and quit it from there with ⌘Q."

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Keep Lodge running in the menu bar", isOn: $settings.keepRunningInMenuBar)
                Text("Closing the window leaves Lodge running, so it can notice cards and drives as they’re plugged in.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Ask to import when a card or drive is plugged in", isOn: $settings.askToImport)
                Text("Whenever Lodge is running. Only for cards and drives with camera folders or media; Lodge never starts an offload on its own.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Picker("Ask with", selection: $settings.importPromptStyle) {
                    ForEach(ImportPromptStyle.allCases) { Text($0.title).tag($0) }
                }
                Text(Self.promptStyleHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .disabled(!settings.askToImport)
            Toggle(isOn: $settings.showMenuBarIcon) {
                HStack(spacing: 4) {
                    Text("Show menu bar icon")
                    InfoHint(text: Self.hiddenIconHint, subject: "Show menu bar icon")
                }
            }
            .disabled(!settings.keepRunningInMenuBar)
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Open at login", isOn: Binding(get: { loginItem.isOn }, set: { loginItem.set($0) }))
                    .disabled(!settings.keepRunningInMenuBar)
                if loginItem.needsApproval {
                    HStack(spacing: 6) {
                        Text("Allow Lodge in System Settings ▸ General ▸ Login Items.")
                        Button("Open Login Items…") { loginItem.openLoginItemsSettings() }
                            .buttonStyle(.link)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else if let error = loginItem.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !settings.ignoredImportCards.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Don’t ask for these cards")
                    ForEach(settings.ignoredImportCards) { card in
                        HStack {
                            Label(card.name, systemImage: "sdcard")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Ask Again") { settings.stopIgnoringImports(card.identity) }
                                .controlSize(.small)
                                .accessibilityLabel("Ask again for \(card.name)")
                        }
                    }
                }
            }
        } header: {
            Text("Menu Bar")
        }
        .onAppear { loginItem.refresh() }
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
                     ? "Increase Contrast or Reduce Transparency is on, so Lodge uses solid colours from the theme instead of gradients."
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
    SettingsView(updater: AppUpdates.updater).demoEnvironment(DemoData.model(state: .ready))
}
#endif
