import Foundation
import AppKit

/// User preferences: the destination folder and whether to eject cards when done.
///
/// Stored in `UserDefaults` (a small built-in key/value store). A plain folder path is
/// fine because SnapDrop is not sandboxed.
@MainActor
final class AppSettings: ObservableObject {
    private static let destinationKey = "destinationPath"
    private static let ejectKey = "ejectAfterOffload"

    /// Where settings are saved. `nil` = don't save (used for previews and demo mode).
    private let defaults: UserDefaults?

    /// Absolute path of the folder clips are offloaded into, or `nil` if not chosen yet.
    @Published var destinationPath: String? {
        didSet { defaults?.set(destinationPath, forKey: Self.destinationKey) }
    }

    /// Eject the card automatically after an offload where every clip verified. Off by default.
    @Published var ejectAfterOffload: Bool {
        didSet { defaults?.set(ejectAfterOffload, forKey: Self.ejectKey) }
    }

    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        destinationPath = defaults?.string(forKey: Self.destinationKey)
        ejectAfterOffload = defaults?.bool(forKey: Self.ejectKey) ?? false
    }

    /// The destination as a URL (handier for file operations).
    var destinationURL: URL? {
        destinationPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// Shows the standard macOS "choose a folder" panel.
    func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose the folder SnapDrop should copy your clips into."
        if let current = destinationURL {
            panel.directoryURL = current
        }
        if panel.runModal() == .OK, let url = panel.url {
            destinationPath = url.path
        }
    }
}
