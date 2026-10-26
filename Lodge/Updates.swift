import SwiftUI
import Combine
import Sparkle

/// App updates, powered by Sparkle (https://sparkle-project.org).
///
/// Sparkle reads the feed at `SUFeedURL` (Info.plist), shows its own "A new version is
/// available" window, and only installs updates signed with the private key that matches
/// `SUPublicEDKey`. See docs/RELEASING.md for how to publish an update.
@MainActor
enum AppUpdates {
    /// The one Sparkle controller for the app's lifetime. It isn't started for the unit tests'
    /// host or the screenshot demo mode, so those never check for (or show) updates.
    static let controller = SPUStandardUpdaterController(
        startingUpdater: shouldStart, updaterDelegate: nil, userDriverDelegate: nil)

    static var updater: SPUUpdater { controller.updater }

    private static var shouldStart: Bool {
        if AppModel.isRunningUnitTests { return false }
        #if DEBUG
        if DemoData.launchState != nil { return false }
        #endif
        return true
    }
}

/// Keeps "Check for Updates…" disabled while a check is already running
/// (the standard Sparkle SwiftUI pattern).
final class CheckForUpdatesViewModel: ObservableObject {
    @Published private(set) var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheckForUpdates)
    }
}

/// Lodge ▸ Check for Updates…
struct CheckForUpdatesView: View {
    @StateObject private var viewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        _viewModel = StateObject(wrappedValue: CheckForUpdatesViewModel(updater: updater))
    }

    var body: some View {
        Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!viewModel.canCheckForUpdates)
    }
}

/// Mirrors the updater's settings (stored by Sparkle in the app's defaults) for SwiftUI.
final class UpdaterSettingsModel: ObservableObject {
    private let updater: SPUUpdater
    private var observations: Set<AnyCancellable> = []

    init(updater: SPUUpdater) {
        self.updater = updater
        // Redraw when Sparkle changes these itself (e.g. from its update window).
        updater.publisher(for: \.automaticallyChecksForUpdates).map { _ in () }
            .merge(with: updater.publisher(for: \.automaticallyDownloadsUpdates).map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &observations)
    }

    var automaticallyChecksForUpdates: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { objectWillChange.send(); updater.automaticallyChecksForUpdates = newValue }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { updater.automaticallyDownloadsUpdates }
        set { objectWillChange.send(); updater.automaticallyDownloadsUpdates = newValue }
    }

    /// False if the feed or Info.plist turns automatic installs off (SUAllowsAutomaticUpdates).
    var allowsAutomaticUpdates: Bool { updater.allowsAutomaticUpdates }
}

/// The Updates section of Settings ▸ General.
struct UpdateSettingsSection: View {
    @StateObject private var model: UpdaterSettingsModel

    init(updater: SPUUpdater) {
        _model = StateObject(wrappedValue: UpdaterSettingsModel(updater: updater))
    }

    var body: some View {
        Section {
            Toggle("Automatically check for updates", isOn: $model.automaticallyChecksForUpdates)
            if model.allowsAutomaticUpdates {
                Toggle("Automatically download and install updates", isOn: $model.automaticallyDownloadsUpdates)
                    .disabled(!model.automaticallyChecksForUpdates)
            }
        } header: {
            Text("Updates")
        } footer: {
            Text("Lodge checks for a new version once a day. You can also choose Lodge ▸ Check for Updates… any time.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
