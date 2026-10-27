import Foundation

/// "Dates" (Media stage): copy only files from certain days. Any date by default.
/// Pure and `Codable`, so it's saved in settings and unit tested.
struct DateFilter: Codable, Equatable, Hashable, Sendable {
    enum Mode: String, Codable, CaseIterable, Identifiable, Sendable {
        case any, today, last7Days, custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .any: return "Any date"
            case .today: return "Today"
            case .last7Days: return "Last 7 days"
            case .custom: return "Custom range"
            }
        }
    }

    var mode: Mode = .any
    /// The custom range's first and last day (whole days; the order doesn't matter).
    var from: Date
    var to: Date

    init(mode: Mode = .any, from: Date = Date(), to: Date = Date()) {
        self.mode = mode
        self.from = from
        self.to = to
    }

    static let any = DateFilter()

    var isActive: Bool { mode != .any }

    /// The date a file is judged by: when it was created (on a camera card, when it was shot),
    /// or when it was last changed if the card doesn't record a creation date. Same order as
    /// `Clip.captureDate`, which names the files, so the `{date}` in a name always passes the
    /// filter that let the file through. `nil` when neither is known.
    static func date(of clip: Clip) -> Date? {
        clip.creationDate ?? clip.modificationDate
    }

    /// The days let through, from midnight of the first day up to (not including) midnight
    /// after the last one, so the last day counts in full. `nil` = any date.
    func interval(now: Date = Date(), calendar: Calendar = .current) -> Range<Date>? {
        let today = calendar.startOfDay(for: now)
        func dayAfter(_ day: Date) -> Date { calendar.date(byAdding: .day, value: 1, to: day) ?? day }
        switch mode {
        case .any:
            return nil
        case .today:
            return today..<dayAfter(today)
        case .last7Days:
            // Today and the six days before it.
            let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
            return start..<dayAfter(today)
        case .custom:
            let first = calendar.startOfDay(for: min(from, to))
            let last = calendar.startOfDay(for: max(from, to))
            return first..<dayAfter(last)
        }
    }

    /// True when `clip` is copied. With a filter on, a file without any date stays on the card.
    func includes(_ clip: Clip, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let interval = interval(now: now, calendar: calendar) else { return true }
        guard let date = Self.date(of: clip) else { return false }
        return interval.contains(date)
    }

    /// Card paths of the files in `files` the filter leaves on the card. Sidecars and proxies
    /// (C0001M01.XML, GL010001.LRV) go with their clip, whatever their own date; a helper file
    /// without a clip (MEDIAPRO.XML) is judged by its own date.
    func excludedIDs(in files: [Clip], rules: FileRules = .standard,
                     now: Date = Date(), calendar: Calendar = .current) -> Set<String> {
        guard isActive else { return [] }
        let sidecars = SidecarMatcher.match(Offloader.order(files), rules: rules)
        let byID = Dictionary(files.map { ($0.relativePath, $0) }, uniquingKeysWith: { first, _ in first })
        var result = Set<String>()
        for file in files {
            let judged = sidecars.primary[file.relativePath].flatMap { byID[$0] } ?? file
            if !includes(judged, now: now, calendar: calendar) { result.insert(file.relativePath) }
        }
        return result
    }
}

enum DateFilterHelp {
    static let text = "Copies only files from these days, by the date each file was created (or last changed, if the card doesn’t record that). Sidecars and proxies go with their clip. Everything else stays on the card."
}
