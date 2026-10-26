import SwiftUI

// MARK: - Palettes

/// One colour theme. Every theme defines the same tokens, tuned separately for Light and Dark.
/// Colours are stored as 0xRRGGBB so they're easy to read and to test (see ThemeTests).
///
/// - `wash`: the very soft background gradient behind the main window (4 stops).
/// - `button`: the prominent button fill (3 stops), dark enough for white text (≥ 4.5:1).
/// - `solid`: the button fill when gradients are off (Increase Contrast / Reduce Transparency).
/// - `progress`: the bright sweep for thin things (progress bar, flowing dots, borders).
/// - `glow`: the shadow colour around the active stage and the finished check.
/// - `accent…`: the tint for controls, text and selection, per appearance and contrast.
/// - `gauge…`: the destination's used-space bar (never red-looking, so it isn't a warning).
struct ThemePalette: Identifiable, Equatable, Sendable {
    enum ID: String, CaseIterable, Sendable {
        case comet, aurora, ocean, twilight, ember, forest, graphite
    }

    let id: ID
    let name: String
    let wash: [UInt32]
    let button: [UInt32]
    let solid: UInt32
    let progress: [UInt32]
    let glow: UInt32
    let accentLight: UInt32
    let accentDark: UInt32
    let accentLightHighContrast: UInt32
    let accentDarkHighContrast: UInt32
    let gaugeLight: [UInt32]
    let gaugeDark: [UInt32]

    /// How strong each wash stop is, in Light and Dark.
    static let washOpacityLight: [Double] = [0.05, 0.045, 0.05, 0.07]
    static let washOpacityDark: [Double] = [0.12, 0.05, 0.03, 0.045]

    static func palette(_ id: ID) -> ThemePalette {
        all.first { $0.id == id } ?? comet
    }

    static let all: [ThemePalette] = [comet, aurora, ocean, twilight, ember, forest, graphite]

    /// The default, from the Comet A app icon: plum → magenta → coral → warm orange.
    static let comet = ThemePalette(
        id: .comet, name: "Comet",
        wash: [0x6E3566, 0xA3305E, 0xEE6A55, 0xFFA36B],
        button: [0x6E3566, 0xA3305E, 0xC8434F], solid: 0x86224E,
        progress: [0xA3305E, 0xEE6A55, 0xFFA36B], glow: 0xA3305E,
        accentLight: 0xA3305E, accentDark: 0xEE6A55,
        accentLightHighContrast: 0x7A1F4A, accentDarkHighContrast: 0xFFB3A3,
        gaugeLight: [0x6E3566, 0xA3305E], gaugeDark: [0xA3305E, 0xC2405C])

    static let aurora = ThemePalette(
        id: .aurora, name: "Aurora",
        wash: [0x0E7C7B, 0x2BB673, 0x6A4BC4, 0x9B7BF0],
        button: [0x0B6B6B, 0x1C7451, 0x6247C2], solid: 0x0B5555,
        progress: [0x14A89A, 0x3CCB7F, 0x8B6CF0], glow: 0x14A89A,
        accentLight: 0x0E7A6E, accentDark: 0x5FD3B5,
        accentLightHighContrast: 0x064F47, accentDarkHighContrast: 0x9DEBD6,
        gaugeLight: [0x0B6B6B, 0x1C7451], gaugeDark: [0x14A89A, 0x6A4BC4])

    static let ocean = ThemePalette(
        id: .ocean, name: "Ocean",
        wash: [0x0B1F4D, 0x1E4FA8, 0x2A86D6, 0x39C6E6],
        button: [0x14306E, 0x1D56B5, 0x11709C], solid: 0x12306E,
        progress: [0x1E5FD0, 0x2A96E6, 0x39CDE8], glow: 0x1E6FD8,
        accentLight: 0x1D5FC4, accentDark: 0x5AB6F0,
        accentLightHighContrast: 0x103E8A, accentDarkHighContrast: 0xA3D8FA,
        gaugeLight: [0x14306E, 0x1D56B5], gaugeDark: [0x1D6FD8, 0x2A96E6])

