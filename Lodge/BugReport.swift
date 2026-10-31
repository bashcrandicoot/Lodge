import AppKit
import OSLog

/// Help ▸ Report a Bug… and the "Lodge quit unexpectedly" prompt: a new email to `Support.email`
/// with the Lodge and macOS versions, the Mac model and chip, and Lodge's own recent log lines
/// (plus the crash report, when there is one) attached as .txt files.
///
/// Only app and system details and Lodge's own log go in. Paths in the log and the crash report
/// (card, drive and folder names, the home folder) are replaced with "<path>" first.
enum BugReport {
    /// How many of Lodge's most recent log lines go in the report.
    static let logLineLimit = 200
    /// A `mailto:` body has no attachments, so it carries the log itself, cut to this size.
    static let mailtoBodyLimit = 6_000

    // MARK: What goes in

    struct SystemInfo: Equatable, Sendable {
        var appVersion: String
        var build: String
        /// "27.0 (26A428)"
        var macOSVersion: String
        /// "Mac15,6"
        var macModel: String
        /// "Apple M3 Pro"
        var chip: String

        static var current: SystemInfo {
            let info = Bundle.main.infoDictionary ?? [:]
            return SystemInfo(
                appVersion: info["CFBundleShortVersionString"] as? String ?? "?",
                build: info["CFBundleVersion"] as? String ?? "?",
                macOSVersion: macOSVersionString(),
                macModel: sysctlString("hw.model") ?? "Unknown Mac",
                chip: sysctlString("machdep.cpu.brand_string") ?? "Unknown chip")
        }
    }

    /// "Lodge bug report (version <version> build <build>)"
    static func subject(_ info: SystemInfo) -> String {
        "Lodge bug report (version \(info.appVersion) build \(info.build))"
    }

    /// The email's text. `attachments` names the files that come with it; `inlineLog` is only
    /// used for the `mailto:` fallback, which can't attach anything.
    static func body(_ info: SystemInfo, attachments: [String] = [], crashReportName: String? = nil,
                     inlineLog: [String]? = nil) -> String {
        var lines = [
            "What happened?",
            crashReportName == nil
                ? "(What were you doing, and what went wrong? Steps to make it happen again help a lot.)"
                : "(Lodge quit unexpectedly. What were you doing just before?)",
            "",
            "",
            "—",
            "Lodge \(info.appVersion) (build \(info.build))",
            "macOS \(info.macOSVersion)",
            "Mac: \(info.macModel), \(info.chip)",
        ]
        if let crashReportName { lines.append("Crash: \(crashReportName)") }
        if !attachments.isEmpty { lines.append("Attached: \(attachments.joined(separator: ", "))") }
        if let inlineLog {
            lines.append("")
            lines.append("Lodge’s recent log:")
            lines.append(inlineLog.isEmpty ? "(nothing logged recently)" : inlineLog.joined(separator: "\n"))
        }
        return lines.joined(separator: "\n")
    }

    /// The body for `mailto:`, with as many of the newest log lines as fit in `mailtoBodyLimit`.
    static func mailtoBody(_ info: SystemInfo, crashReportName: String?, log: [String]) -> String {
        var kept = log
        while !kept.isEmpty,
              body(info, crashReportName: crashReportName, inlineLog: kept).count > mailtoBodyLimit {
            kept.removeFirst(max(1, kept.count / 10))
        }
        var text = body(info, crashReportName: crashReportName, inlineLog: kept)
        if crashReportName != nil {
            text += "\n\n(The crash report couldn’t be attached. It’s in Console ▸ Crash Reports, under Lodge.)"
        }
        return text
    }

    /// The last `limit` lines.
    static func tail(_ lines: [String], limit: Int = logLineLimit) -> [String] {
        Array(lines.suffix(max(0, limit)))
    }

