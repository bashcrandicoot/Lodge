import XCTest
import AppKit
@testable import Lodge

final class MenuBarItemTests: XCTestCase {
    private let a7 = CardVolume(url: URL(fileURLWithPath: "/Volumes/A7SIII"), name: "A7SIII", uuid: "1")
    private let t7 = CardVolume(url: URL(fileURLWithPath: "/Volumes/T7"), name: "T7", uuid: "2")

    func testNoCards() {
        let items = MenuBarItem.items(cards: [], isPaused: false, isBusy: false)
        XCTAssertEqual(items, [.openLodge, .divider, .cardsHeader(empty: true), .divider,
                               .pause(paused: false), .settings, .divider, .quit])
        XCTAssertEqual(items.map(\.title).filter { !$0.isEmpty },
                       ["Open Lodge", "No Cards Connected", "Pause Detection", "Settings…", "Quit Lodge"])
    }

    func testEachCardGetsAnImportItem() {
        let items = MenuBarItem.items(cards: [a7, t7], isPaused: true, isBusy: false)
        XCTAssertTrue(items.contains(.importCard(path: "/Volumes/A7SIII", name: "A7SIII", enabled: true)))
        XCTAssertTrue(items.contains(.importCard(path: "/Volumes/T7", name: "T7", enabled: true)))
        XCTAssertEqual(MenuBarItem.importCard(path: "/Volumes/T7", name: "T7", enabled: true).title, "Import from T7…")
        XCTAssertTrue(items.contains(.pause(paused: true)))
        XCTAssertEqual(MenuBarItem.pause(paused: true).title, "Resume Detection")
    }

    func testImportsWaitDuringAnOffload() {
        let items = MenuBarItem.items(cards: [a7], isPaused: false, isBusy: true)
        XCTAssertTrue(items.contains(.importCard(path: "/Volumes/A7SIII", name: "A7SIII", enabled: false)))
        XCTAssertTrue(items.contains(.offloading))
    }

    func testMenuBarIconComesFromTheAssetCatalog() throws {
        let icon = try XCTUnwrap(StatusItemController.iconImage())
        XCTAssertTrue(icon.isTemplate)
        XCTAssertEqual(icon.size, NSSize(width: 16, height: 16))
        XCTAssertNotNil(NSImage(named: "MenuBarIcon"))
        // Only the silhouette ships: the colour variant and the old separate template are gone.
        XCTAssertNil(NSImage(named: "MenuBarIconTemplate"))
        // Bitmaps only: the PDF version compiled into a plain white square.
        XCTAssertFalse(icon.representations.contains { $0 is NSPDFImageRep })
    }

    /// Draws the icon at 2x and checks its alpha: a cabin-shaped silhouette, not a solid square
    /// (which is what the broken PDF turned into) and not empty. Colour is ignored on purpose:
    /// a template image is drawn from its alpha alone.
    func testMenuBarIconIsASilhouetteNotASquare() throws {
        let image = try XCTUnwrap(StatusItemController.iconImage())
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32, bitsPerSample: 8,
                                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = NSSize(width: 16, height: 16)   // 2x
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: 16, height: 16))
        NSGraphicsContext.restoreGraphicsState()

        func alpha(_ x: Int, _ y: Int) -> CGFloat { rep.colorAt(x: x, y: y)?.alphaComponent ?? 0 }
        var covered = 0
        for y in 0..<32 { for x in 0..<32 where alpha(x, y) > 0.5 { covered += 1 } }
        let coverage = Double(covered) / Double(32 * 32)
        XCTAssertGreaterThan(coverage, 0.25, "The icon is (nearly) empty")
        XCTAssertLessThan(coverage, 0.7, "The icon fills its square: it would show as a solid block")
        // The corners are transparent (a square would fill them); the walls are solid.
        for (x, y) in [(0, 0), (31, 0), (0, 31), (31, 31), (2, 2), (29, 2)] {
            XCTAssertLessThan(alpha(x, y), 0.1, "corner \(x),\(y) isn't transparent")
        }
        XCTAssertGreaterThan(alpha(16, 22), 0.9, "the cabin's walls should be solid")
        // The roof's peak comes to a point: the top rows are much narrower than the walls.
        let wallsWidth = (0..<32).filter { alpha($0, 22) > 0.5 }.count
        let peakWidth = (0..<32).filter { alpha($0, 9) > 0.5 }.count
        XCTAssertLessThan(peakWidth, wallsWidth)
    }

    func testPromptTitle() {
        XCTAssertEqual(ImportPrompter.title(for: a7), "A7SIII card connected")
        XCTAssertEqual(ImportPrompter.title(for: t7, kind: "drive"), "T7 drive connected")
        // Don't say "card" twice.
        let sd = CardVolume(url: URL(fileURLWithPath: "/Volumes/SD Card"), name: "SD Card", uuid: nil)
        XCTAssertEqual(ImportPrompter.title(for: sd), "SD Card connected")
        let ssd = CardVolume(url: URL(fileURLWithPath: "/Volumes/Samsung SSD"), name: "Samsung SSD", uuid: nil)
        XCTAssertEqual(ImportPrompter.title(for: ssd, kind: "drive"), "Samsung SSD connected")
    }
}

