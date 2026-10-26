import SwiftUI
import AppKit

// MARK: - 07 Done

/// "You're all set": the preset is saved; offer the card that's plugged in (if any).
struct OnboardingDone: View {
    @ObservedObject var store: OnboardingStore
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var watcher: VolumeWatcher
    var finish: (OnboardingExit) -> Void

    init(store: OnboardingStore, model: AppModel, finish: @escaping (OnboardingExit) -> Void) {
        self.store = store
        self.model = model
        settings = model.settings
        watcher = model.watcher
        self.finish = finish
    }

    private var presetName: String { store.savedPreset?.name ?? store.draft.trimmedName }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image("OnboardingDoneScene")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: OnboardingView.size.width, height: OnboardingView.size.height)
                .accessibilityHidden(true)
            Text("Lodge")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
            HStack(alignment: .top, spacing: 0) {
                left
                    .frame(width: 600, alignment: .topLeading)
                    .padding(.top, 88)
                    .padding(.leading, 64)
                Spacer(minLength: 0)
                right
                    .frame(width: 500)
                    .padding(.top, 160)
                    .padding(.trailing, 56)
            }
        }
        .frame(width: OnboardingView.size.width, height: OnboardingView.size.height)
        .clipped()
    }

    private var left: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "checkmark")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Color.green, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.bottom, 22)
            Text("Preset saved")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: 0x7BE38E))
                .padding(.bottom, 6)
            Text("You’re all set.\nBring your media home.")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(.white)
                .lineSpacing(2)
                .padding(.bottom, 14)
            (Text(presetName).fontWeight(.semibold).foregroundColor(.white)
             + Text(" is ready. Insert a card and Lodge will copy, verify and file everything for you.")
                .foregroundColor(Color(hex: 0xC9C0DD)))
                .font(.system(size: 15))
                .lineSpacing(3)
                .frame(maxWidth: 470, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 22)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Keycap(text: "⌘ ,")
                    Text("Edit presets, destinations and naming in Settings")
                }
                HStack(spacing: 10) {
                    Toggle("Watch for new cards and offer to offload them", isOn: $settings.askToImport)
                        .toggleStyle(.switch).controlSize(.small).labelsHidden()
                    Text("Watch for new cards and offer to offload them")
                }
                HStack(spacing: 10) {
                    Toggle("Keep watching from the menu bar when the window is closed", isOn: $settings.keepRunningInMenuBar)
                        .toggleStyle(.switch).controlSize(.small).labelsHidden()
                    Text("Keep watching from the menu bar when the window is closed")
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(.white.opacity(0.78))
        }
    }

    private var right: some View {
        VStack(spacing: 14) {
            if let card = watcher.cards.first {
                cardPanel(card)
            } else {
                waiting
            }
            HStack(spacing: 10) {
                Button("Open Settings") { finish(.openSettings) }
                Text("·").foregroundStyle(.white.opacity(0.45))
                Button("Open Lodge") { finish(.openLodge) }
            }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white.opacity(0.88))
        }
    }

    private func cardPanel(_ card: CardVolume) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Circle().fill(Color.accentColor).frame(width: 8, height: 8)
                    .background(Circle().fill(Color.accentColor.opacity(0.25)).frame(width: 16, height: 16))
                Text("Card detected").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                Spacer()
            }
            HStack(spacing: 12) {
                Image(systemName: "sdcard")
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 48, height: 48)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(card.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    Text(card.url.path).font(.system(size: 12.5, design: .monospaced)).foregroundStyle(.white.opacity(0.55))
                }
            }
            HStack(spacing: 6) {
                chip("Preset", presetName)
                if let path = store.savedPreset?.destinationPath ?? store.draft.destinationPath {
                    chip("To", URL(fileURLWithPath: path).lastPathComponent)
                }
                OnboardingChip(text: "SHA-256 verified", green: true)
            }
            Button {
                finish(.offload(card))
            } label: {
                Label("Offload with \(presetName)", systemImage: "square.3.layers.3d")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.extraLarge)
            .keyboardShortcut(.defaultAction)
            Text("Opens Lodge on this card. You’ll see every file before anything is copied.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.45))
                .frame(maxWidth: .infinity)
        }
        .padding(18)
        .background(Color(hex: 0x1E1E20).opacity(0.92), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.12)))
        .shadow(color: Color(hex: 0x080414).opacity(0.55), radius: 30, y: 24)
    }

    private func chip(_ key: String, _ value: String) -> some View {
        (Text("\(key): ").foregroundColor(.white.opacity(0.5)) + Text(value).foregroundColor(.white.opacity(0.85)))
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(.white.opacity(0.08), in: Capsule())
    }

    private var waiting: some View {
        VStack(spacing: 8) {
            Image(systemName: "sdcard")
                .font(.system(size: 30))
                .foregroundStyle(Color(hex: 0x5BAEF7))
            Text("Waiting for a card")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
            Text("Insert an SD, CFexpress or other card, or a camera — Lodge picks it up and offers to offload it.")
                .font(.system(size: 12)).foregroundStyle(Color(hex: 0xC9C0DD))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 170)
        .background(Color(hex: 0x140E28).opacity(0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(.white.opacity(0.28), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
    }
}
