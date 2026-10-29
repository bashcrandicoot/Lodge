import XCTest
@testable import Lodge

final class BugReportTests: XCTestCase {
    private let info = BugReport.SystemInfo(appVersion: "1.0.4", build: "5", macOSVersion: "27.0 (26A428)",
                                            macModel: "Mac15,6", chip: "Apple M3 Pro")

    // MARK: Subject and body

    func testSubjectNamesVersionAndBuild() {
        XCTAssertEqual(BugReport.subject(info), "Lodge bug report (version 1.0.4 build 5)")
    }

    func testBodyHasPromptAndSystemDetails() {
        let body = BugReport.body(info, attachments: ["Lodge log.txt"])
        XCTAssertTrue(body.hasPrefix("What happened?\n"))
        XCTAssertTrue(body.contains("Lodge 1.0.4 (build 5)"))
        XCTAssertTrue(body.contains("macOS 27.0 (26A428)"))
        XCTAssertTrue(body.contains("Mac: Mac15,6, Apple M3 Pro"))
        XCTAssertTrue(body.contains("Attached: Lodge log.txt"))
        XCTAssertFalse(body.contains("Crash:"))
        XCTAssertFalse(body.contains("recent log:"), "The log is an attachment, not in the body")
    }

    func testCrashBodyNamesTheReport() {
        let body = BugReport.body(info, attachments: ["Lodge log.txt", "Lodge-2026-10-27-014949.txt"],
                                  crashReportName: "Lodge-2026-10-27-014949.ips")
        XCTAssertTrue(body.contains("Lodge quit unexpectedly"))
        XCTAssertTrue(body.contains("Crash: Lodge-2026-10-27-014949.ips"))
        XCTAssertTrue(body.contains("Attached: Lodge log.txt, Lodge-2026-10-27-014949.txt"))
    }

    func testMailtoBodyCarriesTheNewestLogLinesWithinTheLimit() {
        let log = (1...500).map { "line \($0) " + String(repeating: "x", count: 40) }
        let body = BugReport.mailtoBody(info, crashReportName: nil, log: log)
        XCTAssertLessThanOrEqual(body.count, BugReport.mailtoBodyLimit)
        XCTAssertTrue(body.contains("line 500 "), "Newest lines are kept")
        XCTAssertFalse(body.contains("line 1 "), "Oldest lines go first")
        XCTAssertTrue(BugReport.mailtoBody(info, crashReportName: nil, log: []).contains("(nothing logged recently)"))
        XCTAssertTrue(BugReport.mailtoBody(info, crashReportName: "Lodge-x.ips", log: ["a"])
            .contains("couldn’t be attached"))
    }

    func testTailKeepsTheLastLines() {
        XCTAssertEqual(BugReport.tail(["a", "b", "c"], limit: 2), ["b", "c"])
        XCTAssertEqual(BugReport.tail(["a"], limit: 200), ["a"])
        XCTAssertEqual(BugReport.tail(["a"], limit: 0), [])
        XCTAssertEqual(BugReport.tail((1...300).map(String.init)).count, 200)
    }

    // MARK: Privacy

    func testPathsAreRedacted() {
        func redact(_ s: String) -> String { BugReport.redactingPaths(s, homeDirectory: "/Users/sam") }
        XCTAssertEqual(redact("Card inserted: /Volumes/SD Card, new mount true"),
                       "Card inserted: <path>, new mount true")
        XCTAssertEqual(redact("Read /Volumes/A7S III/DCIM/C0001.MP4: removable"), "Read <path>: removable")
        XCTAssertEqual(redact("Saved to /Users/sam/Movies/Client X/clip.mov"), "Saved to <path>")
        XCTAssertEqual(redact("\"procPath\" : \"/private/tmp/abc/Lodge.app\","), "\"procPath\" : \"<path>\",")
        XCTAssertEqual(redact("Notifications at launch: authorization authorized"),
                       "Notifications at launch: authorization authorized")
        XCTAssertEqual(redact("/System/Library/Frameworks/AppKit.framework"),
                       "/System/Library/Frameworks/AppKit.framework", "System paths help and name nothing private")
    }

