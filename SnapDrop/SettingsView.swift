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
    case general, naming, cameras
    static let storageKey = "settingsTab"
}

/// Destination and what happens after an offload.
struct GeneralSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var watcher: VolumeWatcher

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
                            settings.chooseDestination()
                            watcher.refresh()
                        }
                    }
                }
                Text("Folder and file names are set in the Naming tab.")
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
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
    }
}

#if DEBUG
#Preview("Settings") {
    SettingsView().demoEnvironment(DemoData.model(state: .ready))
}
#endif
