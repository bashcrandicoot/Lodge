import SwiftUI
import AppKit
import Combine

/// The setup window. AppKit-owned (not a SwiftUI scene) so it only exists when it's needed:
/// first launch, or `-LodgeDemoOnboarding YES`. The main window waits behind it.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let title = "Welcome to Lodge"
    /// The one that's open.
    private(set) static var current: OnboardingWindowController?

    let store: OnboardingStore
    let model: AppModel
    let window: NSWindow
    private var stepObserver: AnyCancellable?
    private var finished = false

    /// `-LodgeDemoOnboarding YES`: show setup even when it was finished before.
    static var isForced: Bool { UserDefaults.standard.bool(forKey: "LodgeDemoOnboarding") }

    /// Called once at launch: shows setup the first time Lodge runs (and when forced).
    static func showIfNeeded(for model: AppModel) {
        guard current == nil, !AppModel.isRunningUnitTests else { return }
        let store: OnboardingStore
        if AppModel.isDemo {
            // Screenshots never read or write the real defaults.
            guard isForced else { return }
            store = OnboardingStore(defaults: nil)
        } else {
            store = OnboardingStore()
            if isForced {
                if store.isFinished { store.restart() }
            } else if !store.shouldShow(for: model) {
                return
            }
        }
        var drives = OnboardingDrive.live()
        #if DEBUG
        if AppModel.isDemo { drives = OnboardingDemo.drives }
        if let raw = UserDefaults.standard.string(forKey: "LodgeDemoOnboardingStep"),
           let step = OnboardingStep(rawValue: raw) {
            OnboardingDemo.prepare(store, at: step, model: model)
        }
        #endif
        let controller = OnboardingWindowController(store: store, model: model, drives: drives)
        current = controller
        controller.show()
    }

    init(store: OnboardingStore, model: AppModel, drives: [OnboardingDrive]) {
        self.store = store
        self.model = model
        window = NSWindow(contentRect: NSRect(origin: .zero, size: OnboardingView.size),
                          styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        super.init()
        window.title = Self.title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier("onboarding")
        window.tabbingMode = .disallowed
        window.delegate = self
        let hosting = NSHostingView(rootView: OnboardingView(store: store, model: model, drives: drives) { [weak self] exit in
            self?.finish(exit)
        })
        // The window keeps its 1280×800 frame: SwiftUI sits in a plain container so it can't
        // grow the window by the title bar's height (the content runs under the title bar).
        hosting.sizingOptions = []
        hosting.safeAreaRegions = []
        let container = NSView(frame: NSRect(origin: .zero, size: OnboardingView.size))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        window.contentView = container
        // Full-size content: the frame is the content (the title bar floats over it).
        window.setFrame(NSRect(origin: .zero, size: OnboardingView.size), display: false)
        applyAppearance(for: store.step)
        stepObserver = store.$step.sink { [weak self] step in self?.applyAppearance(for: step) }
    }

    /// The splash and done screens are always dark (the night scene); the steps follow Lodge's
    /// appearance (Settings ▸ Appearance, which can be "System").
    private func applyAppearance(for step: OnboardingStep) {
        window.appearance = step.forcesDarkAppearance ? NSAppearance(named: .darkAqua) : nil
    }

    private func show() {
        window.setFrame(NSRect(origin: window.frame.origin, size: OnboardingView.size), display: false)
        window.center()
        if AppModel.isDemo {
            #if DEBUG
            DemoData.centreOnSharpestScreen(window)
            #endif
            window.orderFrontRegardless()   // screenshots never take focus
        } else {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
        }
        // The main window waits until setup is done (SwiftUI may still be opening it).
        for delay in [0.0, 0.3, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, !self.finished else { return }
                MainWindow.window?.orderOut(nil)
            }
        }
    }

    func finish(_ exit: OnboardingExit) {
        guard !finished else { return }
        finished = true
        if store.step == .done || exit == .skipped { store.markFinished() }
        window.close()
        let activate = !AppModel.isDemo
        switch exit {
        case .skipped, .openLodge:
            MainWindow.show(activate: activate)
        case .offload(let card):
            model.select(card)
            MainWindow.show(activate: activate)
        case .openSettings:
            MainWindow.show(activate: activate)
            if activate { MainWindow.showSettings() }
        }
        Self.current = nil
    }

    // Closing the window keeps the progress (setup resumes next launch), except on the done
    // screen, where the preset is already saved.
    func windowWillClose(_ notification: Notification) {
        guard !finished else { return }
        finished = true
        if store.step == .done { store.markFinished() }
        MainWindow.show(activate: !AppModel.isDemo)
        DispatchQueue.main.async { Self.current = nil }
    }
}

#if DEBUG
/// Screenshots of setup: fake drives and a draft filled in up to the requested step.
enum OnboardingDemo {
    static let drives: [OnboardingDrive] = [
        OnboardingDrive(name: "Shuttle SSD", kind: "External", suggestedPath: "/Volumes/Shuttle SSD/Projects",
                        totalBytes: 2_000_000_000_000, freeBytes: 1_240_000_000_000, isInternal: false),
        OnboardingDrive(name: "Studio RAID", kind: "External", suggestedPath: "/Volumes/Studio RAID",
                        totalBytes: 20_000_000_000_000, freeBytes: 5_800_000_000_000, isInternal: false),
        OnboardingDrive(name: "Macintosh HD", kind: "Internal", suggestedPath: NSHomeDirectory() + "/Movies",
                        totalBytes: 1_000_000_000_000, freeBytes: 186_000_000_000, isInternal: true),
    ]

    @MainActor
    static func prepare(_ store: OnboardingStore, at step: OnboardingStep, model: AppModel) {
        store.draft.destinationPath = drives[0].suggestedPath
        store.draft.choose(.filmShoot)
        if step == .done {
            store.go(to: .review)
            store.save(into: model)
        } else {
            store.go(to: step)
        }
    }
}
#endif
