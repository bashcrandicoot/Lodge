import AppKit
import SwiftUI
import XCTest
@testable import Lodge

/// Off-screen stills of `TrialSheet` and `LockGate`. `ImageRenderer` draws a bitmap.
/// It does not create or show a window. `animated: false` draws the finished arc and
/// skips the lock bounce, so the still is not the first frame of the spring.
///
/// ```
/// xcodebuild test -scheme Lodge -only-testing:LodgeTests/TrialSheetSnapshotTests
/// ```
/// PNGs go to `LODGE_SNAPSHOT_DIR`, or `NSTemporaryDirectory()/lodge-snapshots`.
@MainActor
final class TrialSheetSnapshotTests: XCTestCase {
    private let day: TimeInterval = 24 * 60 * 60
    private let hour: TimeInterval = 60 * 60

    func testTrialSheetAndLockGateSnapshots() throws {
        let directory = snapshotDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let visibleBefore = NSApp.windows.filter(\.isVisible).count

        let shots = [
            trial(name: "trial-3-days", remaining: 3 * day, title: "3 days left",
                  hero: "Trial: 3 days left of 3"),
            trial(name: "trial-1-day", remaining: day, title: "1 day left",
                  hero: "Trial: 1 day left of 3"),
            trial(name: "trial-5-hours", remaining: 5 * hour, title: "5 hours left",
                  hero: "Trial: 5 hours left of 3"),
            trial(name: "trial-1-hour", remaining: hour, title: "1 hour left",
                  hero: "Trial: 1 hour left of 3"),
            trial(name: "trial-under-an-hour", remaining: 30 * 60, title: "Less than an hour left",
                  hero: "Trial: Less than an hour left of 3"),
            lock(),
            offline(),
        ]

        for shot in shots {
            XCTAssertEqual(shot.title, shot.expectedTitle, shot.name)
            XCTAssertEqual(shot.secondary, shot.expectedSecondary, shot.name)
            XCTAssertEqual(shot.buttons, shot.expectedButtons, shot.name)
            XCTAssertEqual(shot.hero, shot.expectedHero, shot.name)
            for scheme in [ColorScheme.light, ColorScheme.dark] {
                let image = try render(shot.view, scheme: scheme)
                let url = directory.appendingPathComponent("\(shot.name)-\(schemeName(scheme)).png")
                try writePNG(image, to: url)
                let bytes = try Data(contentsOf: url)
                XCTAssertGreaterThan(bytes.count, 200, url.path)
            }
        }

        XCTAssertEqual(NSApp.windows.filter(\.isVisible).count, visibleBefore,
                       "Snapshot rendering must not open a window")
    }

    private func trial(name: String, remaining: TimeInterval, title: String, hero: String) -> Shot {
        let sheet = TrialSheet(remaining: remaining, onContinue: {}, onEnterLicense: {}, animated: false)
        return Shot(name: name, title: sheet.title, expectedTitle: title,
                    secondary: sheet.secondary, expectedSecondary: TrialLaunchNotice.trialSecondary,
                    buttons: sheet.buttonTitles, expectedButtons: ["Continue", "Enter License Key…"],
                    hero: sheet.heroLabel, expectedHero: hero,
                    view: AnyView(sheet))
    }

    private func lock() -> Shot {
        let gate = LockGate(mode: .purchase, onBuy: {}, onEnterLicense: {}, onQuit: {}, onCheckAgain: {},
                            animated: false)
        return Shot(name: "lock-gate", title: gate.title, expectedTitle: "Lodge trial ended",
                    secondary: gate.secondary, expectedSecondary: "Buy once for $10. No subscription.",
                    buttons: gate.buttonTitles, expectedButtons: ["Buy Lodge", "Enter License Key…", "Quit"],
                    hero: gate.heroLabel, expectedHero: "Trial ended",
                    view: AnyView(gate))
    }

    private func offline() -> Shot {
        let gate = LockGate(mode: .offlineLapse, onBuy: {}, onEnterLicense: {}, onQuit: {}, onCheckAgain: {},
                            animated: false)
        return Shot(name: "offline-lapse", title: gate.title,
                    expectedTitle: "Lodge could not confirm this license",
                    secondary: gate.secondary,
                    expectedSecondary: "The 14-day offline period has ended.",
                    buttons: gate.buttonTitles,
                    expectedButtons: ["Check Again", "Enter License Key…", "Quit"],
                    hero: gate.heroLabel, expectedHero: "Lodge could not confirm this license",
                    view: AnyView(gate))
    }

    private func render(_ view: AnyView, scheme: ColorScheme) throws -> NSImage {
        let content = view
            .environment(\.colorScheme, scheme)
            .transaction { $0.disablesAnimations = true }
            .frame(width: 320)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        renderer.isOpaque = false
        renderer.proposedSize = ProposedViewSize(width: 320, height: nil)
        let image: NSImage = try XCTUnwrap(renderer.nsImage, "ImageRenderer produced no image")
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
        return image
    }

    private func writePNG(_ image: NSImage, to url: URL) throws {
        let properties: [NSBitmapImageRep.PropertyKey: Any] = [:]
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: properties) else {
            XCTFail("Could not encode \(url.lastPathComponent)")
            return
        }
        try png.write(to: url, options: .atomic)
    }

    private func snapshotDirectory() -> URL {
        if let raw = ProcessInfo.processInfo.environment["LODGE_SNAPSHOT_DIR"], !raw.isEmpty {
            return URL(fileURLWithPath: raw, isDirectory: true)
        }
        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("lodge-snapshots", isDirectory: true)
    }

    private func schemeName(_ scheme: ColorScheme) -> String {
        scheme == .dark ? "dark" : "light"
    }

    private struct Shot {
        var name: String
        var title: String
        var expectedTitle: String
        var secondary: String
        var expectedSecondary: String
        var buttons: [String]
        var expectedButtons: [String]
        var hero: String
        var expectedHero: String
        var view: AnyView
    }
}
