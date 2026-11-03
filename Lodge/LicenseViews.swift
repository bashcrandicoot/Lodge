import SwiftUI
import AppKit

extension LicenseModel {
    var keyDraftBinding: Binding<String> {
        Binding(get: { self.keyDraft }, set: { self.keyDraft = $0 })
    }
}

/// Key entry from the trial. Purchase stays on the lock gate, after the trial.
struct LicenseEntrySheet: View {
    @EnvironmentObject private var license: LicenseModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LicenseCopy.enterLicenseKey)
                .font(.headline)
            TextField(LicenseCopy.keyPrompt, text: license.keyDraftBinding)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await submit() } }
            HStack {
                Spacer()
                Button(LicenseCopy.activate) { Task { await submit() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(license.isWorking || LicenseKey.normalize(license.keyDraft).isEmpty)
            }
            if let banner = license.banner {
                Text(banner)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func submit() async {
        await license.activate()
        if license.allowsUse, license.trialDaysLeft == nil { dismiss() }
    }
}

/// Shown in place of the funnel until this Mac has a usable license.
struct LicenseGate: View {
    @EnvironmentObject private var license: LicenseModel
    @State private var enteringLicense = false

    var body: some View {
        LockGate(
            mode: license.offersPurchase ? .purchase : .offlineLapse,
            onBuy: { Support.openBuyPage() },
            onEnterLicense: { enteringLicense = true },
            onQuit: { NSApp.terminate(nil) },
            onCheckAgain: { Task { await license.refresh() } }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ThemeBackground())
        .sheet(isPresented: $enteringLicense) {
            LicenseEntrySheet()
        }
    }
}

/// Launch note. `remaining` and the callbacks are the whole input, so a test can draw it
/// without a license, the Keychain, or the clock.
struct TrialSheet: View {
    var remaining: TimeInterval
    var onContinue: () -> Void = {}
    var onEnterLicense: () -> Void = {}
    /// When false, the ring is already at its final arc. The default animates unless Reduce Motion is on.
    var animated: Bool = true
    /// Drawn inside the ring. The app uses its own icon; tests pass Lodge's, because
    /// `NSApp.applicationIconImage` is the test runner's icon there.
    var icon: NSImage = NSApp.applicationIconImage ?? NSImage()

    var title: String { TrialLaunchNotice.title(remaining: remaining) }
    var secondary: String { TrialLaunchNotice.trialSecondary }
    var buttonTitles: [String] { TrialLaunchNotice.trialButtons }
    var heroLabel: String { TrialLaunchNotice.accessibilityLabel(remaining) }

    var body: some View {
        TrialColumn(
            title: title,
            titleColor: TrialLaunchNotice.isLastDay(remaining) ? .orange : .primary,
            secondary: secondary,
            animated: animated
        ) {
            TrialRing(remaining: remaining, accessibilityLabel: heroLabel, animated: animated, icon: icon)
        } actions: {
            Button(TrialLaunchNotice.continueTitle, action: onContinue)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .frame(maxWidth: .infinity)
            Button(TrialLaunchNotice.enterLicense, action: onEnterLicense)
                .buttonStyle(.plain)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
        }
        .onExitCommand(perform: onContinue)
    }
}

/// Post-trial lock, and the same column when a saved license can no longer be confirmed.
struct LockGate: View {
    enum Mode: Equatable {
        case purchase
        case offlineLapse
    }

    var mode: Mode = .purchase
    var onBuy: () -> Void = {}
    var onEnterLicense: () -> Void = {}
    var onQuit: () -> Void = {}
    var onCheckAgain: () -> Void = {}
    /// When false, the lock does not bounce. The default animates unless Reduce Motion is on.
    var animated: Bool = true

    var title: String {
        mode == .purchase ? TrialLaunchNotice.endedTitle : TrialLaunchNotice.confirmTitle
    }
    var secondary: String {
        mode == .purchase ? TrialLaunchNotice.endedSecondary : TrialLaunchNotice.confirmSecondary
    }
    var buttonTitles: [String] {
        mode == .purchase ? TrialLaunchNotice.lockButtons : TrialLaunchNotice.offlineButtons
    }
    var heroLabel: String {
        mode == .purchase ? TrialLaunchNotice.endedAccessibility : TrialLaunchNotice.confirmTitle
    }

    var body: some View {
        TrialColumn(title: title, titleColor: .primary, secondary: secondary, animated: animated) {
            TrialEndedRing(accessibilityLabel: heroLabel, animated: animated)
        } actions: {
            Button(buttonTitles[0], action: mode == .purchase ? onBuy : onCheckAgain)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .frame(maxWidth: .infinity)
            Button(TrialLaunchNotice.enterLicense, action: onEnterLicense)
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            Button(TrialLaunchNotice.quit, action: onQuit)
                .buttonStyle(.plain)
                .font(.callout)
                .foregroundStyle(.secondary)
                .keyboardShortcut(.cancelAction)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
        }
        .onExitCommand(perform: onQuit)
    }
}

/// Ring, title, one secondary line, then the actions. 320pt, material, no title bar of its own.
private struct TrialColumn<Hero: View, Actions: View>: View {
    var title: String
    var titleColor: Color
    var secondary: String
    var animated: Bool = true
    @ViewBuilder var hero: () -> Hero
    @ViewBuilder var actions: () -> Actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            hero()
            Text(title)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(titleColor)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .contentTransition(animated && !reduceMotion ? ContentTransition.numericText() : ContentTransition.identity)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 20)
            Text(secondary)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
            actions()
                .padding(.top, 24)
        }
        .padding(.top, 32)
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Countdown ring with the app icon inside. Trim starts at 12 o'clock and runs clockwise.
/// `animated` false, and Reduce Motion, both draw the final arc with no spring.
private struct TrialRing: View {
    var remaining: TimeInterval
    var accessibilityLabel: String
    var animated: Bool = true
    var icon: NSImage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = 0.0

    private var tint: Color {
        TrialLaunchNotice.isLastDay(remaining) ? .orange : .accentColor
    }

    /// A still (or Reduce Motion) must not wait for `onAppear`: the first frame is the final arc.
    private var shown: Double {
        animated && !reduceMotion ? drawn : TrialLaunchNotice.progress(remaining)
    }

    var body: some View {
        ZStack {
            Circle()
                .inset(by: 2.5)
                .stroke(Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            Circle()
                .inset(by: 2.5)
                .trim(from: 0, to: shown)
                .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(nsImage: icon)
                .resizable()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
        }
        .frame(width: 104, height: 104)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .onAppear {
            guard animated, !reduceMotion else { return }
            withAnimation(.spring(response: 0.8, dampingFraction: 0.85).delay(0.15)) {
                drawn = TrialLaunchNotice.progress(remaining)
            }
        }
    }
}

/// Track only, with a lock that bounces once. `animated` false, and Reduce Motion, leave it still.
private struct TrialEndedRing: View {
    var accessibilityLabel: String
    var animated: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bounce = false

    var body: some View {
        ZStack {
            Circle()
                .inset(by: 2.5)
                .stroke(Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            Image(systemName: "lock.fill")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
                .symbolEffect(.bounce, value: bounce)
        }
        .frame(width: 104, height: 104)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .onAppear {
            guard animated, !reduceMotion else { return }
            bounce = true
        }
    }
}

/// Shows the welcome note once each launch: a borderless sheet on the main window, or a
/// fixed panel when that window is not open. SwiftUI's sheet keeps a title bar on macOS 14.
enum TrialNotice {
    static let enterLicense = Notification.Name("LodgeEnterLicense")
    static var pendingLicenseEntry = false

    @MainActor static func presentIfNeeded(license: LicenseModel?) {
        guard !AppModel.isRunningUnitTests else { return }
        guard TrialNoticeWindow.current == nil else { return }
        guard let license else { return }
        guard let remaining = license.trialRemaining else { return }
        guard license.launchNoticeTitle(isDemo: AppModel.isDemo) != nil else { return }
        license.markLaunchNoticePresented()
        TrialNoticeWindow.show(remaining: remaining)
    }
}

@MainActor
private final class TrialNoticeWindow: NSObject {
    static var current: TrialNoticeWindow?
    private let panel: TrialNoticePanel
    private var dismissed = false

    static func show(remaining: TimeInterval) {
        let window = TrialNoticeWindow(remaining: remaining)
        current = window
        window.present()
    }

    private init(remaining: TimeInterval) {
        let card = TrialSheet(
            remaining: remaining,
            onContinue: { TrialNoticeWindow.current?.dismiss() },
            onEnterLicense: {
                TrialNotice.pendingLicenseEntry = true
                TrialNoticeWindow.current?.dismiss()
                DispatchQueue.main.async {
                    MainWindow.show()
                    NotificationCenter.default.post(name: TrialNotice.enterLicense, object: nil)
                }
            }
        )
        panel = TrialNoticePanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 360),
                                 styleMask: [.borderless],
                                 backing: .buffered,
                                 defer: false)
        super.init()
        panel.onCancel = { [weak self] in self?.dismiss() }
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.title = TrialLaunchNotice.title(remaining: remaining)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        install(card)
    }

    private func install(_ card: TrialSheet) {
        let host = NSHostingView(rootView: card)
        host.sizingOptions = [.intrinsicContentSize]
        host.setFrameSize(NSSize(width: 320, height: 1))
        host.layoutSubtreeIfNeeded()
        var height = host.fittingSize.height
        if !height.isFinite || height < 40 {
            height = host.intrinsicContentSize.height
        }
        if !height.isFinite || height < 40 {
            height = 360
        }
        let size = NSSize(width: 320, height: height)
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host
        panel.setContentSize(size)
    }

    private func present() {
        if let parent = MainWindow.window {
            panel.isMovableByWindowBackground = false
            parent.beginSheet(panel)
        } else {
            panel.isFloatingPanel = true
            panel.level = .modalPanel
            panel.center()
            NSApp.activate()
            panel.makeKeyAndOrderFront(nil)
        }
    }

    private func dismiss() {
        guard !dismissed else { return }
        dismissed = true
        if let parent = panel.sheetParent {
            parent.endSheet(panel)
        }
        panel.orderOut(nil)
        if TrialNoticeWindow.current === self {
            TrialNoticeWindow.current = nil
        }
    }
}

private final class TrialNoticePanel: NSPanel {
    var onCancel: (() -> Void)?

    /// A borderless panel cannot take keys unless it says so. The buttons need Return and Escape.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// Settings ▸ General ▸ License, including Deactivate for this Mac.
struct LicenseSettingsSection: View {
    @EnvironmentObject private var license: LicenseModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            Text(LicenseCopy.price)
                .fixedSize(horizontal: false, vertical: true)
            if license.canDeactivate {
                if let masked = license.maskedKey {
                    LabeledContent(LicenseCopy.thisMac, value: masked)
                }
                Button(LicenseCopy.deactivate) { Task { await license.deactivate() } }
                    .disabled(license.isWorking)
                if license.needsCheck {
                    Button(LicenseCopy.checkAgain) { Task { await license.refresh() } }
                        .disabled(license.isWorking)
                }
            } else {
                TextField(LicenseCopy.keyPrompt, text: license.keyDraftBinding)
                    .onSubmit { Task { await license.activate() } }
                Button(LicenseCopy.activate) { Task { await license.activate() } }
                    .disabled(license.isWorking || LicenseKey.normalize(license.keyDraft).isEmpty)
            }
            if license.trialDaysLeft == nil {
                Button(LicenseCopy.buy) { openURL(LodgeLicense.buyURL) }
                    .disabled(license.isWorking)
            }
            if license.isWorking {
                Text(LicenseCopy.checking)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let banner = license.banner {
                Text(banner)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text(LicenseCopy.section)
        } footer: {
            Text(license.statusLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task { await license.refresh() }
    }
}
