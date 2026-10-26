import SwiftUI
import AppKit

/// The entry point of the app. `@main` tells Swift to start here.
@main
struct LodgeApp: App {
    /// Lets us hook into a few classic AppKit app events (see `AppDelegate` below).
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// The one shared "brain" of the app. `@StateObject` keeps it alive for the app's lifetime.
    @StateObject private var model = LodgeApp.makeModel()

    var body: some Scene {
        // A single main window (not a document-style app with many windows).
        Window("Lodge", id: "main") {
            ContentView()
                .appEnvironment(model)
                .frame(minWidth: 940, minHeight: 580)
        }
        .defaultSize(width: 1080, height: 660)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)

        // Lodge ▸ Settings… (⌘,)
        Settings {
            SettingsView()
                .appEnvironment(model)
        }
    }

    private static func makeModel() -> AppModel {
        #if DEBUG
        // `-LodgeDemo YES -LodgeDemoState ready` shows sample data (used for screenshots).
        if let state = DemoData.launchState {
            return DemoData.model(state: state)
        }
        #endif
        // As the unit tests' host, never read or write the user's settings, ledger or lists.
        if AppModel.isRunningUnitTests {
            let ledger = FileManager.default.temporaryDirectory.appendingPathComponent("lodge-test-host-ledger.json")
            return AppModel(settings: AppSettings(defaults: nil), ledger: Ledger(fileURL: ledger),
                            cameras: CameraStore(fileURL: nil), destinations: DestinationStore(fileURL: nil),
                            presets: PresetStore(fileURL: nil), startWatching: false)
        }
        // Lodge used to be SnapDrop: copy its data and settings over once (never moved).
        LegacyMigration.runIfNeeded()
        return AppModel()
    }
}

/// Classic AppKit delegate. We only use it to quit the app when its window is closed,
/// so it never sits invisibly in the background.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // As the unit tests' host, stay out of the way: no Dock icon, no windows, never frontmost.
        if AppModel.isRunningUnitTests {
            NSApp.setActivationPolicy(.prohibited)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if DemoData.launchState != nil { DemoData.drawWindowsAsActive() }
        switch UserDefaults.standard.string(forKey: "LodgeDemoAppearance") {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
        // Screenshots: `-LodgeDemoWindowSize 1240x800` resizes the main window and centres it
        // on a Retina screen when there is one, so every screenshot is captured at 2x.
        if let size = UserDefaults.standard.string(forKey: "LodgeDemoWindowSize")?.split(separator: "x"),
           size.count == 2, let width = Double(size[0]), let height = Double(size[1]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard let window = NSApp.windows.first(where: { $0.title == "Lodge" }) else { return }
                window.setContentSize(NSSize(width: width, height: height))
                DemoData.centreOnSharpestScreen(window)
            }
        }
        #endif
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