    // MARK: New-crash detection

    private func file(_ name: String, _ seconds: TimeInterval) -> CrashReports.File {
        CrashReports.File(url: URL(fileURLWithPath: "/tmp/\(name)"), date: Date(timeIntervalSince1970: seconds))
    }

    func testOnlyLodgeReportsCount() {
        XCTAssertTrue(CrashReports.isLodgeReport("Lodge-2026-10-26-152019.ips"))
        XCTAssertTrue(CrashReports.isLodgeReport("Lodge_2026-10-26-152019_Mac.crash"))
        XCTAssertFalse(CrashReports.isLodgeReport("LodgeHelper-2026-10-26-152019.ips"))
        XCTAssertFalse(CrashReports.isLodgeReport("Loadout-2026-10-26-152019.ips"))
        XCTAssertFalse(CrashReports.isLodgeReport("Lodge-2026-10-26-152019.diag"))
    }

    func testNewestUnseenReportIsOffered() {
        let files = [file("Lodge-a.ips", 100), file("Lodge-b.ips", 300), file("Lodge-c.ips", 200),
                     file("Finder-z.ips", 900)]
        XCTAssertEqual(CrashReports.newReport(in: files, lastSeen: Date(timeIntervalSince1970: 150))?.name,
                       "Lodge-b.ips")
        XCTAssertNil(CrashReports.newReport(in: files, lastSeen: Date(timeIntervalSince1970: 300)),
                     "Already seen: no nagging")
        XCTAssertNil(CrashReports.newReport(in: [], lastSeen: Date(timeIntervalSince1970: 0)))
    }

    func testFirstLaunchOffersNothingButRemembersTheNewest() {
        let files = [file("Lodge-a.ips", 100), file("Lodge-b.ips", 300), file("Other-x.ips", 900)]
        XCTAssertNil(CrashReports.newReport(in: files, lastSeen: nil))
        XCTAssertEqual(CrashReports.newestDate(in: files, lastSeen: nil), Date(timeIntervalSince1970: 300))
        XCTAssertEqual(CrashReports.newestDate(in: [], lastSeen: nil), .distantPast)
    }

    func testEachReportIsOfferedOnce() {
        let defaults = UserDefaults(suiteName: "BugReportTests-\(UUID().uuidString)")!
        var files = [file("Lodge-a.ips", 100)]
        // First launch: baseline, nothing offered.
        var seen = defaults.object(forKey: CrashReports.lastSeenKey) as? Date
        XCTAssertNil(CrashReports.newReport(in: files, lastSeen: seen))
        defaults.set(CrashReports.newestDate(in: files, lastSeen: seen), forKey: CrashReports.lastSeenKey)
        // A crash: offered on the next launch…
        files.append(file("Lodge-b.ips", 200))
        seen = defaults.object(forKey: CrashReports.lastSeenKey) as? Date
        XCTAssertEqual(CrashReports.newReport(in: files, lastSeen: seen)?.name, "Lodge-b.ips")
        defaults.set(CrashReports.newestDate(in: files, lastSeen: seen), forKey: CrashReports.lastSeenKey)
        // …and not on the one after.
        seen = defaults.object(forKey: CrashReports.lastSeenKey) as? Date
        XCTAssertNil(CrashReports.newReport(in: files, lastSeen: seen))
    }

    func testLiveSystemInfoIsFilledIn() {
        let live = BugReport.SystemInfo.current
        XCTAssertFalse(live.macOSVersion.isEmpty)
        XCTAssertNotEqual(live.macModel, "Unknown Mac")
        XCTAssertNotEqual(live.chip, "Unknown chip")
    }
}
