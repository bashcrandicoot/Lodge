import SwiftUI
import AppKit

/// The entry point of the app. `@main` tells Swift to start here.
@main
enum LodgeLauncher {
    static func main() {
        // The unit tests run inside the app, which then gets no windows or menu bar icon at all
        // (with no Dock icon allowed, SwiftUI keeps redrawing a menu bar scene until it crashes).
        if AppModel.isRunningUnitTests {
            LodgeTestHost.main()
        } else {
            LodgeApp.main()
        }
    }
}

/// What runs as the unit tests' host: nothing visible.
struct LodgeTestHost: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

struct LodgeApp: App {
    /// Lets us hook into a few classic AppKit app events (see `AppDelegate` below).
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// The one shared "brain" of the app. `@StateObject` keeps it alive for the app's lifetime.
    @StateObject private var model = LodgeApp.makeModel()

    init() {
        // Create (and start) Sparkle at launch, as its docs recommend.
        _ = AppUpdates.controller
    }

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
        .commands {
            // Lodge ▸ About Lodge (with the support link), then Check for Updates…
            CommandGroup(replacing: .appInfo) {
                Button("About Lodge") { Support.showAboutPanel() }
                CheckForUpdatesView(updater: AppUpdates.updater)
                Button("Support Lodge…") { Support.openTipJar() }
            }
            // Help ▸ Contact Support… and Support Lodge…
            // .help placement is empty without a Help Book, so items "after" it never show; replace it instead.
            CommandGroup(replacing: .help) {
                Button("Contact Support…") { Support.contactSupport() }
                Button("Support Lodge…") { Support.openTipJar() }
            }
        }

        // Lodge ▸ Settings… (⌘,)
        Settings {
            SettingsView(updater: AppUpdates.updater)
                .appEnvironment(model)
        }
    }

    private static func makeModel() -> AppModel {
        #if DEBUG
        // `-LodgeDemo YES -LodgeDemoState ready` shows sample data (used for screenshots).
        if let state = DemoData.launchState {
            let model = DemoData.model(state: state)
            AppDelegate.model = model
            StatusItemController.start(for: model)
            return model
        }
        #endif
        // Lodge used to be SnapDrop: copy its data and settings over once (never moved).
        LegacyMigration.runIfNeeded()
        let model = AppModel()
        // Early, so a click on a notification that launched Lodge still gets handled.
        model.importPrompter.registerWithNotificationCenter()
        AppDelegate.model = model
        StatusItemController.start(for: model)
        return model
    }
}

/// Classic AppKit delegate: quitting when the window closes (unless Lodge stays in the menu bar),
/// reopening the window from Finder / the Dock, and the Dock icon in menu bar mode.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The app's model, for the few AppKit events below that need the settings.
    @MainActor static weak var model: AppModel?
    private var windowObservers: [NSObjectProtocol] = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        // As the unit tests' host, stay out of the way: no Dock icon, no windows, never frontmost.
        if AppModel.isRunningUnitTests {
            NSApp.setActivationPolicy(.prohibited)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !AppModel.isRunningUnitTests {
            observeMainWindow()
            // Opened at login in menu bar mode: stay in the menu bar, no window.
            if Self.launchedAsLoginItem, Self.model?.settings.keepRunningInMenuBar == true {
                DispatchQueue.main.async {
                    MainWindow.window?.close()
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
        #if DEBUG
        if DemoData.launchState != nil { DemoData.drawWindowsAsActive() }
        // Screenshots: `-LodgeDemoAbout YES` opens the About window.
        if DemoData.launchState != nil, UserDefaults.standard.bool(forKey: "LodgeDemoAbout") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { Support.showAboutPanel() }
        }
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
        // In menu bar mode Lodge keeps running to watch for cards.
        !(Self.model?.settings.keepRunningInMenuBar ?? false)
    }

    /// Opening Lodge again (Finder, the Dock, Spotlight) while it runs without a window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !MainWindow.isOpen else { return true }
        guard MainWindow.openAction != nil else { return true }   // let SwiftUI reopen it
        MainWindow.show()
        return false
    }

    /// In menu bar mode, Lodge leaves the Dock and the ⌘-Tab list while its window is closed,
    /// and comes back as soon as the window opens again.
    private func observeMainWindow() {
        let center = NotificationCenter.default
        windowObservers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: nil,
                                                  queue: .main) { note in
            guard (note.object as? NSWindow)?.identifier?.rawValue.hasPrefix("main") == true else { return }
            DispatchQueue.main.async {
                guard Self.model?.settings.keepRunningInMenuBar == true, !MainWindow.isOpen,
                      NSApp.activationPolicy() == .regular else { return }
                NSApp.setActivationPolicy(.accessory)
            }
        })
        windowObservers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil,
                                                  queue: .main) { note in
            guard (note.object as? NSWindow)?.identifier?.rawValue.hasPrefix("main") == true,
                  NSApp.activationPolicy() != .regular else { return }
            NSApp.setActivationPolicy(.regular)
        })
    }

    /// True when macOS opened Lodge at login (Open at login).
    private static var launchedAsLoginItem: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == kAEOpenApplication else { return false }
        return event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
}
