import SwiftUI
import AppKit

// The quiet "Support Lodge" card: shown at most twice, only after someone has used Lodge for
// a while, never during a transfer. No notifications, no network calls, no tracking: the
// only thing stored is the little bit of state below, in the app's own UserDefaults.

/// What the prompt knows (saved in UserDefaults).
struct SupportPromptState: Equatable {
    /// When this version of Lodge (or later) first launched.
    var firstLaunch: Date?
    /// Offloads where every file was copied and verified.
    var successfulOffloads = 0
    var timesShown = 0
    /// Not before this date (set when it's shown, so "Maybe Later" waits 30 days).
    var nextAskDate: Date?
    /// "Support Lodge" or "Don't Ask Again" was clicked.
    var neverAskAgain = false
}

enum SupportPromptChoice {
    case support, later, never
}

/// The timing rules, kept pure so they can be unit tested.
enum SupportPromptPolicy {
    static let requiredOffloads = 5
    static let minimumUse: TimeInterval = 3 * 24 * 60 * 60
    static let laterDelay: TimeInterval = 30 * 24 * 60 * 60
    /// Once, plus once more after "Maybe Later".
    static let maximumShows = 2

    static func isDue(_ state: SupportPromptState, now: Date) -> Bool {
        guard !state.neverAskAgain, state.timesShown < maximumShows,
              state.successfulOffloads >= requiredOffloads,
              let first = state.firstLaunch, now.timeIntervalSince(first) >= minimumUse else { return false }
        if let next = state.nextAskDate, now < next { return false }
        return true
    }

    static func launched(_ state: SupportPromptState, now: Date) -> SupportPromptState {
        var state = state
        if state.firstLaunch == nil { state.firstLaunch = now }
        return state
    }

    static func offloadFinished(_ state: SupportPromptState, cleanSuccess: Bool) -> SupportPromptState {
        var state = state
        if cleanSuccess { state.successfulOffloads += 1 }
        return state
    }

    static func shown(_ state: SupportPromptState, now: Date) -> SupportPromptState {
        var state = state
        state.timesShown += 1
        state.nextAskDate = now.addingTimeInterval(laterDelay)
        return state
    }

    static func chose(_ choice: SupportPromptChoice, _ state: SupportPromptState, now: Date) -> SupportPromptState {
        var state = state
        switch choice {
        case .later: state.nextAskDate = now.addingTimeInterval(laterDelay)
        case .support, .never: state.neverAskAgain = true
        }
        return state
    }
}

/// Keeps the prompt's state in UserDefaults (or only in memory, for tests and demo mode)
/// and says when the card is up.
@MainActor
final class SupportPromptStore: ObservableObject {
    @Published private(set) var isShowing = false
    private(set) var state: SupportPromptState {
        didSet { save() }
    }
    private let defaults: UserDefaults?
    private let now: () -> Date

    private enum Key {
        static let firstLaunch = "supportPromptFirstLaunch"
        static let offloads = "supportPromptSuccessfulOffloads"
        static let timesShown = "supportPromptTimesShown"
        static let nextAsk = "supportPromptNextAskDate"
        static let never = "supportPromptNeverAskAgain"
    }

    init(defaults: UserDefaults? = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        var state = SupportPromptState()
        if let defaults {
            state.firstLaunch = defaults.object(forKey: Key.firstLaunch) as? Date
            state.successfulOffloads = defaults.integer(forKey: Key.offloads)
            state.timesShown = defaults.integer(forKey: Key.timesShown)
            state.nextAskDate = defaults.object(forKey: Key.nextAsk) as? Date
            state.neverAskAgain = defaults.bool(forKey: Key.never)
        }
        self.state = SupportPromptPolicy.launched(state, now: now())
    }

    func offloadFinished(cleanSuccess: Bool) {
        state = SupportPromptPolicy.offloadFinished(state, cleanSuccess: cleanSuccess)
    }

    /// Shows the card if it's due. Call only when Lodge is idle (after Done, or at launch).
    func showIfDue() {
        guard !isShowing, SupportPromptPolicy.isDue(state, now: now()) else { return }
        state = SupportPromptPolicy.shown(state, now: now())
        isShowing = true
    }

    func choose(_ choice: SupportPromptChoice) {
        state = SupportPromptPolicy.chose(choice, state, now: now())
        isShowing = false
        if choice == .support { Support.openTipJar() }
    }

    /// Puts the card away without an answer (an offload is starting). It waits 30 days.
    func hide() {
        isShowing = false
    }

    #if DEBUG
    /// Screenshots: `-LodgeDemoSupportPrompt YES`.
    func forceShow() { isShowing = true }
    #endif

    private func save() {
        guard let defaults else { return }
        defaults.set(state.firstLaunch, forKey: Key.firstLaunch)
        defaults.set(state.successfulOffloads, forKey: Key.offloads)
        defaults.set(state.timesShown, forKey: Key.timesShown)
        defaults.set(state.nextAskDate, forKey: Key.nextAsk)
        defaults.set(state.neverAskAgain, forKey: Key.never)
    }
}

/// The card itself, floating over the main window (it doesn't block anything else).
struct SupportPromptCard: View {
    @EnvironmentObject private var prompt: SupportPromptStore

    var body: some View {
        VStack(spacing: 0) {
            // Designed by Yuwie (Design/support-graphic/). Transparent, so it sits on the card.
            Image("SupportHeader")
                .resizable()
                .frame(width: 320, height: 160)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("Support Lodge")
                    .font(.headline)
                Text("Lodge is made by one person at \(Support.developerName). If it saves you time, you can chip in on Gumroad. Thank you!")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 12)
            .padding(.horizontal, 24)
            HStack(spacing: 6) {
                Button("Don’t Ask Again") { prompt.choose(.never) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                Spacer(minLength: 8)
                Button("Maybe Later") { prompt.choose(.later) }
                    .keyboardShortcut(.cancelAction)
                    .fixedSize()
                Button("Support Lodge") { prompt.choose(.support) }
                    .buttonStyle(.themeProminent)
                    .fixedSize()
                    .help("Opens \(Support.tipJarURL.absoluteString) in your browser")
            }
            .controlSize(.regular)
            .padding(.top, 20)
            .padding(.horizontal, 16)
            .padding(.bottom, 18)
        }
        .padding(.top, 12)
        .frame(width: 380)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.25), radius: 24, y: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Support Lodge")
        .accessibilityAddTraits(.isModal)
    }
}

/// Floats the card over the main window, fading in (and rising, unless Reduce Motion is on).
struct SupportPromptOverlay: ViewModifier {
    @EnvironmentObject private var prompt: SupportPromptStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay {
            ZStack {
                if prompt.isShowing {
                    SupportPromptCard()
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 16)))
                }
            }
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.45, bounce: 0.15),
                       value: prompt.isShowing)
        }
    }
}
