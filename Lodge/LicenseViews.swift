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
        TrialCard(
            kind: license.offersPurchase ? .trialEnded : .licenseUnconfirmed,
            banner: license.banner,
            onEnterLicense: { enteringLicense = true },
            onBuy: { Support.openBuyPage() },
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

/// The launch note and the post-trial lock, in one layout.
struct TrialCard: View {
    enum Kind {
        case welcome(TimeInterval)
        case trialEnded
        case licenseUnconfirmed
    }

    var kind: Kind
    var banner: String? = nil
    var onEnterLicense: () -> Void
    var onContinue: () -> Void = {}
    var onBuy: () -> Void = {}
    var onQuit: () -> Void = {}
    var onCheckAgain: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            hero
            Text(title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 16)
            Text(label)
                .font(.callout.weight(.semibold))
                .foregroundStyle(labelColor)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
                .padding(.top, 2)
            Text(bodyText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            if let banner {
                Text(banner)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
            buttons
                .padding(.top, 20)
        }
        .padding(.top, 24)
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var title: String {
        switch kind {
        case .welcome: return TrialLaunchNotice.welcomeTitle
        case .trialEnded: return TrialLaunchNotice.endedTitle
        case .licenseUnconfirmed: return "Lodge could not confirm this license"
        }
    }

    private var label: String {
        switch kind {
        case .welcome(let remaining): return TrialLaunchNotice.timeLeft(remaining)
        case .trialEnded: return TrialLaunchNotice.endedAccessibility
        case .licenseUnconfirmed: return "Offline period ended"
        }
    }

    private var bodyText: String {
        switch kind {
        case .welcome: return TrialLaunchNotice.welcomeBody
        case .trialEnded: return TrialLaunchNotice.endedBody
        case .licenseUnconfirmed: return "The 14-day offline period has ended."
        }
    }

    private var labelColor: Color {
        switch kind {
        case .welcome(let remaining):
            return TrialLaunchNotice.isLastDay(remaining) ? .orange : .accentColor
        case .trialEnded, .licenseUnconfirmed:
            return .secondary
        }
    }

    @ViewBuilder private var hero: some View {
        HStack(spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                .resizable()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
            switch kind {
            case .welcome(let remaining):
                TrialProgressRing(remaining: remaining)
            case .trialEnded:
                TrialEndedRing(accessibilityLabel: TrialLaunchNotice.endedAccessibility)
            case .licenseUnconfirmed:
                TrialEndedRing(accessibilityLabel: "Lodge could not confirm this license")
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var buttons: some View {
        switch kind {
        case .welcome:
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button(TrialLaunchNotice.enterLicense, action: onEnterLicense)
                Button(TrialLaunchNotice.continueTitle, action: onContinue)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .background {
                Button(action: onContinue) { EmptyView() }
                    .keyboardShortcut(.cancelAction)
                    .labelsHidden()
                    .accessibilityHidden(true)
                    .frame(width: 0, height: 0)
            }
        case .trialEnded:
            HStack(spacing: 8) {
                Button(TrialLaunchNotice.quit, action: onQuit)
                    .keyboardShortcut(.cancelAction)
                Spacer(minLength: 0)
                Button(TrialLaunchNotice.enterLicense, action: onEnterLicense)
                Button(LicenseCopy.buy, action: onBuy)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        case .licenseUnconfirmed:
            HStack(spacing: 8) {
                Button(TrialLaunchNotice.quit, action: onQuit)
                    .keyboardShortcut(.cancelAction)
                Spacer(minLength: 0)
                Button(TrialLaunchNotice.enterLicense, action: onEnterLicense)
                Button(LicenseCopy.checkAgain, action: onCheckAgain)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// Countdown ring. Trim starts at 12 o'clock and runs clockwise.
private struct TrialProgressRing: View {
    var remaining: TimeInterval
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = 0.0

    private var tint: Color {
        TrialLaunchNotice.isLastDay(remaining) ? .orange : .accentColor
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: 6, lineCap: .round))
            Circle()
                .trim(from: 0, to: drawn)
                .stroke(tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(TrialLaunchNotice.centerText(remaining))
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .frame(width: 64, height: 64)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TrialLaunchNotice.accessibilityLabel(remaining))
        .onAppear {
            let target = TrialLaunchNotice.progress(remaining)
            guard !reduceMotion else {
                drawn = target
                return
            }
            withAnimation(.spring(response: 0.8, dampingFraction: 0.85).delay(0.15)) {
                drawn = target
            }
        }
    }
}

/// Track only, with a lock that bounces once. Reduce Motion leaves it still.
private struct TrialEndedRing: View {
    var accessibilityLabel: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bounce = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: 6, lineCap: .round))
            Image(systemName: "lock.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
                .symbolEffect(.bounce, value: bounce)
        }
        .frame(width: 64, height: 64)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .onAppear {
            guard !reduceMotion else { return }
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
        let card = TrialCard(
            kind: .welcome(remaining),
            onEnterLicense: {
                TrialNotice.pendingLicenseEntry = true
                TrialNoticeWindow.current?.dismiss()
                DispatchQueue.main.async {
                    MainWindow.show()
                    NotificationCenter.default.post(name: TrialNotice.enterLicense, object: nil)
                }
            },
            onContinue: { TrialNoticeWindow.current?.dismiss() }
        )
        panel = TrialNoticePanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 280),
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
        panel.title = TrialLaunchNotice.welcomeTitle
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        install(card)
    }

    private func install(_ card: TrialCard) {
        let host = NSHostingView(rootView: card)
        host.sizingOptions = [.intrinsicContentSize]
        host.setFrameSize(NSSize(width: 380, height: 1))
        host.layoutSubtreeIfNeeded()
        var height = host.fittingSize.height
        if !height.isFinite || height < 40 {
            height = host.intrinsicContentSize.height
        }
        if !height.isFinite || height < 40 {
            height = 280
        }
        let size = NSSize(width: 380, height: height)
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
