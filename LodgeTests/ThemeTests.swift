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
        // Every neutral colour is a grey: no hue at all.
        let greys = neutral.button + neutral.buttonDark + neutral.progress + neutral.progressDark
            + neutral.gaugeLight + neutral.gaugeDark
            + [neutral.solid, neutral.solidDark, neutral.glow, neutral.glowDark,
               neutral.accentLight, neutral.accentDark, neutral.accentLightHighContrast, neutral.accentDarkHighContrast]
        for hex in greys {
            let r = (hex >> 16) & 0xFF, g = (hex >> 8) & 0xFF, b = hex & 0xFF
            XCTAssertLessThanOrEqual(max(r, g, b) - min(r, g, b), 6, String(hex, radix: 16))
        }
        // Dark: a near-white button with black text.
        XCTAssertEqual(neutral.buttonTextDark, 0x000000)
        XCTAssertEqual(neutral.buttonText, 0xFFFFFF)
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
            for stop in palette.button {
                XCTAssertGreaterThanOrEqual(ThemeMath.contrast(stop, palette.buttonText), 4.5,
                                            "\(palette.name) button stop \(String(stop, radix: 16))")
            }
            for stop in palette.buttonDark {
                XCTAssertGreaterThanOrEqual(ThemeMath.contrast(stop, palette.buttonTextDark), 4.5,
                                            "\(palette.name) dark button stop \(String(stop, radix: 16))")
            }
            XCTAssertGreaterThanOrEqual(ThemeMath.contrast(palette.solid, palette.buttonText), 7, "\(palette.name) solid fill")
            XCTAssertGreaterThanOrEqual(ThemeMath.contrast(palette.solidDark, palette.buttonTextDark), 7, "\(palette.name) dark solid fill")
        }
    }

    func testAccentsAreReadableInLightAndDark() {
        for palette in ThemePalette.all {
            XCTAssertGreaterThanOrEqual(ThemeMath.contrast(palette.accentLight, white), 4.5, palette.name)
            XCTAssertGreaterThanOrEqual(ThemeMath.contrast(palette.accentDark, darkBackground), 4.5, palette.name)
            // Increase Contrast: stronger still.
            XCTAssertGreaterThanOrEqual(ThemeMath.contrast(palette.accentLightHighContrast, white), 7, palette.name)
            XCTAssertGreaterThanOrEqual(ThemeMath.contrast(palette.accentDarkHighContrast, darkBackground), 7, palette.name)
        }
        // White on Default's selected segments and toggles stays readable in Dark.
        XCTAssertGreaterThanOrEqual(ThemeMath.contrast(ThemePalette.controlTintDark, white), 4.5)
        XCTAssertGreaterThanOrEqual(ThemeMath.contrast(ThemePalette.controlTintDarkHighContrast, white), 7)
        // Text drawn on the neutral accent stays readable.
        let neutral = ThemePalette.standard
        XCTAssertGreaterThanOrEqual(ThemeMath.contrast(neutral.accentLight, neutral.onAccentLight), 4.5)
        XCTAssertGreaterThanOrEqual(ThemeMath.contrast(neutral.accentDark, neutral.onAccentDark), 4.5)
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
