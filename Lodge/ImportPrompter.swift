import Foundation
import AppKit
import UserNotifications

/// Shows "A7SIII card connected · Import with Lodge?" when a camera card or drive is plugged in,
/// as a notification, or as a small floating panel when notifications aren't allowed.
/// It never starts an offload: Import only brings Lodge forward with the card selected.
@MainActor
final class ImportPrompter: NSObject, ObservableObject {
    /// Menu bar ▸ Pause Detection: no prompts (and no window popping up) until resumed.
    @Published var isPaused = false
    /// Cards that were plugged in during an offload; asked about once it finishes.
    @Published private(set) var queued: [CardVolume] = []

    weak var model: AppModel?
    /// False for unit tests and demo mode (always the panel, never a permission prompt).
    let usesNotifications: Bool
    private var debouncer = MountDebouncer()
    private var panels: [String: ImportPromptPanel] = [:]
    /// "card" for SD/CFexpress readers (removable media), "drive" for SSDs and other drives.
    private var kinds: [String: String] = [:]

    static let categoryID = "LodgeCardConnected"
    nonisolated private enum Action {
        static let importCard = "import"
        static let ignore = "ignore"
        static let dontAsk = "dontAsk"
    }
    nonisolated private static let cardPathKey = "cardPath"

    init(usesNotifications: Bool) {
        self.usesNotifications = usesNotifications
        super.init()
    }

    /// Call at launch, before the app finishes launching, so a click on a notification
    /// that launched Lodge still reaches us.
    func registerWithNotificationCenter() {
        guard usesNotifications else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let importAction = UNNotificationAction(identifier: Action.importCard, title: "Import", options: [.foreground])
        let ignore = UNNotificationAction(identifier: Action.ignore, title: "Ignore", options: [])
        let dontAsk = UNNotificationAction(identifier: Action.dontAsk, title: "Don’t Ask for This Card", options: [])
        let category = UNNotificationCategory(identifier: Self.categoryID, actions: [importAction, ignore, dontAsk],
                                              intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
    }

    /// Asks macOS for permission to show notifications, the first time only (turning the setting on).
    func requestPermissionIfNeeded() {
        guard usesNotifications else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }

    // MARK: Mounts

    /// A card was just plugged in (not one that was already there at launch).
    /// Completion gets `true` when a prompt was shown or queued.
    func cardMounted(_ card: CardVolume, completion: @escaping (Bool) -> Void = { _ in }) {
        guard let model, model.settings.askToImport, !isPaused else { return completion(false) }
        let destinations = [model.settings.destinationPath].compactMap { $0 } + model.destinations.favorites.map(\.path)
        let ignored = model.settings.ignoredImportIdentities
        Task {
            let (verdict, isCard) = await Task.detached(priority: .userInitiated) {
                let traits = VolumeTraits.read(card.url)
                let verdict = ImportPromptPolicy.verdict(
                    for: traits, identity: card.identity,
                    looksLikeCameraMedia: CameraMedia.looksLikeCameraMedia(root: card.url.path),
                    destinationPaths: destinations, ignored: ignored)
                return (verdict, traits.isRemovable)
            }.value
            self.kinds[card.id] = isCard ? "card" : "drive"
            completion(self.promptIfAllowed(card, verdict: verdict))
        }
    }

    /// The part after the volume was read (also used by the demo's simulated mount).
    @discardableResult
    func promptIfAllowed(_ card: CardVolume, verdict: ImportPromptPolicy.Verdict) -> Bool {
        guard verdict == .prompt, let model, model.settings.askToImport, !isPaused,
              model.watcher.cards.contains(card), debouncer.shouldPrompt(card.identity) else { return false }
        if model.isBusy || model.formatState.isFormatting {
            if !queued.contains(card) { queued.append(card) }
        } else {
            present(card)
        }
        return true
    }

    /// The offload (or format) finished: ask about the cards plugged in meanwhile.
    func offloadEnded() {
        let waiting = queued
        queued = []
        guard let model, model.settings.askToImport, !isPaused else { return }
        for card in waiting where model.watcher.cards.contains(card) { present(card) }
    }

    func cardRemoved(_ card: CardVolume) {
        queued.removeAll { $0 == card }
        kinds[card.id] = nil
        dismiss(card)
    }

    // MARK: Showing

    nonisolated static func title(for card: CardVolume, kind: String = "card") -> String { "\(card.name) \(kind) connected" }
    func title(for card: CardVolume) -> String { Self.title(for: card, kind: kinds[card.id] ?? "card") }
    nonisolated static let message = "Import with Lodge?"

    /// Tests replace the notification / panel with this.
    var presentOverride: ((CardVolume) -> Void)?

    private func present(_ card: CardVolume) {
        if let presentOverride { return presentOverride(card) }
        guard usesNotifications else { return showPanel(for: card) }
        Task {
            let center = UNUserNotificationCenter.current()
            switch await center.notificationSettings().authorizationStatus {
            case .authorized, .provisional:
                await postNotification(for: card)
            case .notDetermined:
                // First prompt ever (the setting was on by default, so never switched on).
                let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
                if granted { await postNotification(for: card) } else { showPanel(for: card) }
            default:
                showPanel(for: card)
            }
        }
    }

    private func postNotification(for card: CardVolume) async {
        let content = UNMutableNotificationContent()
        content.title = title(for: card)
        content.body = Self.message
        content.categoryIdentifier = Self.categoryID
        content.userInfo = [Self.cardPathKey: card.id]
        content.sound = nil
        let request = UNNotificationRequest(identifier: card.id, content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            // Not allowed after all (e.g. an unsigned build): fall back to the panel.
            showPanel(for: card)
        }
    }

    func showPanel(for card: CardVolume) {
        panels[card.id]?.close()
        let panel = ImportPromptPanel(card: card, title: title(for: card), index: panels.count) { [weak self] choice in
            self?.handle(choice, cardPath: card.id)
        }
        panels[card.id] = panel
        panel.show()
    }

    private func dismiss(_ card: CardVolume) {
        panels.removeValue(forKey: card.id)?.close()
        guard usesNotifications else { return }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [card.id])
    }

    // MARK: Answers

    enum Choice { case importCard, ignore, dontAsk }

    func handle(_ choice: Choice, cardPath: String) {
        panels.removeValue(forKey: cardPath)?.close()
        guard let model, let card = model.watcher.cards.first(where: { $0.id == cardPath }) else { return }
        switch choice {
        case .importCard: model.showForImport(card)
        case .ignore: break
        case .dontAsk: model.settings.ignoreImports(from: card)
        }
    }
}

extension ImportPrompter: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let path = response.notification.request.content.userInfo[Self.cardPathKey] as? String
        let action = response.actionIdentifier
        Task { @MainActor in
            defer { completionHandler() }
            guard let path else { return }
            switch action {
            case Action.importCard, UNNotificationDefaultActionIdentifier: self.handle(.importCard, cardPath: path)
            case Action.dontAsk: self.handle(.dontAsk, cardPath: path)
            default: break
            }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}
