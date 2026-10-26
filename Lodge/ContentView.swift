import SwiftUI
import AppKit

/// The main window: a left-to-right funnel (Card → Clips → Destination)
/// with the offload bar along the bottom.
struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    #if DEBUG
    @Environment(\.openSettings) private var openSettings
    #endif

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                CardStageView()
                    .frame(width: 230)
                FunnelArrow(lit: model.session != nil, flowing: model.isBusy)
                ClipsStageView()
                    .frame(minWidth: 0, maxWidth: .infinity)
                FunnelArrow(lit: model.session != nil && settings.destinationURL != nil, flowing: model.isBusy)
                DestinationStageView()
                    .frame(width: 270)
            }
            .padding(20)
            .frame(maxHeight: .infinity)

            Divider()

            OffloadBar()
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.bar)
        }
        .background(ThemeBackground())
        .toolbar {
            // With the title hidden the toolbar has nothing on the left, so a flexible space
            // keeps Recent Offloads and Settings on the trailing side, away from the traffic lights.
            ToolbarItem(placement: .automatic) {
                Spacer()
            }
            // Presets: one click changes where files go and how they're named. Kept at the
            // right, out of the way, just before Recent Offloads and Settings.
            ToolbarItem(placement: .automatic) {
                PresetSwitcher()
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    model.showingRecent.toggle()
                } label: {
                    Label("Recent Offloads", systemImage: "clock.arrow.circlepath")
                }
                .help("Recent Offloads")
                .popover(isPresented: $model.showingRecent, arrowEdge: .bottom) {
                    RecentOffloadsView()
                }
            }
            ToolbarItem(placement: .automatic) {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Settings (⌘,)")
            }
        }
        // The window is still called "Lodge" (Window menu, Mission Control, VoiceOver), but the
        // title bar only shows the traffic lights and the toolbar buttons. The card's name is
        // in the Card pane.
        .navigationTitle("Lodge")
        .background(HiddenWindowTitle())
        #if DEBUG
        .task {
            // Screenshots: `-LodgeDemoSettingsTab naming` opens Settings on that tab.
            if DemoData.launchState != nil, let tab = DemoData.launchSettingsTab {
                UserDefaults.standard.set(tab.rawValue, forKey: SettingsTab.storageKey)
                try? await Task.sleep(for: .milliseconds(600))
                openSettings()
                if UserDefaults.standard.string(forKey: "LodgeDemoWindowSize") != nil {
                    try? await Task.sleep(for: .milliseconds(500))
                    if let window = NSApp.windows.first(where: { $0.isVisible && $0.title != "Lodge" && $0.frame.width > 300 }) {
                        DemoData.centreOnSharpestScreen(window)
                    }
                }
            }
            // Screenshots: `-LodgeDemoShowFormatAlert YES` opens the Format confirmation.
            if DemoData.launchState != nil, UserDefaults.standard.bool(forKey: "LodgeDemoShowFormatAlert") {
                try? await Task.sleep(for: .milliseconds(900))
                model.confirmFormatSelectedCard()
            }
        }
        #endif
    }
}

extension View {
    /// Supplies all of the app's shared objects (and the theme settings) to a view
    /// (used by the app and previews).
    func appEnvironment(_ model: AppModel) -> some View {
        // The theme reads the settings, so it goes inside the objects it needs.
        self
            .lodgeTheme()
            .environmentObject(model)
            .environmentObject(model.settings)
            .environmentObject(model.watcher)
            .environmentObject(model.ledger)
            .environmentObject(model.cameras)
            .environmentObject(model.destinations)
            .environmentObject(model.presets)
    }
}

#if DEBUG
#Preview("Main – empty") {
    ContentView().demoEnvironment(DemoData.model(state: .empty)).frame(width: 1000, height: 620)
}

#Preview("Main – ready") {
    ContentView().demoEnvironment(DemoData.model(state: .ready)).frame(width: 1000, height: 620)
}

#Preview("Main – running") {
    ContentView().demoEnvironment(DemoData.model(state: .running)).frame(width: 1000, height: 620)
}

#Preview("Main – finished, dark") {
    ContentView().demoEnvironment(DemoData.model(state: .finished)).frame(width: 1000, height: 620)
        .preferredColorScheme(.dark)
}
#endif

/// Hides the window's title text without changing the title itself.
private struct HiddenWindowTitle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { TitleHidingView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class TitleHidingView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.titleVisibility = .hidden
        }
    }
}
