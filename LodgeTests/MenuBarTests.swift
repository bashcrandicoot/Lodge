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
        let color = try XCTUnwrap(StatusItemController.iconImage())
        XCTAssertFalse(color.isTemplate)
        XCTAssertEqual(color.size.height, 16, accuracy: 0.5)
        XCTAssertNotNil(NSImage(named: "MenuBarIcon"))
        let template = try XCTUnwrap(StatusItemController.iconImage(template: true))
        XCTAssertTrue(template.isTemplate)
        XCTAssertEqual(template.size, NSSize(width: 22, height: 16))
        XCTAssertNotNil(NSImage(named: "MenuBarIconTemplate"))
        // Bitmaps only: the PDF version compiled into a plain white square.
        XCTAssertFalse(color.representations.contains { $0 is NSPDFImageRep })
    }

    func testMenuBarIconIsInColor() throws {
        let image = try XCTUnwrap(StatusItemController.iconImage())
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32, bitsPerSample: 8,
                                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = NSSize(width: 16, height: 16)   // 2x
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: 16, height: 16))
        NSGraphicsContext.restoreGraphicsState()
        // The night sky (4pt in from the top left; `colorAt` counts from the top) is dark purple, not white.
        let sky = try XCTUnwrap(rep.colorAt(x: 8, y: 8)?.usingColorSpace(.deviceRGB))
        XCTAssertLessThan(sky.brightnessComponent, 0.4)
        XCTAssertGreaterThan(sky.alphaComponent, 0.9)
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
