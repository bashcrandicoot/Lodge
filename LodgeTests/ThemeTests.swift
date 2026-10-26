import AppKit
import SwiftUI
import XCTest
@testable import Lodge

/// The themes: every one defines every token, and white text on the buttons stays readable.
final class ThemeTests: XCTestCase {
    private let white: UInt32 = 0xFFFFFF
    /// Roughly the dark window background.
    private let darkBackground: UInt32 = 0x1E1E1E

    func testEveryThemeIsListedOnceWithAllTokens() {
        XCTAssertEqual(ThemePalette.all.map(\.id), ThemePalette.ID.allCases)
        XCTAssertEqual(Set(ThemePalette.all.map(\.name)).count, ThemePalette.all.count)
        for palette in ThemePalette.all {
            XCTAssertFalse(palette.name.isEmpty)
            XCTAssertEqual(palette.wash.count, palette.id == .standard ? 0 : 4, palette.name)
            if palette.hasWash {
                XCTAssertEqual(palette.wash.count, ThemePalette.washOpacityLight.count, palette.name)
                XCTAssertEqual(palette.wash.count, ThemePalette.washOpacityDark.count, palette.name)
            }
            XCTAssertEqual(palette.button.count, 3, palette.name)
            XCTAssertEqual(palette.buttonDark.count, 3, palette.name)
            XCTAssertEqual(palette.progress.count, 3, palette.name)
            XCTAssertEqual(palette.progressDark.count, 3, palette.name)
            XCTAssertEqual(palette.gaugeLight.count, 2, palette.name)
            XCTAssertEqual(palette.gaugeDark.count, 2, palette.name)
            XCTAssertEqual(ThemePalette.palette(palette.id), palette)
        }
    }

    func testCometAndGraphiteAreGone() {
        let ids = ThemePalette.ID.allCases.map(\.rawValue)
        let names = ThemePalette.all.map { $0.name.lowercased() }
        for removed in ["comet", "graphite"] {
            XCTAssertFalse(ids.contains(removed))
            XCTAssertFalse(names.contains(removed))
            XCTAssertNil(ThemePalette.ID(rawValue: removed))
        }
        XCTAssertEqual(ThemePalette.all.map(\.name), ["Default", "Aurora", "Ocean", "Twilight", "Ember", "Forest"])
    }

    @MainActor
    func testDefaultIsNeutralBlackAndDark() {
        let settings = AppSettings(defaults: nil)
        XCTAssertEqual(settings.themeID, .standard)
        XCTAssertEqual(settings.themeID.rawValue, "default")
        XCTAssertEqual(settings.appearance, .dark)
        XCTAssertEqual(ResolvedTheme().palette, .standard)
        XCTAssertEqual(ThemePalette.all.first?.id, .standard)
        let neutral = ThemePalette.standard
        XCTAssertFalse(neutral.hasWash)
        XCTAssertNil(ResolvedTheme(palette: neutral, isDark: true).washColors)
        // The window itself stays neutral: no wash, and grey demo placeholders.
        for t in stride(from: 0.0, through: 1.0, by: 0.25) {
            let hex = ThemeMath.sweep([0x3A3A3C, 0x5C5C60, 0x7E7E83], t)
            let r = (hex >> 16) & 0xFF, g = (hex >> 8) & 0xFF, b = hex & 0xFF
            XCTAssertLessThanOrEqual(max(r, g, b) - min(r, g, b), 6, String(hex, radix: 16))
        }
        // The prominent button: white text on the accent, in Light and Dark.
        XCTAssertEqual(neutral.buttonTextDark, 0xFFFFFF)
        XCTAssertEqual(neutral.buttonText, 0xFFFFFF)
    }

    /// Is this colour clearly blue (blue channel well above red and green)?
    private func isBlue(_ hex: UInt32) -> Bool {
        let r = (hex >> 16) & 0xFF, g = (hex >> 8) & 0xFF, b = hex & 0xFF
        return b >= 0xA0 && b > r + 40 && b > g + 20
    }