    /// Replaces file paths (in /Volumes, the home folder, /Users, /private, /var, /tmp) with
    /// "<path>": they can name cards, drives, projects and clips. A path runs until a comma,
    /// colon, semicolon, bracket, quote or the end of the line, so names with spaces go too.
    static func redactingPaths(_ text: String, homeDirectory: String = NSHomeDirectory()) -> String {
        var text = text
        if homeDirectory.count > 1 { text = text.replacingOccurrences(of: homeDirectory, with: "~") }
        guard let regex = try? NSRegularExpression(
            pattern: #"(?:~|/(?:Volumes|Users|private|var|tmp))/[^,:;()\[\]"'\n]*"#) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "<path>")
    }

    // MARK: Reading the system

    static func macOSVersionString() -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        var version = "\(os.majorVersion).\(os.minorVersion)"
        if os.patchVersion > 0 { version += ".\(os.patchVersion)" }
        if let build = sysctlString("kern.osversion") { version += " (\(build))" }
        return version
    }

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let value = String(cString: buffer).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    /// Lodge's own log lines from the last three days, newest last, paths redacted. Lodge's
    /// `.info` lines are only kept in memory, so earlier launches mostly show their notices
    /// and errors; this launch shows everything. Slow (a few seconds): call it off the main thread.
    static func recentLogLines(limit: Int = logLineLimit) -> [String] {
        let predicate = NSPredicate(format: "subsystem == %@", Logger.subsystem)
        func read(_ store: OSLogStore) -> [String] {
            let since = store.position(date: Date().addingTimeInterval(-3 * 86_400))
            guard let entries = try? store.getEntries(at: since, matching: predicate) else { return [] }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            formatter.timeZone = .current
            var lines: [String] = []
            for case let entry as OSLogEntryLog in entries {
                lines.append("\(formatter.string(from: entry.date)) [\(entry.category)] \(entry.composedMessage)")
                if lines.count > limit * 4 { lines.removeFirst(lines.count - limit) }
            }
            return lines
        }
        var lines = (try? OSLogStore.local()).map(read) ?? []
        // The local store needs an admin account; this launch's own lines are always readable.
        if lines.isEmpty, let own = try? OSLogStore(scope: .currentProcessIdentifier) { lines = read(own) }
        return tail(lines, limit: limit).map { redactingPaths($0) }
    }

    // MARK: Sending

    /// Gathers the log (off the main thread) and opens a new email. Nothing is sent: the user
    /// reads it over in Mail and clicks Send themselves.
    @MainActor
    static func compose(crashReport: CrashReports.File? = nil) {
        Task.detached(priority: .userInitiated) {
            let info = SystemInfo.current
            let log = recentLogLines()
            let crashText = crashReport.flatMap { try? String(contentsOf: $0.url, encoding: .utf8) }
                .map { redactingPaths($0) }
            await MainActor.run {
                open(info: info, log: log, crashReportName: crashReport?.name, crashText: crashText)
            }
        }
    }

    @MainActor
    private static func open(info: SystemInfo, log: [String], crashReportName: String?, crashText: String?) {
        var files: [URL] = []
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Lodge Bug Report", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let logFile = folder.appendingPathComponent("Lodge log.txt")
        let logText = log.isEmpty ? "(nothing logged recently)\n" : log.joined(separator: "\n") + "\n"
        if (try? logText.write(to: logFile, atomically: true, encoding: .utf8)) != nil { files.append(logFile) }
        if let crashText, let crashReportName {
            let name = (crashReportName as NSString).deletingPathExtension + ".txt"
            let crashFile = folder.appendingPathComponent(name)
            if (try? crashText.write(to: crashFile, atomically: true, encoding: .utf8)) != nil { files.append(crashFile) }
        }

        let text = body(info, attachments: files.map(\.lastPathComponent), crashReportName: crashReportName)
        if let mail = NSSharingService(named: .composeEmail), mail.canPerform(withItems: [text] + files) {
            mail.recipients = [Support.email]
            mail.subject = subject(info)
            mail.perform(withItems: [text] + files)
            return
        }
        // No Mail account: a plain mailto: with the log in the body.
        let url = Support.mailURL(subject: subject(info),
                                  body: mailtoBody(info, crashReportName: crashReportName, log: log))
        NSWorkspace.shared.open(url)
    }
}

