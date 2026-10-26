import SwiftUI
import AppKit

/// The entry point of the app. `@main` tells Swift to start here.
@main
struct SnapDropApp: App {
    /// Lets us hook into a few classic AppKit app events (see `AppDelegate` below).
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// The one shared "brain" of the app. `@StateObject` keeps it alive for the app's lifetime.
    @StateObject private var model = AppModel()

    var body: some Scene {
        // A single main window (not a document-style app with many windows).
        Window("SnapDrop", id: "main") {
            ContentView()
                .environmentObject(model)
                .environmentObject(model.settings)
                .environmentObject(model.watcher)
                .environmentObject(model.ledger)
                .frame(minWidth: 640, minHeight: 520)
        }
        .windowResizability(.contentMinSize)
    }
}

/// Classic AppKit delegate. We only use it to quit the app when its window is closed,
/// so it never sits invisibly in the background.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
