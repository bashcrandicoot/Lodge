import SwiftUI
import AppKit

/// The entry point of the app. `@main` tells Swift to start here.
@main
struct SnapDropApp: App {
    /// Lets us hook into a few classic AppKit app events (see `AppDelegate` below).
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// The one shared "brain" of the app. `@StateObject` keeps it alive for the app's lifetime.
    @StateObject private var model = SnapDropApp.makeModel()

    var body: some Scene {
        // A single main window (not a document-style app with many windows).
        Window("SnapDrop", id: "main") {
            ContentView()
                .appEnvironment(model)
                .frame(minWidth: 940, minHeight: 580)
        }
        .defaultSize(width: 1080, height: 660)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)

        // SnapDrop ▸ Settings… (⌘,)
        Settings {
            SettingsView()
                .appEnvironment(model)
        }
    }

    private static func makeModel() -> AppModel {
        #if DEBUG
        // `-SnapDropDemo YES -SnapDropDemoState ready` shows sample data (used for screenshots).
        if let state = DemoData.launchState {
            return DemoData.model(state: state)
        }
        #endif
        // As the unit tests' host, never read or write the user's settings, ledger or lists.
        if AppModel.isRunningUnitTests {
            let ledger = FileManager.default.temporaryDirectory.appendingPathComponent("snapdrop-test-host-ledger.json")
            return AppModel(settings: AppSettings(defaults: nil), ledger: Ledger(fileURL: ledger),
                            cameras: CameraStore(fileURL: nil), destinations: DestinationStore(fileURL: nil),
                            startWatching: false)
        }
        return AppModel()
    }
}

/// Classic AppKit delegate. We only use it to quit the app when its window is closed,
/// so it never sits invisibly in the background.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "SnapDropDemoAppearance") {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
        #endif
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
