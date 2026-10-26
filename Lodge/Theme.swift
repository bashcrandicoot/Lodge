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
///   Default follows the system accent colour instead (system blue unless the user picked
///   another in System Settings); its `accent…` values are the system-blue fallbacks.
/// - `gauge…`: the destination's used-space bar (never red-looking, so it isn't a warning).
struct ThemePalette: Identifiable, Equatable, Sendable {
    enum ID: String, CaseIterable, Sendable {
        /// The neutral black look, and the default. Saved as "default".
        case standard = "default"
        case aurora, ocean, twilight, ember, forest

        /// A saved theme name, including ones from older versions: "comet" (the old default) and
        /// "graphite" (now part of Default) — and anything unknown — become Default.
        init(savedValue: String?) {
            self = savedValue.flatMap(ID.init(rawValue:)) ?? .standard
        }
    }

    let id: ID
    let name: String
    /// Empty for Default, which has no coloured wash.
    let wash: [UInt32]
    let button: [UInt32]
    let buttonDark: [UInt32]
    let buttonText: UInt32
    let buttonTextDark: UInt32
    let solid: UInt32
    let solidDark: UInt32
    let progress: [UInt32]
    let progressDark: [UInt32]
    let glow: UInt32
    let glowDark: UInt32
    let accentLight: UInt32
    let accentDark: UInt32
    let accentLightHighContrast: UInt32
    let accentDarkHighContrast: UInt32
    /// Text and symbols drawn on top of the accent (e.g. the active step number).
    let onAccentLight: UInt32
    let onAccentDark: UInt32
    let gaugeLight: [UInt32]
    let gaugeDark: [UInt32]

    /// A coloured gradient theme: the same button, progress and glow in Light and Dark, white text.
    init(id: ID, name: String, wash: [UInt32], button: [UInt32], solid: UInt32,
         progress: [UInt32], glow: UInt32,
         accentLight: UInt32, accentDark: UInt32,
         accentLightHighContrast: UInt32, accentDarkHighContrast: UInt32,
         gaugeLight: [UInt32], gaugeDark: [UInt32]) {
        self.init(id: id, name: name, wash: wash,
                  button: button, buttonDark: button, buttonText: 0xFFFFFF, buttonTextDark: 0xFFFFFF,
                  solid: solid, solidDark: solid, progress: progress, progressDark: progress,
                  glow: glow, glowDark: glow,
                  accentLight: accentLight, accentDark: accentDark,
                  accentLightHighContrast: accentLightHighContrast, accentDarkHighContrast: accentDarkHighContrast,
                  onAccentLight: 0xFFFFFF, onAccentDark: 0xFFFFFF,
                  gaugeLight: gaugeLight, gaugeDark: gaugeDark)
    }

    init(id: ID, name: String, wash: [UInt32],
         button: [UInt32], buttonDark: [UInt32], buttonText: UInt32, buttonTextDark: UInt32,
         solid: UInt32, solidDark: UInt32, progress: [UInt32], progressDark: [UInt32],
         glow: UInt32, glowDark: UInt32,
         accentLight: UInt32, accentDark: UInt32,
         accentLightHighContrast: UInt32, accentDarkHighContrast: UInt32,
         onAccentLight: UInt32, onAccentDark: UInt32,
         gaugeLight: [UInt32], gaugeDark: [UInt32]) {
        self.id = id; self.name = name; self.wash = wash
        self.button = button; self.buttonDark = buttonDark
        self.buttonText = buttonText; self.buttonTextDark = buttonTextDark
        self.solid = solid; self.solidDark = solidDark
        self.progress = progress; self.progressDark = progressDark
        self.glow = glow; self.glowDark = glowDark
        self.accentLight = accentLight; self.accentDark = accentDark
        self.accentLightHighContrast = accentLightHighContrast
        self.accentDarkHighContrast = accentDarkHighContrast
        self.onAccentLight = onAccentLight; self.onAccentDark = onAccentDark
        self.gaugeLight = gaugeLight; self.gaugeDark = gaugeDark
    }

    /// Default uses the system accent colour (blue by default) for controls, selection,
    /// progress and the prominent button. The colour themes keep their own gradients.
    var followsSystemAccent: Bool { id == .standard }

    /// The standard macOS system blue, used when the system accent can't be read.
    static let systemBlueLight: UInt32 = 0x007AFF
    static let systemBlueDark: UInt32 = 0x0A84FF

    /// Whether this theme paints a coloured wash behind the window.
    var hasWash: Bool { !wash.isEmpty }

    /// How strong each wash stop is, in Light and Dark.
    static let washOpacityLight: [Double] = [0.05, 0.045, 0.05, 0.07]
    static let washOpacityDark: [Double] = [0.12, 0.05, 0.03, 0.045]

    static func palette(_ id: ID) -> ThemePalette {
        all.first { $0.id == id } ?? standard
    }

