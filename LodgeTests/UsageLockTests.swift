import XCTest
@testable import Lodge

/// After the trial, the model refuses the actions the lock gate is meant to block.
final class UsageLockTests: XCTestCase {
    func testLockedModelRefusesOffloadReoffloadFormatAndImport() {
        let model = AppModel(startWatching: false)
        model.allowsUse = { false }
        model.importPrompter.allowsUse = { false }
        let card = CardVolume(url: URL(fileURLWithPath: "/Volumes/Nowhere"), name: "Nowhere", uuid: nil)

        model.showForImport(card)
        XCTAssertNil(model.selectedCardID)
        model.startOffload()
        XCTAssertNil(model.session)
        model.setReoffloadMode(.everything)
        model.confirmForgetSelectedCardHistory()
        model.formatSelectedCard()
        model.confirmFormatSelectedCard()
        XCTAssertFalse(model.canFormatSelectedCard)
        XCTAssertEqual(model.formatState, .idle)

        let done = expectation(description: "import prompt refused")
        model.importPrompter.cardMounted(card) { shown in
            XCTAssertFalse(shown)
            done.fulfill()
        }
        wait(for: [done], timeout: 1)
        XCTAssertFalse(model.importPrompter.promptIfAllowed(card, verdict: .prompt))
    }

    func testUnlockedModelStillAcceptsAnImportSelection() {
        let model = AppModel(startWatching: false)
        XCTAssertTrue(model.allowsUse())
        let card = CardVolume(url: URL(fileURLWithPath: "/Volumes/Nowhere"), name: "Nowhere", uuid: nil)
        model.showForImport(card)
        XCTAssertEqual(model.selectedCardID, card.id)
    }
}
