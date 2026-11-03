import SwiftUI
import AppKit

/// The main window: a left-to-right funnel (Card → Clips → Destination)
/// with the offload bar along the bottom.
struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var license: LicenseModel
    /// Saved for `MainWindow`, to reopen this window from the menu bar or an import prompt.
    @Environment(\.openWindow) private var openWindow
    /// Saved for `MainWindow`, to open Settings from the menu bar icon.
    @Environment(\.openSettings) private var openSettings
    @State private var enteringLicense = false

    var body: some View {
        Group {
            if license.allowsUse || model.isBusy {
                workspace
            } else {
                LicenseGate()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await license.refresh() }
        }
        .toolbar {
            // With the title hidden the toolbar has nothing on the left, so a flexible space
            // keeps Recent Offloads and Settings on the trailing side, away from the traffic lights.
            ToolbarItem(placement: .automatic) {
                Spacer()
            }
            // Presets: one click changes where files go and how they're named. Kept at the
            // right, out of the way, just before Recent Offloads and Settings.
            if license.allowsUse {
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
            }
            if let trial = license.trialToolbarText {
                ToolbarItem(placement: .automatic) {
                    HStack(spacing: 8) {
                        Text(trial)
                        Button(LicenseCopy.enterLicense) { enteringLicense = true }
                            .buttonStyle(.borderless)
                    }
                    .font(.caption)
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
        .modifier(HideWindowTitle())
        .onAppear {
            MainWindow.openAction = { [openWindow] in openWindow(id: "main") }
            MainWindow.openSettingsAction = { [openSettings] in openSettings() }
            presentTrialNoticeIfNeeded()
            if TrialNotice.pendingLicenseEntry {
                TrialNotice.pendingLicenseEntry = false
                enteringLicense = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: TrialNotice.enterLicense)) { _ in
            TrialNotice.pendingLicenseEntry = false
            enteringLicense = true
        }
        .sheet(isPresented: $enteringLicense) {
            LicenseEntrySheet()
        }
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
            // Screenshots: `-LodgeDemoSupportPrompt YES` shows the support card.
            if DemoData.launchState != nil, UserDefaults.standard.bool(forKey: "LodgeDemoSupportPrompt") {
                try? await Task.sleep(for: .milliseconds(600))
                model.supportPrompt.forceShow()
            }
            // Screenshots: `-LodgeDemoMount YES` pretends the demo card was just plugged in
            // (the import prompt; always the floating panel in demo mode).
            if DemoData.launchState != nil, UserDefaults.standard.bool(forKey: "LodgeDemoMount"),
               let card = model.watcher.cards.first {
                try? await Task.sleep(for: .milliseconds(600))
                model.importPrompter.promptIfAllowed(card, verdict: .prompt)
            }
            // Screenshots: `-LodgeDemoMenuPreview YES` draws the menu bar icon's menu in a window.
            if DemoData.launchState != nil, UserDefaults.standard.bool(forKey: "LodgeDemoMenuPreview") {
                try? await Task.sleep(for: .milliseconds(600))
                MenuBarMenuPreview.show(model: model)
            }
            // Screenshots: `-LodgeDemoShowFormatAlert YES` opens the Format confirmation.
            if DemoData.launchState != nil, UserDefaults.standard.bool(forKey: "LodgeDemoShowFormatAlert") {
                try? await Task.sleep(for: .milliseconds(900))
                model.confirmFormatSelectedCard()
            }
        }
        #endif
    }

    /// Once each launch, while the trial is running and this Mac has no license.
    /// Demo mode and a purchased license skip it. A login launch that stays in the menu bar
    /// has no window, so the note waits and appears as a panel.
    private func presentTrialNoticeIfNeeded() {
        guard !AppDelegate.launchesWithoutWindow else { return }
        TrialNotice.presentIfNeeded(license: license)
    }

    /// The funnel. Hidden until this Mac has a usable license. An offload already running
    /// stays on screen if the grace period ends mid-copy.
    private var workspace: some View {
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
                .background(.bar)
        }
        .background(ThemeBackground())
        .modifier(SupportPromptOverlay())
        .task {
            // Lodge is idle a moment after launch: the buy note may show then too.
            try? await Task.sleep(for: .seconds(3))
            model.considerSupportPrompt()
        }
    }
}

extension View {
    /// Supplies all of the app's shared objects (and the theme settings) to a view
    /// (used by the app and previews).
    func appEnvironment(_ model: AppModel, license: LicenseModel? = nil) -> some View {
        let resolvedLicense = license ?? .previewLicensed()
        // The theme reads the settings, so it goes inside the objects it needs.
        return self
            .lodgeTheme()
            .environmentObject(model)
            .environmentObject(model.settings)
            .environmentObject(model.watcher)
            .environmentObject(model.ledger)
            .environmentObject(model.cameras)
            .environmentObject(model.destinations)
            .environmentObject(model.presets)
            .environmentObject(model.supportPrompt)
            .environmentObject(resolvedLicense)
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

/// Hides the window's title text without changing the title itself (so the Window menu,
/// Mission Control and VoiceOver still say "Lodge").
private struct HideWindowTitle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content
                .toolbar(removing: .title)
                .background(HiddenWindowTitle())
        } else {
            content
                .background(HiddenWindowTitle())
        }
    }
}

/// AppKit side of `HideWindowTitle`. SwiftUI turns the title back on when it rebuilds the
/// toolbar (for example after Done, when the bar and the preset menu change), so this keeps
/// watching the window and hides the title again whenever it reappears.
private struct HiddenWindowTitle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { TitleHidingView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class TitleHidingView: NSView {
        private var observation: NSKeyValueObservation?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observation = nil
            guard let window else { return }
            window.titleVisibility = .hidden
            observation = window.observe(\.titleVisibility, options: [.new]) { window, _ in
                guard window.titleVisibility != .hidden else { return }
                DispatchQueue.main.async { window.titleVisibility = .hidden }
            }
        }
    }
}