    static let twilight = ThemePalette(
        id: .twilight, name: "Twilight",
        wash: [0x2A1E6B, 0x5B2C9E, 0x9B3AA8, 0xE0609E],
        button: [0x3A2B8F, 0x6633A8, 0xA3347F], solid: 0x3A2B8F,
        progress: [0x6A3CC8, 0xB04AB8, 0xEE6AA8], glow: 0x8A3CC0,
        accentLight: 0x7036B8, accentDark: 0xC59CF5,
        accentLightHighContrast: 0x4C2289, accentDarkHighContrast: 0xE0CCFC,
        gaugeLight: [0x3A2B8F, 0x6633A8], gaugeDark: [0x7A4AD8, 0xB04AB8])

    static let ember = ThemePalette(
        id: .ember, name: "Ember",
        wash: [0x6B1414, 0xB3261E, 0xE8622A, 0xF5A623],
        button: [0x8A1C1C, 0xB02A17, 0xB5470E], solid: 0x7A1818,
        progress: [0xC8301E, 0xEE6A2A, 0xF7A934], glow: 0xD0401E,
        accentLight: 0xB8380F, accentDark: 0xF7934C,
        accentLightHighContrast: 0x7F240A, accentDarkHighContrast: 0xFFC79A,
        gaugeLight: [0x8A3A10, 0xB5470E], gaugeDark: [0xD8742A, 0xF09A3A])

    static let forest = ThemePalette(
        id: .forest, name: "Forest",
        wash: [0x0F3D2E, 0x1E7A50, 0x2FA866, 0xA6D65A],
        button: [0x14503A, 0x1B6B44, 0x2D7533], solid: 0x14503A,
        progress: [0x1E8A55, 0x34B86A, 0xA6D65A], glow: 0x2A9A5E,
        accentLight: 0x1E7A45, accentDark: 0x6BD488,
        accentLightHighContrast: 0x0F5230, accentDarkHighContrast: 0xA9EDB9,
        gaugeLight: [0x14503A, 0x1B6B44], gaugeDark: [0x2A9A5E, 0x5CC46E])

    static let graphite = ThemePalette(
        id: .graphite, name: "Graphite",
        wash: [0x2B2D31, 0x4A4E55, 0x7A7F87, 0xB8BCC2],
        button: [0x34373C, 0x4A4E56, 0x5B6068], solid: 0x34373C,
        progress: [0x6B7079, 0x9AA0A8, 0xC8CDD3], glow: 0x6B7079,
        accentLight: 0x4F545C, accentDark: 0xB4BAC2,
        accentLightHighContrast: 0x2F3237, accentDarkHighContrast: 0xDDE1E6,
        gaugeLight: [0x4A4E56, 0x6B7079], gaugeDark: [0x8A9098, 0xB4BAC2])
}

// MARK: - The theme as views see it

/// A palette resolved for the current window: Light or Dark, and whether gradients are off.
/// Views read it with `@Environment(\.theme)`.
struct ResolvedTheme: Equatable {
    var palette: ThemePalette = .comet
    var isDark = false
    /// Increase Contrast or Reduce Transparency: solid colours instead of decorative gradients.
    var isPlain = false
    var isHighContrast = false

    /// The tint for controls, text and selection.
    var accent: Color {
        let hex = isDark
            ? (isHighContrast ? palette.accentDarkHighContrast : palette.accentDark)
            : (isHighContrast ? palette.accentLightHighContrast : palette.accentLight)
        return Color(hex: hex)
    }

    var progressColors: [Color] { palette.progress.map(Color.init(hex:)) }

    /// Fill for prominent buttons (white text).
    var buttonGradient: LinearGradient {
        LinearGradient(colors: palette.button.map(Color.init(hex:)), startPoint: .leading, endPoint: .trailing)
    }

    var solidFill: Color { Color(hex: palette.solid) }

