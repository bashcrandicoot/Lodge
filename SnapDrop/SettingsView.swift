import SwiftUI
import AppKit

/// The Settings window (SnapDrop ▸ Settings…, or ⌘,).
struct SettingsView: View {
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
                Text("Clips are saved as YYYY-MM-DD/ShootName/YYYY-MM-DD_ShootName_0001.mp4")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("After Offload") {
                Toggle("Eject card after offload", isOn: $settings.ejectAfterOffload)
                Text("Only happens when every clip was copied and verified.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
    }
}

#if DEBUG
#Preview("Settings") {
    SettingsView().demoEnvironment(DemoData.model(state: .ready))
}
#endif
