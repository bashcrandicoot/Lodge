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
            Section("After Offload") {
                Toggle("Eject card after offload", isOn: $settings.ejectAfterOffload)
                Text("Only happens when every file was copied and verified.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