/// Crash reports macOS wrote for Lodge (~/Library/Logs/DiagnosticReports/Lodge-….ips), and
/// the "Lodge quit unexpectedly last time" prompt on the next launch. Each report is offered
/// once: the newest one seen is remembered, whichever button is clicked.
enum CrashReports {
    struct File: Equatable, Sendable {
        var url: URL
        var date: Date
        var name: String { url.lastPathComponent }
    }

    static let lastSeenKey = "LodgeLastSeenCrashReportDate"

    static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
    }

    /// "Lodge-2026-10-26-152019.ips" (and older "Lodge_….crash"), not "LodgeHelper-…".
    static func isLodgeReport(_ name: String) -> Bool {
        let lower = name.lowercased()
        guard lower.hasSuffix(".ips") || lower.hasSuffix(".crash") else { return false }
        return name.hasPrefix("Lodge-") || name.hasPrefix("Lodge_")
    }

    /// The newest Lodge report that's newer than the last one seen, or `nil`. With nothing seen
    /// yet (the first launch with this feature) there's nothing to offer: older reports are
    /// from before, and the caller remembers the newest one as the starting point.
    static func newReport(in files: [File], lastSeen: Date?) -> File? {
        guard let lastSeen else { return nil }
        return files.filter { isLodgeReport($0.name) && $0.date > lastSeen }.max { $0.date < $1.date }
    }

    /// What to remember as seen: the newest Lodge report, or the old value if there's none.
    static func newestDate(in files: [File], lastSeen: Date?) -> Date? {
        let newest = files.filter { isLodgeReport($0.name) }.map(\.date).max()
        switch (newest, lastSeen) {
        case let (newest?, seen?): return max(newest, seen)
        case let (newest?, nil): return newest
        case let (nil, seen): return seen ?? .distantPast
        }
    }

    static func liveFiles() -> [File] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .creationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys,
                                                                 options: [.skipsHiddenFiles])) ?? []
        return urls.compactMap { url in
            guard isLodgeReport(url.lastPathComponent) else { return nil }
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard let date = values?.contentModificationDate ?? values?.creationDate else { return nil }
            return File(url: url, date: date)
        }
    }

    /// At launch: if Lodge crashed since the last report it saw, ask (once) to send it.
    @MainActor
    static func offerIfNeeded(defaults: UserDefaults = .standard) {
        let files = liveFiles()
        let lastSeen = defaults.object(forKey: lastSeenKey) as? Date
        let report = newReport(in: files, lastSeen: lastSeen)
        if let date = newestDate(in: files, lastSeen: lastSeen) { defaults.set(date, forKey: lastSeenKey) }
        guard let report else { return }
        Logger.app.notice("Found a new crash report from \(report.date, privacy: .public)")
        showPrompt(for: report)
    }

    /// "Lodge quit unexpectedly last time." As a sheet on the main window when it's open
    /// (so it never jumps in front of other apps), otherwise as an alert.
    @MainActor
    static func showPrompt(for report: File) {
        let alert = NSAlert()
        alert.messageText = "Lodge quit unexpectedly last time. Send a crash report?"
        alert.informativeText = "This opens a new email to \(Support.developerName) with the crash report and Lodge’s recent log attached. File, card and drive names are left out. You can read it over before sending."
        alert.addButton(withTitle: "Send Report")
        alert.addButton(withTitle: "Not Now")
        let handle: (NSApplication.ModalResponse) -> Void = { response in
            if response == .alertFirstButtonReturn { BugReport.compose(crashReport: report) }
        }
        if let window = MainWindow.window {
            alert.beginSheetModal(for: window, completionHandler: handle)
        } else {
            handle(alert.runModal())
        }
    }
}