    static let all: [ThemePalette] = [standard, aurora, ocean, twilight, ember, forest]

    /// The default: a neutral window (near-black in Dark, no coloured wash) with the standard
    /// system accent — blue — on toggles, sliders, selected segments, selection, progress,
    /// badges and the prominent button, like any Mac app. The values below are the
    /// system-blue fallbacks; at run time `ResolvedTheme` uses the system accent colour.
    static let standard = ThemePalette(
        id: .standard, name: "Default",
        wash: [],
        button: [0x1A88FF, 0x007AFF, 0x0071EB], buttonDark: [0x2490FF, 0x0A84FF, 0x0A7AEB],
        buttonText: 0xFFFFFF, buttonTextDark: 0xFFFFFF,
        solid: 0x0040DD, solidDark: 0x0040DD,
        progress: [0x0062CC, 0x007AFF, 0x4DA2FF], progressDark: [0x0A84FF, 0x47A3FF, 0x85C2FF],
        glow: 0x007AFF, glowDark: 0x0A84FF,
        accentLight: systemBlueLight, accentDark: systemBlueDark,
        accentLightHighContrast: 0x004FA6, accentDarkHighContrast: 0x6CB5FF,
        onAccentLight: 0xFFFFFF, onAccentDark: 0xFFFFFF,
        gaugeLight: [0x0062CC, 0x007AFF], gaugeDark: [0x0A84FF, 0x47A3FF])

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
}

// MARK: - The theme as views see it

/// A palette resolved for the current window: Light or Dark, and whether gradients are off.
/// Views read it with `@Environment(\.theme)`.
struct ResolvedTheme: Equatable {
    var palette: ThemePalette = .standard
    var isDark = false
    /// Increase Contrast or Reduce Transparency: solid colours instead of decorative gradients.
    var isPlain = false
    var isHighContrast = false
    /// The system accent colour (System Settings ▸ Appearance), resolved for this appearance.
    /// Only Default uses it; `nil` falls back to system blue.
    var systemAccent: UInt32? = nil

    /// Whether this theme is tinted with the system accent (Default).
    private var usesSystemAccent: Bool { palette.followsSystemAccent && systemAccent != nil }

    /// The tint for controls, text and selection, as 0xRRGGBB.
    var accentHex: UInt32 {
        if palette.followsSystemAccent, let systemAccent {
            // Increase Contrast: a deeper (Light) or lighter (Dark) shade, like the system does.
            guard isHighContrast else { return systemAccent }
            return isDark ? ThemeMath.mix(systemAccent, 0xFFFFFF, 0.4) : ThemeMath.mix(systemAccent, 0x000000, 0.35)
        }
        return isDark
            ? (isHighContrast ? palette.accentDarkHighContrast : palette.accentDark)
            : (isHighContrast ? palette.accentLightHighContrast : palette.accentLight)
    }

    /// The tint for controls, text and selection.
    var accent: Color { Color(hex: accentHex) }

    /// The fill for selected segments and switched-on toggles (white is drawn on top).
    var controlTint: Color { accent }

    /// Text and symbols drawn on the accent, the progress sweep or the border gradient.
    var onAccent: Color { Color(hex: isDark ? palette.onAccentDark : palette.onAccentLight) }

    var progressStops: [UInt32] {
        if usesSystemAccent {
            // The system accent, brightening along the bar.
            let base = accentHex
            return isDark ? [base, ThemeMath.mix(base, 0xFFFFFF, 0.25), ThemeMath.mix(base, 0xFFFFFF, 0.5)]
                          : [ThemeMath.mix(base, 0x000000, 0.2), base, ThemeMath.mix(base, 0xFFFFFF, 0.3)]
        }
        return isDark ? palette.progressDark : palette.progress
    }

    var progressColors: [Color] { progressStops.map(Color.init(hex:)) }

    /// Fill for prominent buttons.
    var buttonGradient: LinearGradient {
        LinearGradient(colors: buttonStops.map(Color.init(hex:)), startPoint: .leading, endPoint: .trailing)
    }

    /// Default: the system accent with the faintest light-to-dark shading, like a system button.
    var buttonStops: [UInt32] {
        if usesSystemAccent {
            let base = systemAccent ?? accentHex
            return [ThemeMath.mix(base, 0xFFFFFF, 0.1), base, ThemeMath.mix(base, 0x000000, 0.08)]
        }
        return isDark ? palette.buttonDark : palette.button
    }

    /// The label colour on prominent buttons.
    var buttonText: Color { Color(hex: isDark ? palette.buttonTextDark : palette.buttonText) }

    var solidFill: Color { Color(hex: isDark ? palette.solidDark : palette.solid) }