    func testDefaultUsesTheSystemBlueAccent() {
        let neutral = ThemePalette.standard
        XCTAssertTrue(neutral.followsSystemAccent)
        XCTAssertEqual(neutral.accentLight, 0x007AFF, "systemBlue (Light)")
        XCTAssertEqual(neutral.accentDark, 0x0A84FF, "systemBlue (Dark)")
        // Without a readable system accent, Default falls back to system blue.
        XCTAssertEqual(ResolvedTheme(palette: neutral, isDark: true).accentHex, 0x0A84FF)
        XCTAssertEqual(ResolvedTheme(palette: neutral, isDark: false).accentHex, 0x007AFF)
        // With one, it follows it: toggles, segments, progress, glow and the button.
        let theme = ResolvedTheme(palette: neutral, isDark: true, systemAccent: 0x0A84FF)
        XCTAssertEqual(theme.accentHex, 0x0A84FF)
        XCTAssertEqual(theme.controlTint, theme.accent, "Switches and selected segments use the accent")
        XCTAssertEqual(theme.buttonStops[1], 0x0A84FF)
        for hex in theme.progressStops + theme.buttonStops + neutral.button + neutral.buttonDark
            + neutral.progress + neutral.progressDark + neutral.gaugeLight + neutral.gaugeDark
            + [neutral.solid, neutral.solidDark, neutral.glow, neutral.glowDark,
               neutral.accentLightHighContrast, neutral.accentDarkHighContrast] {
            XCTAssertTrue(isBlue(hex), String(hex, radix: 16))
        }
        let purple = ResolvedTheme(palette: neutral, isDark: false, systemAccent: 0x953D96)
        XCTAssertEqual(purple.accentHex, 0x953D96, "A user-picked accent is followed")
        // Increase Contrast: system blue gets the stronger shades.
        XCTAssertEqual(ResolvedTheme(palette: neutral, isDark: false, isHighContrast: true,
                                     systemAccent: 0x007AFF).accentHex, neutral.accentLightHighContrast)
        XCTAssertEqual(ResolvedTheme(palette: neutral, isDark: true, isHighContrast: true,
                                     systemAccent: 0x0A84FF).accentHex, neutral.accentDarkHighContrast)
    }

    func testColourThemesKeepTheirOwnAccents() {
        for palette in ThemePalette.all where palette.id != .standard {
            XCTAssertFalse(palette.followsSystemAccent, palette.name)
            let theme = ResolvedTheme(palette: palette, isDark: true, systemAccent: 0x0A84FF)
            XCTAssertEqual(theme.accentHex, palette.accentDark, palette.name)
            XCTAssertEqual(theme.progressStops, palette.progressDark, palette.name)
            XCTAssertEqual(theme.buttonStops, palette.buttonDark, palette.name)
        }
    }