    /// Border and glow for the stage that needs attention, and the finished check.
    var borderGradient: LinearGradient {
        LinearGradient(colors: progressColors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var glow: Color { Color(hex: palette.glow) }

    /// The confetti-like burst when an offload finishes (the middle of the sweep).
    var burst: Color { Color(hex: palette.progress[palette.progress.count / 2]) }

    var gaugeColors: [Color] { (isDark ? palette.gaugeDark : palette.gaugeLight).map(Color.init(hex:)) }

    /// The background wash, or `nil` when gradients are off.
    var washColors: [Color]? {
        guard !isPlain else { return nil }
        let opacities = isDark ? ThemePalette.washOpacityDark : ThemePalette.washOpacityLight
        return zip(palette.wash, opacities).map { Color(hex: $0).opacity($1) }
    }

    /// A colour partway along the progress sweep (`t` from 0 to 1).
    func sweep(_ t: Double) -> Color {
        Color(hex: ThemeMath.sweep(palette.progress, t))
    }
}

/// Colour maths on 0xRRGGBB values (pure, tested).
enum ThemeMath {
    /// Linear blend of `stops` at `t` (0…1, clamped).
    static func sweep(_ stops: [UInt32], _ t: Double) -> UInt32 {
        guard stops.count > 1 else { return stops.first ?? 0 }
        let t = max(0, min(1, t)) * Double(stops.count - 1)
        let index = min(Int(t), stops.count - 2)
        return mix(stops[index], stops[index + 1], t - Double(index))
    }

    static func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 {
            let x = Double((a >> shift) & 0xFF), y = Double((b >> shift) & 0xFF)
            return UInt32((x + (y - x) * t).rounded()) << shift
        }
        return channel(16) | channel(8) | channel(0)
    }

    /// WCAG relative luminance.
    static func luminance(_ hex: UInt32) -> Double {
        func channel(_ shift: UInt32) -> Double {
            let v = Double((hex >> shift) & 0xFF) / 255
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }

    /// WCAG contrast ratio, 1…21.
    static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
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

// MARK: - Environment

struct ThemeKey: EnvironmentKey {
    static let defaultValue = ResolvedTheme()
}

extension EnvironmentValues {
    var theme: ResolvedTheme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }

    /// Gradients are off (Increase Contrast or Reduce Transparency).
    var themeIsPlain: Bool { self[ThemeKey.self].isPlain }
}

/// Resolves the chosen theme once, at the top of a window, and tints every control with it.
/// (The AccentColor asset stays Comet as the fallback for anything outside SwiftUI.)
struct ThemeEnvironment: ViewModifier {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let theme = ResolvedTheme(
            palette: .palette(settings.themeID),
            isDark: scheme == .dark,
            isPlain: contrast == .increased || reduceTransparency || Self.forcedPlain,
            isHighContrast: contrast == .increased)
        content
            .environment(\.theme, theme)
            .tint(theme.accent)
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

/// Light / Dark / follow the system (Settings ▸ Appearance).
enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

// MARK: - Views

/// A very soft wash of the theme's colours behind the main window.
/// Light and Dark are tuned separately; it's left out entirely when the theme is plain.
struct ThemeBackground: View {
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            if let colors = theme.washColors {
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// The main call to action (Offload, Done, Choose Folder): the theme gradient with white text.
/// Pressed darkens it slightly; disabled turns it into a quiet grey button.
struct ThemeProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ThemeProminentButton(configuration: configuration)
    }
}

private struct ThemeProminentButton: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.theme) private var theme
    @Environment(\.controlSize) private var controlSize
    @State private var hovering = false

    var body: some View {
        let large = controlSize == .large
        let plain = theme.isPlain
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
                    shape.fill(theme.solidFill)
                } else {
                    shape.fill(theme.buttonGradient)
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
            .shadow(color: isEnabled && !plain ? theme.glow.opacity(pressed ? 0.12 : 0.28) : .clear, radius: 4, y: 1)
            .contentShape(shape)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: pressed)
    }
}

extension ButtonStyle where Self == ThemeProminentButtonStyle {
    static var themeProminent: ThemeProminentButtonStyle { ThemeProminentButtonStyle() }
}

/// A small chip showing a theme's colours (Settings ▸ Appearance).
struct ThemeSwatch: View {
    let palette: ThemePalette
    let isSelected: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: palette.wash.map(Color.init(hex:)),
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                // A tiny button, to show the fill white text sits on.
                Capsule()
                    .fill(LinearGradient(colors: palette.button.map(Color.init(hex:)),
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: 34, height: 12)
                    .overlay(Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 0.5))
                    .offset(y: 12)
            }
            .frame(width: 62, height: 44)
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? theme.accent : Color.primary.opacity(0.12),
                                  lineWidth: isSelected ? 2.5 : 1)
                    .padding(isSelected ? -3.5 : 0)
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, theme.accent)
                        .font(.system(size: 14))
                        .offset(x: 7, y: -7)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            Text(palette.name)
                .font(.caption)
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .padding(.top, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(palette.name) theme")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
