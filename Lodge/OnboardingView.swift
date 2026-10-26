import SwiftUI
import AppKit

/// How setup ends.
enum OnboardingExit: Equatable {
    /// "Skip setup": nothing changed.
    case skipped
    /// The done screen's "Open Lodge" (or closing it).
    case openLodge
    /// "Offload with …": open the main window on this card.
    case offload(CardVolume)
    /// "Open Settings".
    case openSettings
}

/// How big the setup window is. It's designed at 1280×800 pt; on a smaller screen the whole
/// design shrinks at the same 16:10 ratio (so nothing reflows), down to 75 %.
enum OnboardingLayout {
    /// The size everything in setup is laid out at.
    static let designSize = CGSize(width: 1280, height: 800)
    /// The smallest window (75 % of the design); below that the text gets too small.
    static let minimumSize = CGSize(width: 960, height: 600)
    /// On a screen too short even for the minimum, the window still never gets shorter than this.
    static let shortestHeight: CGFloat = 420
    /// Room left between the window and the edges of the screen.
    static let screenMargin: CGFloat = 12

    /// The window size for a screen whose visible area (`NSScreen.visibleFrame`: no menu bar,
    /// no Dock) is `visible`: the design size if it fits, otherwise the biggest 16:10 size that
    /// does, but never under `minimumSize`. On a screen shorter than the minimum, the height
    /// follows the screen instead (the step area scrolls; Back/Next stays at the bottom).
    static func windowSize(fitting visible: CGSize) -> CGSize {
        let ratio = designSize.width / designSize.height
        let roomWidth = max(visible.width - 2 * screenMargin, 0)
        let roomHeight = max(visible.height - 2 * screenMargin, 0)
        let width = max(minimumSize.width, min(designSize.width, roomWidth, roomHeight * ratio)).rounded(.down)
        let height = min(width / ratio, max(roomHeight, shortestHeight)).rounded(.down)
        return CGSize(width: width, height: height)
    }

    /// How much the design is shrunk in a window of `size`.
    static func scale(for size: CGSize) -> CGFloat {
        min(1, size.width / designSize.width)
    }

    /// The size the views are laid out at (in design points) before shrinking: the design
    /// width, and as much height as the window has room for.
    static func canvasSize(for size: CGSize) -> CGSize {
        let scale = scale(for: size)
        return CGSize(width: size.width / scale, height: size.height / scale)
    }
}

/// The whole setup window: splash, five steps, done. Designed at 1280×800 pt and shrunk to
/// fit smaller screens (`OnboardingLayout`).
struct OnboardingView: View {
    @ObservedObject var store: OnboardingStore
    @ObservedObject var model: AppModel
    let drives: [OnboardingDrive]
    /// The window's size; see `OnboardingLayout.windowSize(fitting:)`.
    var windowSize: CGSize = OnboardingLayout.designSize
    var finish: (OnboardingExit) -> Void

    var body: some View {
        let canvas = OnboardingLayout.canvasSize(for: windowSize)
        Group {
            switch store.step {
            case .splash:
                OnboardingSplash(start: { store.go(to: .template) }, skip: skip)
                    .environment(\.colorScheme, .dark)
            case .done:
                OnboardingDone(store: store, model: model, finish: finish)
                    .environment(\.colorScheme, .dark)
            default:
                OnboardingShell(store: store, model: model, drives: drives, skip: skip)
            }
        }
        .frame(width: canvas.width, height: canvas.height)
        .scaleEffect(OnboardingLayout.scale(for: windowSize), anchor: .topLeading)
        .frame(width: windowSize.width, height: windowSize.height, alignment: .topLeading)
        .ignoresSafeArea()
    }

    private func skip() {
        store.skip()
        finish(.skipped)
    }
}

// MARK: - 01 Splash

struct OnboardingSplash: View {
    var start: () -> Void
    var skip: () -> Void

    private var version: String {
        let info = Bundle.main.infoDictionary
        return (info?["CFBundleShortVersionString"] as? String).map { "Version \($0)" } ?? "Lodge"
    }

