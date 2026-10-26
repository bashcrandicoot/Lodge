import XCTest
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
