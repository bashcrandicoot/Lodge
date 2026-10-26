import SwiftUI

/// SnapDrop's colours, taken from the Comet A app icon: plum → magenta → coral → warm orange.
///
/// Everything that used to be plain accent blue reads from here, so the palette is defined once.
/// Plain tints (selection, pills, links) use `accent`, which is the AccentColor asset:
/// magenta in Light, coral in Dark, with deeper or brighter versions for Increase Contrast.
/// Gradients are only decoration; with Increase Contrast or Reduce Transparency they fall back
/// to solid colours.
enum Theme {
    // The icon's stops (sRGB).
    static let plum = Color(hex: 0x3B1A3F)
    static let plumLight = Color(hex: 0x6E3566)
    static let magenta = Color(hex: 0xA3305E)
    static let coral = Color(hex: 0xEE6A55)
    static let orange = Color(hex: 0xFFA36B)
    /// A deeper coral for fills under white text (white on it is 4:1; on `coral` only 3:1).
    static let deepCoral = Color(hex: 0xD9534F)
    /// The solid fill used for buttons when gradients are turned off (white on it is 8.9:1).
    static let solidFill = Color(hex: 0x86224E)

    /// The tint for controls, text and selection (the AccentColor asset).
    static var accent: Color { .accentColor }

    /// The full sweep, for thin things like the progress bar and flowing dots.
    static var sweepColors: [Color] { [magenta, coral, orange] }

    /// Fill for prominent buttons: dark enough everywhere for white text (≥ 4:1).
    static var buttonGradient: LinearGradient {
        LinearGradient(colors: [plumLight, magenta, deepCoral],
                       startPoint: .leading, endPoint: .trailing)
    }

    /// Fill for the destination's used-space gauge: the cooler end of the palette, so it never
    /// reads as the red "not enough space" warning.
    static func gaugeColors(dark: Bool) -> [Color] {
        dark ? [magenta, Color(hex: 0xC2405C)] : [plumLight, magenta]
    }

    /// Border and glow for the stage that needs attention.
    static var borderGradient: LinearGradient {
        LinearGradient(colors: [magenta, coral, orange],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// A colour partway along the magenta → coral → orange sweep (`t` from 0 to 1).
    static func sweep(_ t: Double) -> Color {
        let t = max(0, min(1, t))
        return t < 0.5
            ? mix(magenta, coral, t * 2)
            : mix(coral, orange, (t - 0.5) * 2)
    }

    private static func mix(_ a: Color, _ b: Color, _ t: Double) -> Color {
        let ca = NSColor(a).usingColorSpace(.sRGB) ?? .black
        let cb = NSColor(b).usingColorSpace(.sRGB) ?? .black
        return Color(.sRGB,
                     red: ca.redComponent + (cb.redComponent - ca.redComponent) * t,
                     green: ca.greenComponent + (cb.greenComponent - ca.greenComponent) * t,
                     blue: ca.blueComponent + (cb.blueComponent - ca.blueComponent) * t)
    }
}

extension Color {
    /// A colour from a 0xRRGGBB value.
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// True when the user has asked for Increase Contrast or Reduce Transparency,
/// so decorative gradients should be replaced with solid colours.
struct PlainThemeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var themeIsPlain: Bool {
        get { self[PlainThemeKey.self] }
        set { self[PlainThemeKey.self] = newValue }
    }
}

/// Works out `themeIsPlain` once, at the top of a window.
struct ThemeEnvironment: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content.environment(\.themeIsPlain, contrast == .increased || reduceTransparency || Self.forcedPlain)
    }

    /// Screenshots: `-SnapDropDemoPlainTheme YES` shows the solid fallback (Debug builds only).
    private static var forcedPlain: Bool {
        #if DEBUG
        DemoData.launchState != nil && UserDefaults.standard.bool(forKey: "SnapDropDemoPlainTheme")
        #else
        false
        #endif
    }
}

extension View {
    func snapDropTheme() -> some View { modifier(ThemeEnvironment()) }
}

/// A very soft wash of the icon's colours behind the main window.
/// Light and Dark are tuned separately; it's left out entirely when the theme is plain.
struct ThemeBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.themeIsPlain) private var plain

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            if !plain {
                let dark = scheme == .dark
                LinearGradient(colors: [Theme.plumLight.opacity(dark ? 0.12 : 0.05),
                                        Theme.magenta.opacity(dark ? 0.05 : 0.045),
                                        Theme.coral.opacity(dark ? 0.03 : 0.05),
                                        Theme.orange.opacity(dark ? 0.045 : 0.07)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// The main call to action (Offload, Done, Choose Folder): the icon gradient with white text.
/// Pressed darkens it slightly; disabled turns it into a quiet grey button.
struct ThemeProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ThemeProminentButton(configuration: configuration)
    }
}

private struct ThemeProminentButton: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.themeIsPlain) private var plain
    @Environment(\.controlSize) private var controlSize
    @State private var hovering = false

    var body: some View {
        let large = controlSize == .large
        let shape = RoundedRectangle(cornerRadius: large ? 8 : 6, style: .continuous)
        let pressed = configuration.isPressed && isEnabled
        configuration.label
            .font(large ? .body.weight(.semibold) : .callout.weight(.semibold))
            .foregroundStyle(isEnabled ? AnyShapeStyle(Color.white) : AnyShapeStyle(.tertiary))
            .padding(.horizontal, large ? 14 : 10)
            .padding(.vertical, large ? 6 : 3)
            .frame(minHeight: large ? 30 : 22)
            .background {
                if !isEnabled {
                    shape.fill(Color.primary.opacity(0.08))
                } else if plain {
                    shape.fill(Theme.solidFill)
                } else {
                    shape.fill(Theme.buttonGradient)
                        .overlay(shape.fill(Color.white.opacity(hovering && !pressed ? 0.07 : 0)))
                }
            }
            .overlay {
                if isEnabled && !plain {
                    // A hairline highlight along the top edge, like a system prominent button.
                    shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.04)],
                                                      startPoint: .top, endPoint: .bottom),
                                       lineWidth: 0.5)
                } else if isEnabled {
                    shape.strokeBorder(Color.primary.opacity(0.6), lineWidth: 1)
                }
            }
            .overlay {
                if pressed { shape.fill(Color.black.opacity(0.16)) }
            }
            .shadow(color: isEnabled && !plain ? Theme.magenta.opacity(pressed ? 0.12 : 0.28) : .clear, radius: 4, y: 1)
            .contentShape(shape)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: pressed)
    }
}

extension ButtonStyle where Self == ThemeProminentButtonStyle {
    static var themeProminent: ThemeProminentButtonStyle { ThemeProminentButtonStyle() }
}
