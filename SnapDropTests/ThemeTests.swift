import AppKit
import SwiftUI
import XCTest
@testable import SnapDrop

/// The Comet A palette: exact colours, and enough contrast for white text on the button fills.
final class ThemeTests: XCTestCase {
    private func rgb(_ color: Color) -> (Double, Double, Double) {
        let c = NSColor(color).usingColorSpace(.sRGB)!
        return (Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent))
    }

    private func luminance(_ color: Color) -> Double {
        func channel(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let (r, g, b) = rgb(color)
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    private func contrastWithWhite(_ color: Color) -> Double {
        1.05 / (luminance(color) + 0.05)
    }

    private func assertColor(_ color: Color, _ hex: UInt32, file: StaticString = #filePath, line: UInt = #line) {
        let (r, g, b) = rgb(color)
        XCTAssertEqual(Int((r * 255).rounded()), Int(hex >> 16 & 0xFF), file: file, line: line)
        XCTAssertEqual(Int((g * 255).rounded()), Int(hex >> 8 & 0xFF), file: file, line: line)
        XCTAssertEqual(Int((b * 255).rounded()), Int(hex & 0xFF), file: file, line: line)
    }

    func testPaletteMatchesTheIcon() {
        assertColor(Theme.plum, 0x3B1A3F)
        assertColor(Theme.plumLight, 0x6E3566)
        assertColor(Theme.magenta, 0xA3305E)
        assertColor(Theme.coral, 0xEE6A55)
        assertColor(Theme.orange, 0xFFA36B)
    }

    func testSweepRunsMagentaToCoralToOrange() {
        assertColor(Theme.sweep(0), 0xA3305E)
        assertColor(Theme.sweep(0.5), 0xEE6A55)
        assertColor(Theme.sweep(1), 0xFFA36B)
        assertColor(Theme.sweep(-1), 0xA3305E)   // clamped
        assertColor(Theme.sweep(2), 0xFFA36B)
    }

    func testWhiteButtonTextHasEnoughContrast() {
        // Every stop of the button gradient, and the solid fallback, keep white text readable.
        for color in [Theme.plumLight, Theme.magenta, Theme.deepCoral] {
            XCTAssertGreaterThanOrEqual(contrastWithWhite(color), 3.9)
        }
        XCTAssertGreaterThanOrEqual(contrastWithWhite(Theme.solidFill), 7)
    }
}
