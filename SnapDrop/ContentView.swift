import SwiftUI

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
            ToolbarItem(placement: .primaryAction) {
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
            ToolbarItem(placement: .primaryAction) {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Settings (⌘,)")
            }
        }
        .navigationTitle("SnapDrop")
        .navigationSubtitle(model.selectedCard?.name ?? "No card")
        #if DEBUG
        .task {
            // Screenshots: `-SnapDropDemoSettingsTab naming` opens Settings on that tab.
            if DemoData.launchState != nil, let tab = DemoData.launchSettingsTab {
                UserDefaults.standard.set(tab.rawValue, forKey: SettingsTab.storageKey)
                try? await Task.sleep(for: .milliseconds(600))
                openSettings()
            }
            // Screenshots: `-SnapDropDemoShowFormatAlert YES` opens the Format confirmation.
            if DemoData.launchState != nil, UserDefaults.standard.bool(forKey: "SnapDropDemoShowFormatAlert") {
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
        self
            .environmentObject(model)
            .environmentObject(model.settings)
            .environmentObject(model.watcher)
            .environmentObject(model.ledger)
            .environmentObject(model.cameras)
            .environmentObject(model.destinations)
            .snapDropTheme()
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
