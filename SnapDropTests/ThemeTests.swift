import AppKit
import SwiftUI
import XCTest
@testable import SnapDrop

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
            XCTAssertEqual(palette.wash.count, 4, palette.name)
            XCTAssertEqual(palette.wash.count, ThemePalette.washOpacityLight.count, palette.name)
            XCTAssertEqual(palette.wash.count, ThemePalette.washOpacityDark.count, palette.name)
            XCTAssertEqual(palette.button.count, 3, palette.name)
            XCTAssertEqual(palette.progress.count, 3, palette.name)
            XCTAssertEqual(palette.gaugeLight.count, 2, palette.name)
            XCTAssertEqual(palette.gaugeDark.count, 2, palette.name)
            XCTAssertEqual(ThemePalette.palette(palette.id), palette)
        }
    }

    @MainActor
    func testCometIsTheDefaultAndMatchesTheIcon() {
        XCTAssertEqual(AppSettings(defaults: nil).themeID, .comet)
        XCTAssertEqual(AppSettings(defaults: nil).appearance, .system)
        XCTAssertEqual(ResolvedTheme().palette, .comet)
        XCTAssertEqual(ThemePalette.comet.wash, [0x6E3566, 0xA3305E, 0xEE6A55, 0xFFA36B])
        XCTAssertEqual(ThemePalette.comet.progress, [0xA3305E, 0xEE6A55, 0xFFA36B])
    }

    func testWhiteButtonTextHasEnoughContrast() {
        for palette in ThemePalette.all {
            for stop in palette.button {
                XCTAssertGreaterThanOrEqual(ThemeMath.contrast(stop, white), 4.5,
                                            "\(palette.name) button stop \(String(stop, radix: 16))")
            }
            XCTAssertGreaterThanOrEqual(ThemeMath.contrast(palette.solid, white), 7, "\(palette.name) solid fill")
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
        let suite = "SnapDropThemeTests-\(UUID().uuidString)"
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
