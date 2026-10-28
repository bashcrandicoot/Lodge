import XCTest
@testable import Lodge

final class SupportPromptTests: XCTestCase {
    private let day: TimeInterval = 24 * 60 * 60
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func state(offloads: Int, daysSinceFirstLaunch: Double) -> (SupportPromptState, Date) {
        var state = SupportPromptState()
        state.firstLaunch = start
        state.successfulOffloads = offloads
        return (state, start.addingTimeInterval(daysSinceFirstLaunch * day))
    }

    func testNeedsFiveSuccessfulOffloads() {
        let (four, now) = state(offloads: 4, daysSinceFirstLaunch: 10)
        XCTAssertFalse(SupportPromptPolicy.isDue(four, now: now))
        let (five, _) = state(offloads: 5, daysSinceFirstLaunch: 10)
        XCTAssertTrue(SupportPromptPolicy.isDue(five, now: now))
    }

    func testNeedsThreeDaysSinceFirstLaunch() {
        let (early, earlyNow) = state(offloads: 12, daysSinceFirstLaunch: 2.9)
        XCTAssertFalse(SupportPromptPolicy.isDue(early, now: earlyNow))
        let (ready, readyNow) = state(offloads: 12, daysSinceFirstLaunch: 3)
        XCTAssertTrue(SupportPromptPolicy.isDue(ready, now: readyNow))
    }

    func testNoFirstLaunchMeansNotDue() {
        var state = SupportPromptState()
        state.successfulOffloads = 50
        XCTAssertFalse(SupportPromptPolicy.isDue(state, now: start))
    }

    func testOnlyCleanSuccessesCount() {
        var state = SupportPromptState()
        state = SupportPromptPolicy.offloadFinished(state, cleanSuccess: false)
        state = SupportPromptPolicy.offloadFinished(state, cleanSuccess: true)
        XCTAssertEqual(state.successfulOffloads, 1)
    }

    func testFirstLaunchIsRecordedOnce() {
        let first = SupportPromptPolicy.launched(SupportPromptState(), now: start)
        let later = SupportPromptPolicy.launched(first, now: start.addingTimeInterval(9 * day))
        XCTAssertEqual(later.firstLaunch, start)
    }

    func testMaybeLaterAsksOnceMoreAfterThirtyDays() {
        var (state, now) = state(offloads: 5, daysSinceFirstLaunch: 4)
        state = SupportPromptPolicy.shown(state, now: now)
        state = SupportPromptPolicy.chose(.later, state, now: now)
        XCTAssertFalse(SupportPromptPolicy.isDue(state, now: now.addingTimeInterval(29 * day)))
        let again = now.addingTimeInterval(30 * day)
        XCTAssertTrue(SupportPromptPolicy.isDue(state, now: again))
        // Shown the second time and put off again: never a third time.
        state = SupportPromptPolicy.shown(state, now: again)
        state = SupportPromptPolicy.chose(.later, state, now: again)
        XCTAssertFalse(SupportPromptPolicy.isDue(state, now: again.addingTimeInterval(365 * day)))
    }

    func testShowingWithoutAnAnswerWaitsLikeMaybeLater() {
        var (state, now) = state(offloads: 5, daysSinceFirstLaunch: 4)
        state = SupportPromptPolicy.shown(state, now: now)
        XCTAssertFalse(SupportPromptPolicy.isDue(state, now: now.addingTimeInterval(day)))
        XCTAssertTrue(SupportPromptPolicy.isDue(state, now: now.addingTimeInterval(30 * day)))
    }

    func testDontAskAgainAndSupportStopForGood() {
        for choice in [SupportPromptChoice.never, .support] {
            var (state, now) = state(offloads: 5, daysSinceFirstLaunch: 4)
            state = SupportPromptPolicy.shown(state, now: now)
            state = SupportPromptPolicy.chose(choice, state, now: now)
            XCTAssertFalse(SupportPromptPolicy.isDue(state, now: now.addingTimeInterval(400 * day)))
        }
    }

    @MainActor
    func testStorePersistsAndShowsOnlyWhenDue() throws {
        let suite = "LodgeTests.SupportPrompt.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var clock = start
        let store = SupportPromptStore(defaults: defaults, now: { clock })
        for _ in 0..<5 { store.offloadFinished(cleanSuccess: true) }
        store.showIfDue()
        XCTAssertFalse(store.isShowing, "not three days yet")

        clock = start.addingTimeInterval(3 * day)
        let reopened = SupportPromptStore(defaults: defaults, now: { clock })
        XCTAssertEqual(reopened.state.firstLaunch, start)
        XCTAssertEqual(reopened.state.successfulOffloads, 5)
        reopened.showIfDue()
        XCTAssertTrue(reopened.isShowing)
        reopened.choose(.never)
        XCTAssertFalse(reopened.isShowing)
        XCTAssertTrue(SupportPromptStore(defaults: defaults, now: { clock }).state.neverAskAgain)
    }

    @MainActor
    func testStartingAnOffloadHidesTheCard() {
        var clock = start
        let store = SupportPromptStore(defaults: nil, now: { clock })
        for _ in 0..<5 { store.offloadFinished(cleanSuccess: true) }
        clock = start.addingTimeInterval(5 * day)
        store.showIfDue()
        XCTAssertTrue(store.isShowing)
        store.hide()
        XCTAssertFalse(store.isShowing)
        store.showIfDue()
        XCTAssertFalse(store.isShowing, "waits 30 days after being shown")
    }

    func testTipJarAndSupportEmail() {
        XCTAssertEqual(Support.tipJarURL.absoluteString, "https://ko-fi.com/bashframes")
        XCTAssertEqual(Support.emailURL.absoluteString, "mailto:bashframes@gmail.com?subject=Lodge%20Support")
        XCTAssertTrue(Support.supportEmailURL.absoluteString.contains("body="))
    }

    func testDeveloperNameIsLowercase() {
        XCTAssertEqual(Support.developerName, "bashframes")
    }
}
