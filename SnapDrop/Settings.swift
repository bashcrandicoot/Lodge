import Foundation
import AppKit

/// User preferences. Right now that's just the destination folder.
///
/// The folder path is stored in `UserDefaults` (a small built-in key/value store).
/// That's fine because SnapDrop is not sandboxed, so a plain path keeps working.
@MainActor
final class AppSettings: ObservableObject {
    private static let destinationKey = "destinationPath"

    /// Absolute path of the folder clips are offloaded into, or `nil` if not chosen yet.
    @Published var destinationPath: String? {
        didSet { UserDefaults.standard.set(destinationPath, forKey: Self.destinationKey) }
    }

    init() {
        destinationPath = UserDefaults.standard.string(forKey: Self.destinationKey)
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