    var body: some View {
        ZStack {
            Image("OnboardingSplashScene")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .accessibilityHidden(true)
            LinearGradient(colors: [Color(hex: 0x0E091E).opacity(0), Color(hex: 0x0E091E).opacity(0.55)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 90)
                .frame(maxHeight: .infinity, alignment: .bottom)

            VStack(spacing: 0) {
                Image("LodgeWordmark")
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 42.7)
                    .foregroundStyle(.white)
                    .accessibilityLabel("Lodge")
                    .padding(.bottom, 34)
                (Text("From card to ").foregroundColor(.white) + Text("calm.").foregroundColor(Color(hex: 0xE88A4F)))
                    .font(.system(size: 64, weight: .bold))
                    .tracking(-1.6)
                    .overlay(alignment: .trailing) { calmGradient }
                    .padding(.bottom, 16)
                Text("Offload footage, photos and audio into the same organized, verified folder structure — every shoot, every time.")
                    .font(.system(size: 17))
                    .foregroundStyle(Color(hex: 0xC9C0DD))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .frame(maxWidth: 560)
                    .padding(.bottom, 24)
                HStack(spacing: 8) {
                    pill("One-click offload", dot: 0xF5A35C)
                    pill("Checksum-verified copies", dot: 0xC9C0DD)
                    pill("Reusable presets", dot: 0xD2683C)
                }
                .padding(.bottom, 28)
                HStack(spacing: 10) {
                    Button(action: start) {
                        Label("Get started", systemImage: "arrow.right")
                            .labelStyle(TrailingIconLabelStyle())
                            .font(.system(size: 14, weight: .medium))
                            .padding(.horizontal, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.extraLarge)
                    .keyboardShortcut(.defaultAction)
                    Button("Skip setup", action: skip)
                        .buttonStyle(GlassButtonStyle())
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 118)

            HStack {
                Text(version)
                Spacer()
                HStack(spacing: 6) {
                    Text("Press")
                    Keycap(text: "Return ↩")
                    Text("to begin")
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.62))
            .padding(.horizontal, 24)
            .padding(.bottom, 18)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    /// "calm." in the brand afterglow (#F5A35C → #D2683C), laid exactly over the plain word.
    private var calmGradient: some View {
        Text("calm.")
            .font(.system(size: 64, weight: .bold))
            .tracking(-1.6)
            .foregroundStyle(LinearGradient(colors: [Color(hex: 0xF5A35C), Color(hex: 0xD2683C)],
                                            startPoint: .leading, endPoint: .trailing))
            .accessibilityHidden(true)
    }

    private func pill(_ text: String, dot: UInt32) -> some View {
        HStack(spacing: 6) {
            Circle().fill(Color(hex: dot)).frame(width: 6, height: 6)
            Text(text)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.white.opacity(0.08), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.1)))
    }
}

/// "Next: Destination →": the icon after the text.
struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.title
            configuration.icon
        }
    }
}

// MARK: - Shell (02–06)

struct OnboardingShell: View {
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var store: OnboardingStore
    @ObservedObject var model: AppModel
    let drives: [OnboardingDrive]
    var skip: () -> Void