    @MainActor
    func testSystemAccentIsReadableAndTheAssetIsSystemBlue() throws {
        // The resolved system accent is a real colour in both appearances.
        XCTAssertNotNil(ThemeEnvironment.systemAccentHex(dark: true))
        XCTAssertNotNil(ThemeEnvironment.systemAccentHex(dark: false))
        // The app's AccentColor asset is system blue (used when the system accent is Multicolor).
        let asset = try XCTUnwrap(NSColor(named: "AccentColor", bundle: .main))
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            var matches = false
            NSAppearance(named: name)?.performAsCurrentDrawingAppearance {
                let a = asset.usingColorSpace(.sRGB), b = NSColor.systemBlue.usingColorSpace(.sRGB)
                matches = a != nil && b != nil
                    && abs(a!.redComponent - b!.redComponent) < 0.02
                    && abs(a!.greenComponent - b!.greenComponent) < 0.02
                    && abs(a!.blueComponent - b!.blueComponent) < 0.02
            }
            XCTAssertTrue(matches, name.rawValue)
        }
    }

    @MainActor
    func testSavedCometGraphiteOrUnknownBecomeDefault() throws {
        for saved in ["comet", "graphite", "something-new"] {
            let suite = "LodgeThemeMigration-\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(saved, forKey: "theme")
            let settings = AppSettings(defaults: defaults)
            XCTAssertEqual(settings.themeID, .standard, saved)
            XCTAssertEqual(defaults.string(forKey: "theme"), "default", saved)
        }
        XCTAssertEqual(ThemePalette.ID(savedValue: "ember"), .ember)
        XCTAssertEqual(ThemePalette.ID(savedValue: nil), .standard)
    }

    @MainActor
    func testExistingInstallWithoutAChoiceGetsDark() throws {
        let suite = "LodgeAppearanceDefault-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        defaults.set("/Users/someone/Movies", forKey: "destination")   // an older install
        XCTAssertEqual(AppSettings(defaults: defaults).appearance, .dark)
        defaults.set("light", forKey: "appearance")
        XCTAssertEqual(AppSettings(defaults: defaults).appearance, .light)
    }

    func testButtonTextHasEnoughContrast() {
        for palette in ThemePalette.all {
            // Default's button is the system accent with white semibold text, exactly like the
            // system's own default buttons: at least 3:1 (WCAG for bold text and controls).
            let minimum = palette.followsSystemAccent ? 3 : 4.5
            for stop in palette.button {
                XCTAssertGreaterThanOrEqual(ThemeMath.contrast(stop, palette.buttonText), minimum,
                                            "\(palette.name) button stop \(String(stop, radix: 16))")
            }
            for stop in palette.buttonDark {
                XCTAssertGreaterThanOrEqual(ThemeMath.contrast(stop, palette.buttonTextDark), minimum,
                                            "\(palette.name) dark button stop \(String(stop, radix: 16))")
            }
            XCTAssertGreaterThanOrEqual(ThemeMath.contrast(palette.solid, palette.buttonText), 7, "\(palette.name) solid fill")
            XCTAssertGreaterThanOrEqual(ThemeMath.contrast(palette.solidDark, palette.buttonTextDark), 7, "\(palette.name) dark solid fill")
        }
    }

    func testAccentsAreReadableInLightAndDark() {
        for palette in ThemePalette.all {
            // System blue on white is 4.0:1, the same as every Mac app's controls and links (≥ 3:1).
            XCTAssertGreaterThanOrEqual(ThemeMath.contrast(palette.accentLight, white),
                                        palette.followsSystemAccent ? 3 : 4.5, palette.name)
            XCTAssertGreaterThanOrEqual(ThemeMath.contrast(palette.accentDark, darkBackground), 4.5, palette.name)
            // Increase Contrast: stronger still.
            XCTAssertGreaterThanOrEqual(ThemeMath.contrast(palette.accentLightHighContrast, white), 7, palette.name)
            XCTAssertGreaterThanOrEqual(ThemeMath.contrast(palette.accentDarkHighContrast, darkBackground), 7, palette.name)
        }
        // Default in Dark: blue on the near-black window is comfortably readable.
        let neutral = ThemePalette.standard
        XCTAssertGreaterThanOrEqual(ThemeMath.contrast(neutral.accentDark, 0x1A1A1C), 4.5)
        // White on Default's selected segments, switches and badges (system blue): ≥ 3:1.
        XCTAssertGreaterThanOrEqual(ThemeMath.contrast(neutral.accentLight, neutral.onAccentLight), 3)
        XCTAssertGreaterThanOrEqual(ThemeMath.contrast(neutral.accentDark, neutral.onAccentDark), 3)
        // Increase Contrast: white on the stronger blue in Light, and the solid button, ≥ 7:1.
        XCTAssertGreaterThanOrEqual(ThemeMath.contrast(neutral.accentLightHighContrast, white), 7)
        XCTAssertGreaterThanOrEqual(ThemeMath.contrast(neutral.solid, white), 7)
    }

    func testSweepBlendsAndClamps() {
        let stops: [UInt32] = [0xA3305E, 0xEE6A55, 0xFFA36B]
        XCTAssertEqual(ThemeMath.sweep(stops, 0), 0xA3305E)
        XCTAssertEqual(ThemeMath.sweep(stops, 0.5), 0xEE6A55)
        XCTAssertEqual(ThemeMath.sweep(stops, 1), 0xFFA36B)
        XCTAssertEqual(ThemeMath.sweep(stops, -1), 0xA3305E)
        XCTAssertEqual(ThemeMath.sweep(stops, 2), 0xFFA36B)
        XCTAssertEqual(ThemeMath.mix(0x000000, 0xFFFFFF, 0.5), 0x808080)
        XCTAssertEqual(ThemeMath.contrast(0x000000, 0xFFFFFF), 21, accuracy: 0.01)
    }

    func testPlainThemeDropsTheWash() {
        XCTAssertNil(ResolvedTheme(palette: .ocean, isDark: true, isPlain: true).washColors)
        XCTAssertEqual(ResolvedTheme(palette: .ocean, isDark: true).washColors?.count, 4)
    }

    @MainActor
    func testThemeAndAppearanceArePersisted() throws {
        let suite = "LodgeThemeTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.themeID = .ocean
        settings.appearance = .dark
        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.themeID, .ocean)
        XCTAssertEqual(reloaded.appearance, .dark)
    }
}
