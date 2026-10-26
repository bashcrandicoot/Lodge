import SwiftUI
import AppKit
import ServiceManagement
import Combine

/// Opening, finding and tracking the main window, for the menu bar icon, the import prompt
/// and reopening Lodge from Finder / the Dock / Spotlight while it runs in the background.
@MainActor
enum MainWindow {
    /// SwiftUI's `openWindow(id: "main")`, saved by the first view that can see it.
    static var openAction: (() -> Void)?
    /// SwiftUI's `openSettings()`, saved the same way (AppKit has no supported way to open Settings).
    static var openSettingsAction: (() -> Void)?

    static var window: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("main") == true && $0.isVisible }
    }

    static var isOpen: Bool { window != nil }

    /// Lodge is in front with its window showing (the user is looking at it).
    static var isFrontmost: Bool { NSApp.isActive && (window?.isVisible ?? false) && !(window?.isMiniaturized ?? true) }

    /// Shows the main window (reopening it if it was closed) and brings Lodge forward.
    /// `activate: false` is only used by screenshots, which must never take focus.
    static func show(activate: Bool = true) {
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
        if activate { NSApp.activate() }
        if let window {
            if window.isMiniaturized { window.deminiaturize(nil) }
            activate ? window.makeKeyAndOrderFront(nil) : window.orderFrontRegardless()
        } else {
            openAction?()
        }
    }

    /// Lodge ▸ Settings…, from the menu bar icon (Lodge may have no window open).
    static func showSettings() {
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
        NSApp.activate()
        if let openSettingsAction {
            openSettingsAction()
        } else {
            show()
        }
    }
}

/// What's in the menu bar icon's menu. A plain list so it can be tested and drawn for screenshots.
enum MenuBarItem: Hashable {
    case openLodge
    /// "Cards & Drives" (or "No cards connected").
    case cardsHeader(empty: Bool)
    case importCard(path: String, name: String, enabled: Bool)
    case offloading
    case pause(paused: Bool)
    case settings
    case quit
    case divider

    static func items(cards: [CardVolume], isPaused: Bool, isBusy: Bool) -> [MenuBarItem] {
        var items: [MenuBarItem] = [.openLodge, .divider, .cardsHeader(empty: cards.isEmpty)]
        items += cards.map { .importCard(path: $0.id, name: $0.name, enabled: !isBusy) }
        if isBusy { items.append(.offloading) }
        items += [.divider, .pause(paused: isPaused), .settings, .divider, .quit]
        return items
    }

    var title: String {
        switch self {
        case .openLodge: return "Open Lodge"
        case .cardsHeader(let empty): return empty ? "No Cards Connected" : "Cards & Drives"
        case .importCard(_, let name, _): return "Import from \(name)…"
        case .offloading: return "Offloading… (imports wait until it’s done)"
        case .pause(let paused): return paused ? "Resume Detection" : "Pause Detection"
        case .settings: return "Settings…"
        case .quit: return "Quit Lodge"
        case .divider: return ""
        }
    }
}

