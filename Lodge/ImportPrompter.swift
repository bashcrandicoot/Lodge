import Foundation
import AppKit
import UserNotifications
import os

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
        Task {
            let settings = await center.notificationSettings()
            Logger.importPrompt.info("Notifications at launch: authorization \(settings.authorizationStatus.logName, privacy: .public), alerts \(settings.alertSetting.logName, privacy: .public), style \(settings.alertStyle.rawValue, privacy: .public)")
        }
    }

    /// Asks macOS for permission to show notifications, the first time only (turning the setting on).
    func requestPermissionIfNeeded() {
        guard usesNotifications else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                Logger.importPrompt.info("Asked for notification permission: granted \(granted, privacy: .public)")
            } catch {
                Logger.importPrompt.error("Asking for notification permission failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: Mounts

    /// A card was just plugged in (not one that was already there at launch).
    /// Completion gets `true` when a prompt was shown or queued.
    /// `force` (the DEBUG "Test Import Prompt" item) skips the quick-remount debounce.
    func cardMounted(_ card: CardVolume, force: Bool = false, completion: @escaping (Bool) -> Void = { _ in }) {
        guard let model else { return completion(false) }
        guard model.settings.askToImport, !isPaused else {
            Logger.importPrompt.info("No prompt for \(card.url.path, privacy: .public): askToImport \(model.settings.askToImport, privacy: .public), paused \(self.isPaused, privacy: .public)")
            return completion(false)
        }
        let destinations = [model.settings.destinationPath].compactMap { $0 } + model.destinations.favorites.map(\.path)
        let ignored = model.settings.ignoredImportIdentities
        Task {
            let (verdict, isCard) = await Task.detached(priority: .userInitiated) {
                let traits = VolumeTraits.read(card.url)
                let media = CameraMedia.looksLikeCameraMedia(root: card.url.path)
                let verdict = ImportPromptPolicy.verdict(
                    for: traits, identity: card.identity, looksLikeCameraMedia: media,
                    destinationPaths: destinations, ignored: ignored)
                Logger.importPrompt.info("Read \(card.url.path, privacy: .public): \(traits.logDescription, privacy: .public), camera media \(media, privacy: .public), verdict \(String(describing: verdict), privacy: .public)")
                return (verdict, traits.isRemovable)
            }.value
            self.kinds[card.id] = isCard ? "card" : "drive"
            completion(self.promptIfAllowed(card, verdict: verdict, force: force))
        }
    }

    #if DEBUG
    /// Menu bar ▸ Test Import Prompt (Debug builds): the full prompt path for the first connected
    /// card that qualifies, as if it had just been plugged in. Completion gets a problem to show,
    /// or `nil` when a prompt went up.
    func testPrompt(completion: @escaping (String?) -> Void) {
        guard let model else { return completion("Lodge isn't ready yet.") }
        let cards = model.watcher.cards
        Logger.importPrompt.info("Test Import Prompt: \(cards.count, privacy: .public) connected: \(cards.map(\.url.path).joined(separator: ", "), privacy: .public)")
        guard !cards.isEmpty else { return completion("No cards or drives are connected.") }
        guard model.settings.askToImport else { return completion("“Ask to import” is off in Settings ▸ General ▸ Menu Bar.") }
        guard !isPaused else { return completion("Detection is paused (menu bar ▸ Resume Detection).") }
        func tryCard(_ index: Int) {
            guard index < cards.count else {
                return completion("None of the connected cards or drives qualify for a prompt. Details are in Console (subsystem com.sebastianphillips.Lodge, category ImportPrompt).")
            }
            cardMounted(cards[index], force: true) { shown in
                if shown { completion(nil) } else { tryCard(index + 1) }
            }
        }
        tryCard(0)
    }
    #endif

    /// The part after the volume was read (also used by the demo's simulated mount).
    @discardableResult
    func promptIfAllowed(_ card: CardVolume, verdict: ImportPromptPolicy.Verdict, force: Bool = false) -> Bool {
        let path = card.url.path
        guard verdict == .prompt, let model, model.settings.askToImport, !isPaused else {
            Logger.importPrompt.info("No prompt for \(path, privacy: .public): verdict \(String(describing: verdict), privacy: .public), paused \(self.isPaused, privacy: .public)")
            return false
        }
        guard model.watcher.cards.contains(card) else {
            Logger.importPrompt.info("No prompt for \(path, privacy: .public): it was removed meanwhile")
            return false
        }
        guard force || debouncer.shouldPrompt(card.identity) else {
            Logger.importPrompt.info("No prompt for \(path, privacy: .public): asked about it moments ago (debounce)")
            return false
        }
        if model.isBusy || model.formatState.isFormatting {
            Logger.importPrompt.info("Queued the prompt for \(path, privacy: .public) until the offload or format finishes")
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

    /// "A7S III card connected", or "SD Card connected" when the name already says what it is.
    nonisolated static func title(for card: CardVolume, kind: String = "card") -> String {
        let name = card.name.trimmingCharacters(in: .whitespaces)
        let saysKind = ["card", "drive", "ssd", "disk"].contains { name.lowercased().hasSuffix(" " + $0) || name.lowercased() == $0 }
        return saysKind ? "\(name) connected" : "\(name) \(kind) connected"
    }
    func title(for card: CardVolume) -> String { Self.title(for: card, kind: kinds[card.id] ?? "card") }
    nonisolated static let message = "Import with Lodge?"

    /// Tests replace the notification / panel with this.
    var presentOverride: ((CardVolume) -> Void)?

    private func present(_ card: CardVolume) {
        if let presentOverride { return presentOverride(card) }
        guard usesNotifications, model?.settings.importPromptStyle != .panel else { return showPanel(for: card) }
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            Logger.importPrompt.info("Prompting for \(card.url.path, privacy: .public): notification authorization \(settings.authorizationStatus.logName, privacy: .public), alerts \(settings.alertSetting.logName, privacy: .public)")
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                await postNotification(for: card)
            case .notDetermined:
                // First prompt ever (the setting was on by default, so never switched on).
                // Show the panel right away: the permission request waits on the user.
                showPanel(for: card)
                do {
                    let granted = try await center.requestAuthorization(options: [.alert, .sound])
                    Logger.importPrompt.info("Asked for notification permission: granted \(granted, privacy: .public)")
                } catch {
                    Logger.importPrompt.error("Asking for notification permission failed: \(error.localizedDescription, privacy: .public)")
                }
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
        content.sound = .default
        let request = UNNotificationRequest(identifier: card.id, content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
            // Posted. A Focus (Do Not Disturb…) can still hold it in Notification Center.
            Logger.importPrompt.info("Posted the notification \"\(content.title, privacy: .public)\"")
        } catch {
            // Not allowed after all (e.g. an unsigned build): fall back to the panel.
            Logger.importPrompt.error("Posting the notification failed (\(error.localizedDescription, privacy: .public)): showing the panel")
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
        Logger.importPrompt.info("Showed the import panel for \(card.url.path, privacy: .public)")
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
        // Show the banner (with its sound) even while Lodge is the active app.
        completionHandler([.banner, .list, .sound])
    }
}

extension UNAuthorizationStatus {
    var logName: String {
        switch self {
        case .notDetermined: "notDetermined"
        case .denied: "denied"
        case .authorized: "authorized"
        case .provisional: "provisional"
        case .ephemeral: "ephemeral"
        @unknown default: "unknown(\(rawValue))"
        }
    }
}

extension UNNotificationSetting {
    var logName: String {
        switch self {
        case .notSupported: "notSupported"
        case .disabled: "disabled"
        case .enabled: "enabled"
        @unknown default: "unknown(\(rawValue))"
        }
    }
}