@MainActor
final class ImportPrompterTests: XCTestCase {
    private func model() -> AppModel {
        AppModel(settings: AppSettings(defaults: nil), ledger: Ledger(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("lodge-prompter-tests.json")), cameras: CameraStore(fileURL: nil),
                 destinations: DestinationStore(fileURL: nil), presets: PresetStore(fileURL: nil),
                 supportPrompt: SupportPromptStore(defaults: nil), startWatching: false)
    }

    func testOnlyPromptsForConnectedCardsWhenAllowed() {
        let model = model()
        let card = CardVolume(url: URL(fileURLWithPath: "/Volumes/A7SIII"), name: "A7SIII", uuid: "1")
        let prompter = model.importPrompter
        XCTAssertFalse(prompter.usesNotifications)
        // Not mounted (as far as Lodge knows): nothing.
        XCTAssertFalse(prompter.promptIfAllowed(card, verdict: .prompt))
        model.watcher.injectDemoCards([card])
        XCTAssertFalse(prompter.promptIfAllowed(card, verdict: .skip(.notCameraMedia)))
        model.settings.askToImport = false
        XCTAssertFalse(prompter.promptIfAllowed(card, verdict: .prompt))
        model.settings.askToImport = true
        prompter.isPaused = true
        XCTAssertFalse(prompter.promptIfAllowed(card, verdict: .prompt))
        prompter.isPaused = false

        var shown: [String] = []
        prompter.presentOverride = { shown.append($0.name) }
        XCTAssertTrue(prompter.promptIfAllowed(card, verdict: .prompt))
        // A quick remount of the same card doesn't ask twice.
        XCTAssertFalse(prompter.promptIfAllowed(card, verdict: .prompt))
        XCTAssertEqual(shown, ["A7SIII"])
    }

    func testForcedPromptSkipsTheDebounce() {
        let model = model()
        let card = CardVolume(url: URL(fileURLWithPath: "/Volumes/A7SIII"), name: "A7SIII", uuid: "1")
        model.watcher.injectDemoCards([card])
        var shown = 0
        model.importPrompter.presentOverride = { _ in shown += 1 }
        XCTAssertTrue(model.importPrompter.promptIfAllowed(card, verdict: .prompt))
        XCTAssertTrue(model.importPrompter.promptIfAllowed(card, verdict: .prompt, force: true))
        XCTAssertEqual(shown, 2)
    }

    func testTestImportPromptExplainsWhyNothingShows() {
        let model = model()
        var problems: [String?] = []
        model.importPrompter.testPrompt { problems.append($0) }
        XCTAssertEqual(problems, ["No cards or drives are connected."])

        let folder = FileManager.default.temporaryDirectory   // not a card: never qualifies
        model.watcher.injectDemoCards([CardVolume(url: folder, name: "Temp", uuid: nil)])
        model.settings.askToImport = false
        model.importPrompter.testPrompt { problems.append($0) }
        XCTAssertEqual(problems.last, "“Ask to import” is off in Settings ▸ General ▸ Menu Bar.")

        model.settings.askToImport = true
        let done = expectation(description: "checked the card")
        model.importPrompter.testPrompt { problems.append($0); done.fulfill() }
        wait(for: [done], timeout: 5)
        XCTAssertTrue(problems.last??.hasPrefix("None of the connected cards") == true)
    }

    func testDontAskAddsTheCardToTheList() {
        let model = model()
        let card = CardVolume(url: URL(fileURLWithPath: "/Volumes/A7SIII"), name: "A7SIII", uuid: "1")
        model.watcher.injectDemoCards([card])
        model.importPrompter.handle(.dontAsk, cardPath: card.id)
        XCTAssertEqual(model.settings.ignoredImportIdentities, ["1"])
        model.importPrompter.handle(.ignore, cardPath: card.id)
        XCTAssertEqual(model.settings.ignoredImportCards.count, 1)
    }
}