    /// Border and glow for the stage that needs attention, and the finished check.
    var borderGradient: LinearGradient {
        LinearGradient(colors: progressColors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var glow: Color { Color(hex: usesSystemAccent ? accentHex : (isDark ? palette.glowDark : palette.glow)) }

    /// The confetti-like burst when an offload finishes (the middle of the sweep).
    var burst: Color { Color(hex: progressStops[progressStops.count / 2]) }

    var gaugeColors: [Color] {
        if usesSystemAccent {
            let base = accentHex
            let stops = isDark ? [base, ThemeMath.mix(base, 0xFFFFFF, 0.25)] : [ThemeMath.mix(base, 0x000000, 0.2), base]
            return stops.map(Color.init(hex:))
        }
        return (isDark ? palette.gaugeDark : palette.gaugeLight).map(Color.init(hex:))
    }

    /// The background wash, or `nil` when gradients are off.
    var washColors: [Color]? {
        guard !isPlain, palette.hasWash else { return nil }
        let opacities = isDark ? ThemePalette.washOpacityDark : ThemePalette.washOpacityLight
        return zip(palette.wash, opacities).map { Color(hex: $0).opacity($1) }
    }

    /// Demo thumbnails and previews: the progress sweep, or mid greys for Default
    /// (its sweep runs to white, which would wash out the white symbol on top).
    func placeholder(_ t: Double) -> Color {
        Color(hex: ThemeMath.sweep(palette.hasWash ? progressStops : [0x3A3A3C, 0x5C5C60, 0x7E7E83], t))
    }

    /// A colour partway along the progress sweep (`t` from 0 to 1).
    func sweep(_ t: Double) -> Color {
        Color(hex: ThemeMath.sweep(progressStops, t))
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
/// (The AccentColor asset is system blue: the accent AppKit controls use when the system
/// accent is set to Multicolor, and the fallback for anything outside SwiftUI.)
struct ThemeEnvironment: ViewModifier {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    /// Bumped when the user changes the accent colour in System Settings.
    @State private var systemColorsVersion = 0

    func body(content: Content) -> some View {
        let isDark = scheme == .dark
        let theme = ResolvedTheme(
            palette: .palette(settings.themeID),
            isDark: isDark,
            isPlain: contrast == .increased || reduceTransparency || Self.forcedPlain,
            isHighContrast: contrast == .increased,
            systemAccent: systemColorsVersion >= 0 ? Self.systemAccentHex(dark: isDark) : nil)
        content
            .environment(\.theme, theme)
            .tint(theme.accent)
            .onReceive(NotificationCenter.default.publisher(for: NSColor.systemColorsDidChangeNotification)) { _ in
                systemColorsVersion += 1
            }
    }

    /// `NSColor.controlAccentColor` (the user's accent, or the app's system-blue AccentColor
    /// when it's set to Multicolor) resolved for Light or Dark. `nil` falls back to system blue.
    static func systemAccentHex(dark: Bool) -> UInt32? {
        guard let appearance = NSAppearance(named: dark ? .darkAqua : .aqua) else { return nil }
        var hex: UInt32?
        appearance.performAsCurrentDrawingAppearance {
            guard let color = NSColor.controlAccentColor.usingColorSpace(.sRGB) else { return }
            func channel(_ value: CGFloat) -> UInt32 { UInt32((max(0, min(1, value)) * 255).rounded()) }
            hex = channel(color.redComponent) << 16 | channel(color.greenComponent) << 8 | channel(color.blueComponent)
        }
        return hex
    }

    /// Screenshots: `-LodgeDemoPlainTheme YES` shows the solid fallback (Debug builds only).
    private static var forcedPlain: Bool {
        #if DEBUG
        DemoData.launchState != nil && UserDefaults.standard.bool(forKey: "LodgeDemoPlainTheme")
        #else
        false
        #endif
    }
}

extension View {
    func lodgeTheme() -> some View { modifier(ThemeEnvironment()) }

    /// Tints a segmented picker or toggle with the theme's control colour.
    func themeControlTint() -> some View { modifier(ThemeControlTint()) }
}

private struct ThemeControlTint: ViewModifier {
    @Environment(\.theme) private var theme
    func body(content: Content) -> some View { content.tint(theme.controlTint) }
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
            if theme.isDark && !theme.palette.hasWash {
                // Default in Dark: a true neutral near-black, not tinted by the desktop picture.
                Color(hex: 0x1A1A1C)
            } else {
                Color(nsColor: .windowBackgroundColor)
            }
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
            .foregroundStyle(isEnabled ? AnyShapeStyle(theme.buttonText) : AnyShapeStyle(.tertiary))
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
                        .overlay(shape.fill(theme.buttonText.opacity(hovering && !pressed ? 0.07 : 0)))
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
                    .fill(LinearGradient(colors: (palette.hasWash ? palette.wash : [0x3A3A3C, 0x0B0B0C]).map(Color.init(hex:)),
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                // A tiny button, to show the fill white text sits on.
                Capsule()
                    .fill(LinearGradient(colors: palette.buttonDark.map(Color.init(hex:)),
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