    var body: some View {
        let palette = OnboardingPalette(scheme)
        HStack(spacing: 0) {
            OnboardingSidebar(store: store)
                .frame(width: 256)
                .frame(maxHeight: .infinity)
                .background(palette.sidebar)
                .overlay(alignment: .trailing) { Rectangle().fill(palette.stroke).frame(width: 1) }
            VStack(spacing: 0) {
                titleBar
                ProgressTrack(fraction: Double(store.step.number ?? 0) / 5)
                header
                    .padding(.top, 28)
                    .padding(.horizontal, 44)
                // Scrolls only when the window is too short for the step (very small screens),
                // so Back/Next always stays in view.
                ViewThatFits(in: .vertical) {
                    paddedStepBody
                    ScrollView(.vertical) { paddedStepBody.padding(.bottom, 22) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                footer
            }
            .background(palette.window)
        }
    }

    private var titleBar: some View {
        Text("Set up your first preset")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .overlay(alignment: .bottom) {
                Rectangle().fill(scheme == .dark ? Color.black.opacity(0.45) : Color.black.opacity(0.1)).frame(height: 1)
            }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Step \(store.step.number ?? 1) of 5")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 26, weight: .bold))
                .tracking(-0.3)
            Text(intro)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .frame(maxWidth: 760, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var paddedStepBody: some View {
        stepBody
            .padding(.top, 22)
            .padding(.horizontal, 44)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private var stepBody: some View {
        switch store.step {
        case .template: OnboardingTemplateStep(draft: store.draft)
        case .destination:
            OnboardingDestinationStep(draft: $store.draft, drives: drives,
                                      canChooseDefault: OnboardingApplier.canChooseDefault(
                                          for: store.draft.destinationPath, in: model.destinations))
        case .folders: OnboardingFoldersStep(draft: $store.draft)
        case .naming: OnboardingNamingStep(draft: $store.draft)
        case .review: OnboardingReviewStep(store: store)
        default: EmptyView()
        }
    }

    private var title: String {
        switch store.step {
        case .template: "A preset is your offload, on rails."
        case .destination: "Where should your media live?"
        case .folders: "Build your folder tree."
        case .naming: "Naming & safety."
        case .review: "Review & save your preset."
        default: ""
        }
    }

    private var intro: String {
        switch store.step {
        case .template:
            "Tell Lodge once where media goes, how folders are built and how files are named. Every card after that lands in exactly the same place — no dragging, no guessing."
        case .destination:
            "Pick the drive and folder Lodge copies into. You can add more destinations later and switch between them in one click."
        case .folders:
            "Start from a preset, then add tokens. Inside the last folder, Lodge sorts files into one folder per type (MP4, WAV, ARW…) automatically."
        case .naming:
            "How files are renamed, how copies are verified, and what happens when Lodge finds a file it already has."
        case .review:
            "Here’s exactly what a card will look like after an offload, using sample values."
        default: ""
        }
    }

    private var footer: some View {
        let palette = OnboardingPalette(scheme)
        let isReview = store.step == .review
        return HStack(spacing: 10) {
            Button(action: skip) {
                (Text("Skip setup").font(.system(size: 13, weight: .medium)).foregroundColor(.secondary)
                 + Text(isReview ? " — discard this preset" : " — keep Lodge’s defaults").font(.system(size: 13)).foregroundColor(palette.helper))
            }
            .buttonStyle(.plain)
            Spacer()
            Button {
                store.goBack()
            } label: {
                Label("Back", systemImage: "arrow.left")
            }
            .controlSize(.large)
            .disabled(store.step == .template)
            .opacity(store.step == .template ? 0.4 : 1)
            Button {
                if isReview { store.save(into: model) } else { store.goForward() }
            } label: {
                if isReview {
                    Label("Save preset", systemImage: "checkmark")
                } else {
                    Label("Next: \(store.step.next?.sidebarTitle ?? "")", systemImage: "arrow.right")
                        .labelStyle(TrailingIconLabelStyle())
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!store.draft.canLeave(store.step))
        }
        .padding(.leading, 44)
        .padding(.trailing, 24)
        .frame(height: 60)
        .overlay(alignment: .top) { Rectangle().fill(palette.stroke).frame(height: 1) }
    }
}

/// The 3 pt progress bar under the title bar.
struct ProgressTrack: View {
    @Environment(\.colorScheme) private var scheme
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(scheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.06))
                UnevenRoundedRectangle(bottomTrailingRadius: 2, topTrailingRadius: 2)
                    .fill(Color.accentColor)
                    .frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: 3)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int(fraction * 100)) percent")
    }
}

struct OnboardingSidebar: View {
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var store: OnboardingStore

    var body: some View {
        let palette = OnboardingPalette(scheme)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                    .resizable()
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)
                Image("LodgeWordmark")
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 18.2)
                    .foregroundStyle(.primary)
                    .accessibilityLabel("Lodge")
            }
            .padding(.bottom, 24)
            Text("First preset")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.helper)
                .padding(.leading, 10)
                .padding(.bottom, 6)
            VStack(spacing: 2) {
                ForEach(OnboardingStep.numbered) { step in
                    row(step, palette: palette)
                }
            }
            Spacer()
            note
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(scheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(palette.stroke))
        }
        .padding(.top, 64)
        .padding(.horizontal, 14)
        .padding(.bottom, 16)
    }

    private func row(_ step: OnboardingStep, palette: OnboardingPalette) -> some View {
        let current = step == store.step
        let done = (step.number ?? 0) < (store.step.number ?? 0)
        return Button {
            store.go(to: step)
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    if done {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white, Color.green)
                    } else if current {
                        Circle().fill(Color.accentColor)
                        Text("\(step.number ?? 0)").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                    } else {
                        Circle().strokeBorder(palette.tertiary.opacity(0.7), lineWidth: 1)
                        Text("\(step.number ?? 0)").font(.system(size: 11)).foregroundStyle(palette.helper)
                    }
                }
                .frame(width: 20, height: 20)
                Text(step.sidebarTitle)
                    .font(.system(size: 13, weight: current ? .semibold : .regular))
                    .foregroundStyle(current || done ? Color.primary : Color.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(current ? palette.rowSelected : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .allowsHitTesting(store.canJump(to: step))
        .accessibilityValue(current ? "Current step" : done ? "Done" : "")
    }

    private var note: Text {
        switch store.step {
        case .template:
            Text("About 2 minutes. ").bold().foregroundColor(.primary)
                + Text("Everything here can be changed later in Settings ▸ Presets.")
        case .destination:
            Text("Tip: ").bold().foregroundColor(.primary)
                + Text("Lodge keeps a Finder bookmark of each favorite, so a moved or renamed folder is still found.")
        case .folders:
            Text("Tokens ").bold().foregroundColor(.primary)
                + Text("are filled in at offload time — from the card, each file’s capture date, or what you type in Lodge.")
        case .naming:
            Text("Want the camera’s names? ").bold().foregroundColor(.primary)
                + Text("Add {original} to the pattern, or turn Rename files off.")
        default:
            Text("Switch presets ").bold().foregroundColor(.primary)
                + Text("from the main window any time, and edit them in Settings ▸ Presets.")
        }
    }
}
