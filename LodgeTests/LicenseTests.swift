import XCTest
#if canImport(Lodge)
@testable import Lodge
#else
@testable import LodgeLicense
#endif

@MainActor
final class LicenseTests: XCTestCase {
    private let activationID = "b6724bc8-7ad9-4ca0-b143-7c896fcbb6fe"
    private let key = "LODGE-TEST-KEY-1234"
    private let day: TimeInterval = 24 * 60 * 60
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)

    /// `startTrial` leaves the Keychain empty so the controller records this clock as day one.
    /// Otherwise the trial is already over, and the license tests are looking at the gate.
    private func make(endpoint: PolarEndpoint = .live, startTrial: Bool = false) -> (LicenseController, MemoryLicenseStore, ScriptedLicenseTransport) {
        let store = MemoryLicenseStore()
        if !startTrial {
            let start = clock.addingTimeInterval(-10 * day)
            store.trial = TrialRecord(firstLaunch: start, lastSeen: clock)
        }
        let transport = ScriptedLicenseTransport()
        let client = LicenseClient(transport: transport, endpoint: endpoint)
        let controller = LicenseController(
            store: store, client: client, now: { self.clock }, machineLabel: { "Test Mac" })
        return (controller, store, transport)
    }

    private func stored(age days: Double) -> StoredLicense {
        StoredLicense(key: key, activationID: activationID, lastValidatedAt: clock.addingTimeInterval(-days * day))
    }

    private func activateOK(status: String = "granted", expires: String? = nil, id: String? = nil) -> LicenseHTTPResponse {
        json(200, """
        {"id":"\(id ?? activationID)","license_key":{"status":"\(status)","expires_at":\(jsonString(expires)),"limit_activations":3}}
        """)
    }

    private func validateOK(status: String = "granted", activation: String? = nil, expires: String? = nil) -> LicenseHTTPResponse {
        let activationJSON = activation.map { "{\"id\":\"\($0)\"}" } ?? "null"
        return json(200, """
        {"status":"\(status)","expires_at":\(jsonString(expires)),"activation":\(activationJSON),"limit_activations":3}
        """)
    }

    private func rejected(_ status: Int, _ detail: String) -> LicenseHTTPResponse {
        json(status, "{\"error\":\"PolarError\",\"detail\":\"\(detail)\"}")
    }

    private func json(_ status: Int, _ body: String) -> LicenseHTTPResponse {
        LicenseHTTPResponse(status: status, body: Data(body.utf8))
    }

    private func jsonString(_ value: String?) -> String {
        value.map { "\"\($0)\"" } ?? "null"
    }

    private func fields(_ request: LicenseRequest) throws -> [String: String] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: request.body) as? [String: String])
    }

    func testPriceIsTenDollarsWithAThreeDayTrial() {
        XCTAssertEqual(LicenseCopy.price, "Lodge is $10 once, try free 3 days. A license key works on 3 Macs and does not expire.")
        XCTAssertEqual(LodgeLicense.trialLength, 3 * day)
    }

    func testTrialDayMath() {
        let start = clock
        func record(elapsed: TimeInterval, seen: TimeInterval? = nil) -> TrialRecord {
            TrialRecord(firstLaunch: start, lastSeen: start.addingTimeInterval(seen ?? elapsed))
        }
        XCTAssertEqual(TrialPolicy.access(record: record(elapsed: 0), now: start), .active(daysLeft: 3))
        XCTAssertEqual(TrialPolicy.access(record: record(elapsed: day), now: start.addingTimeInterval(day)), .active(daysLeft: 2))
        XCTAssertEqual(TrialPolicy.access(record: record(elapsed: 2 * day), now: start.addingTimeInterval(2 * day)), .active(daysLeft: 1))
        XCTAssertEqual(TrialPolicy.access(record: record(elapsed: 3 * day - 1), now: start.addingTimeInterval(3 * day - 1)), .active(daysLeft: 1))
        XCTAssertEqual(TrialPolicy.access(record: record(elapsed: 3 * day), now: start.addingTimeInterval(3 * day)), .expired)
        XCTAssertEqual(TrialPolicy.access(record: record(elapsed: 4 * day), now: start.addingTimeInterval(4 * day)), .expired)
    }

    func testClockRollbackDoesNotExtendTheTrial() {
        let start = clock
        let recorded = TrialRecord(firstLaunch: start, lastSeen: start.addingTimeInterval(2 * day))
        let rolledBack = start.addingTimeInterval(day)
        XCTAssertEqual(TrialPolicy.access(record: recorded, now: rolledBack), .expired)
        XCTAssertEqual(TrialPolicy.advance(record: recorded, now: rolledBack), recorded)

        let beforeStart = start.addingTimeInterval(-3600)
        let opened = TrialRecord(firstLaunch: start, lastSeen: start)
        XCTAssertEqual(TrialPolicy.access(record: opened, now: beforeStart), .expired)
        XCTAssertEqual(TrialPolicy.advance(record: opened, now: beforeStart), opened)
    }

    func testTrialIsStoredBeforeTheGateAndSurvivesReinstall() {
        let (controller, store, _) = make(startTrial: true)
        XCTAssertEqual(controller.trialDaysLeft, 3)
        XCTAssertTrue(controller.allowsUse)
        XCTAssertEqual(store.trial?.firstLaunch, clock)
        XCTAssertEqual(store.trial?.lastSeen, clock)
        let started = store.trial?.firstLaunch

        clock = clock.addingTimeInterval(2 * day)
        let reinstalled = LicenseController(store: store, client: .refusing, now: { self.clock }, machineLabel: { "Test Mac" })
        XCTAssertEqual(store.trial?.firstLaunch, started)
        XCTAssertEqual(reinstalled.trialDaysLeft, 1)
        XCTAssertTrue(reinstalled.allowsUse)

        clock = started!.addingTimeInterval(3 * day)
        let ended = LicenseController(store: store, client: .refusing, now: { self.clock }, machineLabel: { "Test Mac" })
        XCTAssertEqual(store.trial?.firstLaunch, started)
        XCTAssertNil(ended.trialDaysLeft)
        XCTAssertFalse(ended.allowsUse)

        try? store.clear()
        XCTAssertNotNil(store.trial)
    }

    func testLaunchNoticeUsesDaysThenHoursAndSkipsWhenItShould() throws {
        XCTAssertEqual(TrialLaunchNotice.timeLeft(3 * day), "3 days left")
        XCTAssertEqual(TrialLaunchNotice.timeLeft(2 * day), "2 days left")
        XCTAssertEqual(TrialLaunchNotice.timeLeft(day), "1 day left")
        XCTAssertEqual(TrialLaunchNotice.timeLeft(23 * 60 * 60), "23 hours left")
        XCTAssertEqual(TrialLaunchNotice.timeLeft(60 * 60), "1 hour left")
        XCTAssertEqual(TrialLaunchNotice.timeLeft(30 * 60), "Less than an hour left")
        XCTAssertEqual(TrialLaunchNotice.title(remaining: 2 * day), TrialLaunchNotice.welcomeTitle)
        XCTAssertFalse(TrialLaunchNotice.welcomeBody.contains("Buy"))
        XCTAssertEqual(TrialLaunchNotice.continueTitle, "Continue")
        XCTAssertEqual(TrialLaunchNotice.enterLicense, "Enter License Key…")

        XCTAssertTrue(TrialLaunchNotice.shouldPresent(isTrial: true, isLicensed: false, isDemo: false, alreadyPresented: false))
        XCTAssertFalse(TrialLaunchNotice.shouldPresent(isTrial: true, isLicensed: true, isDemo: false, alreadyPresented: false))
        XCTAssertFalse(TrialLaunchNotice.shouldPresent(isTrial: true, isLicensed: false, isDemo: true, alreadyPresented: false))
        XCTAssertFalse(TrialLaunchNotice.shouldPresent(isTrial: false, isLicensed: false, isDemo: false, alreadyPresented: false))
        XCTAssertFalse(TrialLaunchNotice.shouldPresent(isTrial: true, isLicensed: false, isDemo: false, alreadyPresented: true))

        let (active, _, _) = make(startTrial: true)
        XCTAssertEqual(active.launchNoticeTitle(isDemo: false), TrialLaunchNotice.welcomeTitle)
        XCTAssertFalse(active.offersPurchase)
        XCTAssertNil(active.launchNoticeTitle(isDemo: true))
        active.markLaunchNoticePresented()
        XCTAssertNil(active.launchNoticeTitle(isDemo: false))

        let (ended, _, _) = make()
        XCTAssertNil(ended.launchNoticeTitle(isDemo: false))
        XCTAssertTrue(ended.offersPurchase)

        let store = MemoryLicenseStore()
        store.saved = stored(age: 0)
        store.trial = TrialRecord(firstLaunch: clock, lastSeen: clock)
        let licensed = LicenseController(store: store, client: .refusing, now: { self.clock }, machineLabel: { "Test Mac" })
        XCTAssertNil(licensed.launchNoticeTitle(isDemo: false))
        XCTAssertFalse(licensed.offersPurchase)

        let origin = clock
        let (_, hourStore, _) = make(startTrial: true)
        clock = origin.addingTimeInterval(2 * day + 60 * 60)
        let hours = LicenseController(store: hourStore, client: .refusing, now: { self.clock }, machineLabel: { "Test Mac" })
        XCTAssertEqual(hours.launchNoticeTitle(isDemo: false), TrialLaunchNotice.welcomeTitle)
        let hourRemaining = try XCTUnwrap(hours.trialRemaining)
        XCTAssertEqual(TrialLaunchNotice.timeLeft(hourRemaining), "23 hours left")
        XCTAssertEqual(TrialLaunchNotice.toolbar(2 * day), "Trial: 2 days left")
        XCTAssertEqual(TrialLaunchNotice.toolbar(30 * 60), "Trial: Less than an hour left")
    }

    func testTrialCountdownLabelAndMode() {
        XCTAssertEqual(TrialLaunchNotice.measure(3 * day), .days(3))
        XCTAssertEqual(TrialLaunchNotice.centerText(3 * day), "3")
        XCTAssertEqual(TrialLaunchNotice.accessibilityLabel(3 * day), "Trial: 3 days left of 3")
        XCTAssertEqual(TrialLaunchNotice.progress(3 * day), 1, accuracy: 0.0001)
        XCTAssertFalse(TrialLaunchNotice.isLastDay(3 * day))

        XCTAssertEqual(TrialLaunchNotice.measure(day), .days(1))
        XCTAssertEqual(TrialLaunchNotice.timeLeft(day), "1 day left")
        XCTAssertEqual(TrialLaunchNotice.accessibilityLabel(day), "Trial: 1 day left of 3")
        XCTAssertEqual(TrialLaunchNotice.measure(day + 1), .days(2))

        XCTAssertEqual(TrialLaunchNotice.measure(23 * 60 * 60), .hours(23))
        XCTAssertEqual(TrialLaunchNotice.centerText(23 * 60 * 60), "23")
        XCTAssertEqual(TrialLaunchNotice.accessibilityLabel(23 * 60 * 60), "Trial: 23 hours left of 3")
        XCTAssertTrue(TrialLaunchNotice.isLastDay(23 * 60 * 60))
        XCTAssertEqual(TrialLaunchNotice.measure(24 * 60 * 60 - 1), .hours(24))
        XCTAssertEqual(TrialLaunchNotice.timeLeft(24 * 60 * 60 - 1), "24 hours left")
        XCTAssertEqual(TrialLaunchNotice.measure(22 * 60 * 60 + 1), .hours(23))

        XCTAssertEqual(TrialLaunchNotice.measure(60 * 60), .hours(1))
        XCTAssertEqual(TrialLaunchNotice.timeLeft(60 * 60), "1 hour left")
        XCTAssertEqual(TrialLaunchNotice.accessibilityLabel(60 * 60), "Trial: 1 hour left of 3")

        XCTAssertEqual(TrialLaunchNotice.measure(30 * 60), .lessThanAnHour)
        XCTAssertEqual(TrialLaunchNotice.timeLeft(30 * 60), "Less than an hour left")
        XCTAssertEqual(TrialLaunchNotice.centerText(30 * 60), "<1")
        XCTAssertEqual(TrialLaunchNotice.accessibilityLabel(30 * 60), "Trial: Less than an hour left of 3")
        XCTAssertEqual(TrialLaunchNotice.progress(30 * 60), TrialLaunchNotice.minimumProgress, accuracy: 0.0001)
        XCTAssertEqual(TrialLaunchNotice.progress(1.5 * day), 0.5, accuracy: 0.0001)

        XCTAssertEqual(TrialLaunchNotice.welcomeTitle, "Welcome to Lodge")
        XCTAssertEqual(TrialLaunchNotice.welcomeBody, "After your trial, Lodge is a one-time $10 purchase. No subscription.")
        XCTAssertEqual(TrialLaunchNotice.endedTitle, "Your Lodge trial has ended")
        XCTAssertEqual(TrialLaunchNotice.endedBody, "Buy Lodge once for $10 to keep using it. No subscription.")
        XCTAssertEqual(TrialLaunchNotice.endedAccessibility, "Trial ended")
        XCTAssertEqual(TrialLaunchNotice.quit, "Quit")
    }

    func testBuyIsOfferedOnlyWhenTheTrialHasEndedWithoutALicense() {
        let (active, _, _) = make(startTrial: true)
        XCTAssertFalse(active.offersPurchase)

        let (ended, _, _) = make()
        XCTAssertTrue(ended.offersPurchase)
        XCTAssertFalse(ended.allowsUse)

        let store = MemoryLicenseStore()
        store.saved = stored(age: 20)
        let lapsed = LicenseController(store: store, client: .refusing, now: { self.clock }, machineLabel: { "Test Mac" })
        XCTAssertFalse(lapsed.allowsUse)
        XCTAssertFalse(lapsed.offersPurchase)
    }

    func testControllerTreatsABackwardClockAsExpired() {
        let (controller, store, _) = make(startTrial: true)
        let started = store.trial
        clock = clock.addingTimeInterval(-day)
        let rolled = LicenseController(store: store, client: .refusing, now: { self.clock }, machineLabel: { "Test Mac" })
        XCTAssertEqual(store.trial, started)
        XCTAssertFalse(rolled.allowsUse)
        XCTAssertNil(rolled.trialDaysLeft)
        XCTAssertTrue(controller.allowsUse)
    }

    func testProductConstants() {
        XCTAssertEqual(LodgeLicense.keyPrefix, "LODGE")
        XCTAssertEqual(LodgeLicense.activationLimit, 3)
        XCTAssertEqual(LodgeLicense.priceUSD, 10)
        XCTAssertEqual(LodgeLicense.buyURL.absoluteString, "https://buy.polar.sh/polar_cl_gS9NEtdIPJuJDXu8sdui02XetKbkwKuHgiYxi4FBkM1")
        XCTAssertEqual(LodgeLicense.revalidateAfter, 7 * day)
        XCTAssertEqual(LodgeLicense.offlineGrace, 14 * day)
        XCTAssertEqual(PolarEndpoint.live.organizationID, "ece11ea2-d5d5-4acc-ad68-68f2ba66a6f9")
        XCTAssertEqual(PolarEndpoint.sandbox.organizationID, "6501e028-3477-48a7-b174-df0c4d223b6c")
        XCTAssertEqual(PolarEndpoint.live.apiRoot.absoluteString, "https://api.polar.sh")
        XCTAssertEqual(PolarEndpoint.sandbox.apiRoot.absoluteString, "https://sandbox-api.polar.sh")
    }

    func testSandboxSwitch() {
        XCTAssertEqual(PolarEndpoint.resolve(sandboxSetting: "YES", environment: "1", allowSandbox: false), .live)
        XCTAssertEqual(PolarEndpoint.resolve(sandboxSetting: "sandbox", environment: nil, allowSandbox: false), .live)
        XCTAssertEqual(PolarEndpoint.resolve(sandboxSetting: "YES", environment: nil, allowSandbox: true), .sandbox)
        XCTAssertEqual(PolarEndpoint.resolve(sandboxSetting: "sandbox", environment: nil, allowSandbox: true), .sandbox)
        XCTAssertEqual(PolarEndpoint.resolve(sandboxSetting: "NO", environment: "1", allowSandbox: true), .sandbox)
        XCTAssertEqual(PolarEndpoint.resolve(sandboxSetting: "NO", environment: nil, allowSandbox: true), .live)
    }

    func testFreshnessBoundaries() {
        let validated = stored(age: 0)
        XCTAssertEqual(LicensePolicy.freshness(lastValidatedAt: validated.lastValidatedAt, now: clock), .current)
        let almostWeek = clock.addingTimeInterval(-LodgeLicense.revalidateAfter + 1)
        XCTAssertEqual(LicensePolicy.freshness(lastValidatedAt: almostWeek, now: clock), .current)
        let week = clock.addingTimeInterval(-LodgeLicense.revalidateAfter)
        XCTAssertEqual(LicensePolicy.freshness(lastValidatedAt: week, now: clock), .stale)
        let almostGrace = clock.addingTimeInterval(-LodgeLicense.offlineGrace + 1)
        XCTAssertEqual(LicensePolicy.freshness(lastValidatedAt: almostGrace, now: clock), .stale)
        let grace = clock.addingTimeInterval(-LodgeLicense.offlineGrace)
        XCTAssertEqual(LicensePolicy.freshness(lastValidatedAt: grace, now: clock), .graceExpired)
        let future = clock.addingTimeInterval(day)
        XCTAssertEqual(LicensePolicy.freshness(lastValidatedAt: future, now: clock), .graceExpired)
        XCTAssertFalse(LicensePolicy.allowsUse(.licensed(validated, .graceExpired)))
        XCTAssertEqual(LicensePolicy.phase(stored: nil, now: clock), .unlicensed)
        XCTAssertFalse(LicensePolicy.allowsUse(.unlicensed))
        XCTAssertTrue(LicensePolicy.allowsUse(.licensed(validated, .current)))
        XCTAssertTrue(LicensePolicy.allowsUse(.licensed(validated, .stale)))
        XCTAssertFalse(LicensePolicy.allowsUse(.licensed(validated, .graceExpired)))
    }

    func testStoredLicenseRoundTrip() throws {
        let value = stored(age: 3)
        let data = try LicenseJSON.encoder().encode(value)
        let decoded = try LicenseJSON.decoder().decode(StoredLicense.self, from: data)
        XCTAssertEqual(decoded.key, value.key)
        XCTAssertEqual(decoded.activationID, value.activationID)
        XCTAssertEqual(decoded.lastValidatedAt.timeIntervalSince1970, value.lastValidatedAt.timeIntervalSince1970, accuracy: 1)
    }

    func testPrefixIsRejectedBeforeAnyRequest() async {
        let (controller, store, transport) = make()
        controller.keyDraft = "  NOT-A-KEY  "
        await controller.activate()
        XCTAssertTrue(transport.requests.isEmpty)
        XCTAssertNil(store.saved)
        XCTAssertFalse(controller.allowsUse)
        XCTAssertEqual(controller.banner, LicenseCopy.prefixError)
    }

    func testActivatePostsPublicCustomerPortalRequest() async throws {
        let (controller, store, transport) = make()
        transport.responses = [.success(activateOK())]
        controller.keyDraft = "  \(key)  "
        await controller.activate()

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url.absoluteString, "https://api.polar.sh/v1/customer-portal/license-keys/activate")
        let body = try fields(request)
        XCTAssertEqual(body["key"], key)
        XCTAssertEqual(body["organization_id"], PolarEndpoint.live.organizationID)
        XCTAssertEqual(body["label"], "Test Mac")
        XCTAssertNil(body["activation_id"])
        XCTAssertNil(body["token"])
        XCTAssertEqual(Set(body.keys), ["key", "label", "organization_id"])

        let urlRequest = LicenseHTTP.urlRequest(for: request)
        XCTAssertEqual(urlRequest.httpMethod, "POST")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertNil(urlRequest.value(forHTTPHeaderField: "Authorization"))

        XCTAssertEqual(store.saved?.key, key)
        XCTAssertEqual(store.saved?.activationID, activationID)
        XCTAssertEqual(store.saved?.lastValidatedAt, clock)
        XCTAssertTrue(controller.allowsUse)
        XCTAssertEqual(controller.keyDraft, "")
        XCTAssertNil(controller.banner)
        XCTAssertTrue(controller.canDeactivate)
    }

    func testSandboxActivateUsesSandboxHostAndOrg() async throws {
        let (controller, _, transport) = make(endpoint: .sandbox)
        transport.responses = [.success(activateOK())]
        controller.keyDraft = key
        await controller.activate()
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url.absoluteString, "https://sandbox-api.polar.sh/v1/customer-portal/license-keys/activate")
        XCTAssertEqual(try fields(request)["organization_id"], PolarEndpoint.sandbox.organizationID)
    }

    func testActivateRejectsRevokedExpiredAndLimitWithoutStoring() async {
        let cases: [(LicenseHTTPResponse, String)] = [
            (activateOK(status: "revoked"), LicenseCopy.validateRejected),
            (activateOK(expires: "2000-01-01T00:00:00Z"), LicenseCopy.expired),
            (rejected(403, "License key activation limit reached"), LicenseCopy.activationLimitReached),
        ]
        for (response, message) in cases {
            let (controller, store, transport) = make()
            transport.responses = [.success(response)]
            controller.keyDraft = key
            await controller.activate()
            XCTAssertNil(store.saved)
            XCTAssertFalse(controller.allowsUse)
            XCTAssertEqual(controller.banner, message)
        }
    }

    func testActivateAcceptsNullOrFutureExpiry() async {
        for expires in [nil, "2099-01-01T00:00:00Z"] {
            let (controller, store, transport) = make()
            transport.responses = [.success(activateOK(expires: expires))]
            controller.keyDraft = key
            await controller.activate()
            XCTAssertEqual(store.saved?.activationID, activationID)
            XCTAssertTrue(controller.allowsUse)
        }
    }

    func testActivateNetworkErrorDoesNotStore() async {
        let (controller, store, transport) = make()
        transport.responses = [.failure(URLError(.notConnectedToInternet))]
        controller.keyDraft = key
        await controller.activate()
        XCTAssertNil(store.saved)
        XCTAssertEqual(controller.banner, LicenseCopy.unreachable)
    }

    func testCurrentLicenseSkipsTheNetwork() async {
        let (controller, store, transport) = make()
        store.saved = stored(age: 6)
        transport.responses = [.success(validateOK(activation: activationID))]
        await controller.refresh()
        XCTAssertTrue(transport.requests.isEmpty)
        XCTAssertTrue(controller.allowsUse)
        XCTAssertFalse(controller.needsCheck)
    }

    func testWeekOldLicenseValidatesAndStampsTheClock() async throws {
        let (controller, store, transport) = make()
        store.saved = stored(age: 7)
        transport.responses = [.success(validateOK(activation: activationID))]
        await controller.refresh()
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url.absoluteString, "https://api.polar.sh/v1/customer-portal/license-keys/validate")
        let body = try fields(request)
        XCTAssertEqual(body["key"], key)
        XCTAssertEqual(body["activation_id"], activationID)
        XCTAssertEqual(body["organization_id"], PolarEndpoint.live.organizationID)
        XCTAssertNil(body["label"])
        XCTAssertEqual(store.saved?.lastValidatedAt, clock)
        XCTAssertTrue(controller.allowsUse)
        XCTAssertNil(controller.banner)
    }

    func testOfflineGraceKeepsTheKeyAndTheAppUsable() async {
        let (controller, store, transport) = make()
        store.saved = stored(age: 10)
        transport.responses = [.failure(URLError(.cannotConnectToHost))]
        await controller.refresh()
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(store.saved?.activationID, activationID)
        XCTAssertTrue(controller.allowsUse)
        XCTAssertNil(controller.banner)
        XCTAssertEqual(controller.statusLine, LicenseCopy.offlineGrace)
    }

    func testGraceExpiryBlocksUseButKeepsTheKeyUntilALaterSuccess() async {
        let (controller, store, transport) = make()
        store.saved = stored(age: 14)
        transport.responses = [.failure(URLError(.notConnectedToInternet))]
        await controller.refresh()
        XCTAssertFalse(controller.allowsUse)
        XCTAssertEqual(store.saved?.key, key)
        XCTAssertEqual(controller.banner, LicenseCopy.unreachable)

        transport.responses = [.success(validateOK(activation: activationID))]
        await controller.refresh()
        XCTAssertTrue(controller.allowsUse)
        XCTAssertEqual(store.saved?.lastValidatedAt, clock)
        XCTAssertNil(controller.banner)
    }

    func testRejectedValidateClearsTheStoredLicense() async {
        let (controller, store, transport) = make()
        store.saved = stored(age: 8)
        transport.responses = [.success(rejected(403, "License key is revoked"))]
        await controller.refresh()
        XCTAssertNil(store.saved)
        XCTAssertFalse(controller.allowsUse)
        XCTAssertFalse(controller.canDeactivate)
        XCTAssertEqual(controller.banner, LicenseCopy.validateRejected)
    }

    func testMismatchedActivationClearsTheStoredLicense() async {
        let (controller, store, transport) = make()
        store.saved = stored(age: 8)
        transport.responses = [.success(validateOK(activation: "other-activation"))]
        await controller.refresh()
        XCTAssertNil(store.saved)
        XCTAssertEqual(controller.banner, LicenseCopy.validateRejected)
    }

    func testDeactivateClearsOnSuccess() async throws {
        let (controller, store, transport) = make()
        store.saved = stored(age: 1)
        controller.keyDraft = "ignored"
        _ = controller.phase
        transport.responses = [.success(LicenseHTTPResponse(status: 204, body: Data()))]
        await controller.deactivate()
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url.absoluteString, "https://api.polar.sh/v1/customer-portal/license-keys/deactivate")
        let body = try fields(request)
        XCTAssertEqual(body["activation_id"], activationID)
        XCTAssertEqual(body["organization_id"], PolarEndpoint.live.organizationID)
        XCTAssertNil(body["label"])
        XCTAssertNil(store.saved)
        XCTAssertFalse(controller.allowsUse)
        XCTAssertNil(controller.banner)
    }

    func testDeactivateNetworkErrorKeepsTheLicense() async {
        let (controller, store, transport) = make()
        store.saved = stored(age: 1)
        transport.responses = [.failure(URLError(.networkConnectionLost))]
        await controller.deactivate()
        XCTAssertEqual(store.saved?.activationID, activationID)
        XCTAssertTrue(controller.allowsUse)
        XCTAssertEqual(controller.banner, LicenseCopy.unreachable)
    }

    func testDeactivateNotFoundClearsTheLocalCopy() async {
        let (controller, store, transport) = make()
        store.saved = stored(age: 1)
        transport.responses = [.success(rejected(404, "License key not found"))]
        await controller.deactivate()
        XCTAssertNil(store.saved)
        XCTAssertEqual(controller.banner, LicenseCopy.keyNotFound)
    }

    func testKeyMaskAndPrefix() {
        XCTAssertTrue(LicenseKey.hasLodgePrefix("  lodge-abc  "))
        XCTAssertFalse(LicenseKey.hasLodgePrefix("LODGE"))
        XCTAssertFalse(LicenseKey.hasLodgePrefix("NOPE-LODGE"))
        XCTAssertEqual(LicenseKey.mask(key), "LODGE…1234")
    }
}

final class ScriptedLicenseTransport: LicenseTransport {
    var requests: [LicenseRequest] = []
    var responses: [Result<LicenseHTTPResponse, Error>] = []

    func post(_ request: LicenseRequest) async throws -> LicenseHTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else { throw URLError(.notConnectedToInternet) }
        return try responses.removeFirst().get()
    }
}