/// The menu bar icon and its menu.
///
/// An AppKit `NSStatusItem` rather than SwiftUI's `MenuBarExtra`: with a `MenuBarExtra` in the
/// scene list, closing the main window sent SwiftUI's scene graph into an endless update loop
/// (a stack-overflow crash), which is exactly what menu bar mode needs to survive.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private static var shared: StatusItemController?

    /// Puts the icon in the menu bar whenever `model.menuBarIconInserted` is on (not in unit tests).
    static func start(for model: AppModel) {
        guard !AppModel.isRunningUnitTests else { return }
        // After the current SwiftUI update (the model is made while the scenes are built).
        DispatchQueue.main.async {
            guard shared == nil else { return }
            shared = StatusItemController(model: model)
        }
    }

    private weak var model: AppModel?
    private var statusItem: NSStatusItem?
    private var visibilityObservation: NSKeyValueObservation?
    private var cancellable: AnyCancellable?

    init(model: AppModel) {
        self.model = model
        super.init()
        cancellable = model.$menuBarIconInserted.removeDuplicates().sink { [weak self] inserted in
            self?.setInserted(inserted)
        }
    }

    private func setInserted(_ inserted: Bool) {
        if inserted {
            if statusItem == nil { install() }
            statusItem?.isVisible = true
        } else if let item = statusItem {
            visibilityObservation = nil
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    /// The little Lodge cabin icon, in color. `MenuBarIconTemplate` is a one-color version that
    /// follows the menu bar's appearance, if the color one ever needs to go.
    nonisolated static func iconImage(template: Bool = false) -> NSImage? {
        let image = NSImage(named: template ? "MenuBarIconTemplate" : "MenuBarIcon")
            ?? NSImage(systemSymbolName: "house.lodge", accessibilityDescription: "Lodge")
        image?.isTemplate = template
        image?.accessibilityDescription = "Lodge"
        return image
    }

    private func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "LodgeMenuBarIcon"
        // ⌘-dragging the icon out of the menu bar turns "Show menu bar icon" off.
        item.behavior = .removalAllowed
        if let button = item.button {
            button.image = Self.iconImage()
            button.toolTip = "Lodge"
        }
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        statusItem = item
        visibilityObservation = item.observe(\.isVisible, options: [.new]) { [weak self] _, change in
            guard change.newValue == false else { return }
            Task { @MainActor in
                guard let self, let model = self.model, model.menuBarIconInserted else { return }
                model.menuBarIconInserted = false
            }
        }
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let model else { return }
        let items = MenuBarItem.items(cards: model.watcher.cards, isPaused: model.importPrompter.isPaused,
                                      isBusy: model.isBusy)
        for item in items { menu.addItem(menuItem(for: item)) }
    }

    private func menuItem(for item: MenuBarItem) -> NSMenuItem {
        switch item {
        case .divider:
            return .separator()
        case .cardsHeader, .offloading:
            let header = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
            header.isEnabled = false
            return header
        case .importCard(let path, _, let enabled):
            let entry = action(item.title, #selector(importCard(_:)))
            entry.representedObject = path
            entry.isEnabled = enabled
            return entry
        case .openLodge: return action(item.title, #selector(openLodge))
        case .pause: return action(item.title, #selector(togglePause))
        case .settings: return action(item.title, #selector(openSettings), key: ",")
        case .quit: return action(item.title, #selector(quit), key: "q")
        }
    }

    private func action(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        entry.target = self
        return entry
    }

    @objc private func openLodge() { MainWindow.show() }

    @objc private func importCard(_ sender: NSMenuItem) {
        guard let model, let path = sender.representedObject as? String,
              let card = model.watcher.cards.first(where: { $0.id == path }) else { return }
        model.showForImport(card)
    }

    @objc private func togglePause() { model?.importPrompter.isPaused.toggle() }

    @objc private func openSettings() { MainWindow.showSettings() }

    @objc private func quit() { NSApp.terminate(nil) }
}

/// Settings ▸ General ▸ Menu Bar ▸ Open at login, through `SMAppService.mainApp`.
@MainActor
final class LoginItem: ObservableObject {
    @Published private(set) var status: SMAppService.Status
    @Published private(set) var lastError: String?
    /// Demo mode and tests show the switch without touching the real login items.
    private let isLive: Bool

    init(isLive: Bool) {
        self.isLive = isLive
        status = isLive ? SMAppService.mainApp.status : .notRegistered
    }

    var isOn: Bool { status == .enabled || status == .requiresApproval }
    var needsApproval: Bool { status == .requiresApproval }

    func refresh() {
        guard isLive else { return }
        status = SMAppService.mainApp.status
    }

    func set(_ on: Bool) {
        guard isLive else { status = on ? .enabled : .notRegistered; return }
        lastError = nil
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
