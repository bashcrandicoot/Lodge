import Foundation

// Naming templates: "{date}/{project}" for folders and "{date}_{project}_{seq}" for files.
// Pure code (no disk, no UI) so every rule can be unit tested.

/// A placeholder that can appear in a template, like `{project}`.
enum TemplateToken: String, CaseIterable, Identifiable, Sendable {
    case project, camera, date, year, month, day, time, type, card, original, seq, ext

    var id: String { rawValue }

    /// Old token names that still work. `{shoot}` was merged into `{project}`.
    static let aliases: [String: TemplateToken] = ["shoot": .project]

    /// "{project}"
    var placeholder: String { "{\(rawValue)}" }

    var summary: String {
        switch self {
        case .project: return "Project name"
        case .camera: return "Selected camera"
        case .date: return "Capture date (2026-10-25)"
        case .year: return "Year (2026)"
        case .month: return "Month (10)"
        case .day: return "Day (25)"
        case .time: return "Capture time (143005)"
        case .type: return "Video, Photo, Audio or Other"
        case .card: return "Card (volume) name"
        case .original: return "Original file name, no extension"
        case .seq: return "Sequence number (0001); {seq:3} for 001"
        case .ext: return "File extension (mp4)"
        }
    }

    /// Tokens that can differ for each file in the same folder. Used to decide which
    /// part of the name after `{seq}` is a fixed "suffix" when counting existing files.
    var variesPerFile: Bool {
        switch self {
        case .original, .time, .type, .ext, .seq: return true
        default: return false
        }
    }
}

/// One piece of a template: plain text, or a token (with optional `{seq:3}` padding).
enum TemplatePart: Equatable, Sendable {
    case literal(String)
    case token(TemplateToken, padding: Int?)
}

/// A friendly problem found in a template.
struct TemplateIssue: Equatable, Sendable {
    enum Severity: Sendable { case error, warning }
    let severity: Severity
    let message: String

    static func error(_ message: String) -> TemplateIssue { TemplateIssue(severity: .error, message: message) }
    static func warning(_ message: String) -> TemplateIssue { TemplateIssue(severity: .warning, message: message) }
}

/// Characters that aren't allowed in file or folder names (":" is the Finder's
/// separator; the rest break exFAT cards and Windows drives).
enum NameRules {
    static let illegalCharacters: Set<Character> = [":", "\\", "*", "?", "\"", "<", ">", "|"]

    /// Makes any text safe to use inside one file/folder name.
    /// Replaces "/", illegal and control characters with "-", trims spaces, and
    /// removes leading dots so the result is never a hidden file.
    static func safeComponent(_ raw: String) -> String {
        var result = ""
        for character in raw {
            if character == "/" || illegalCharacters.contains(character)
                || character.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
                result.append("-")
            } else {
                result.append(character)
            }
        }
        result = result.trimmingCharacters(in: .whitespaces)
        while result.hasPrefix(".") { result.removeFirst() }
        return result.trimmingCharacters(in: .whitespaces)
    }
}

/// A parsed template. Folder templates have one entry per folder level; a file
/// template has exactly one.
struct NamingTemplate: Equatable, Sendable {
    enum Kind: Sendable { case folder, file }

    let kind: Kind
    let raw: String
    let components: [[TemplatePart]]

    /// Parses and validates `raw`. Returns the template only if there are no errors;
    /// `issues` holds errors and warnings, in the order they were found.
    static func parse(_ raw: String, kind: Kind) -> (template: NamingTemplate?, issues: [TemplateIssue]) {
        var issues: [TemplateIssue] = []
        var components: [[TemplatePart]] = []

        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if kind == .file && trimmed.isEmpty {
            return (nil, [.error("The file name can’t be empty.")])
        }

        let pieces: [String]
        if kind == .folder {
            pieces = trimmed.isEmpty ? [] : trimmed.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            if pieces.contains(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                issues.append(.error("A folder level is empty. Check for “//” or a “/” at the start or end."))
            }
        } else {
            pieces = [trimmed]
        }

        var seqCount = 0
        for piece in pieces where !piece.trimmingCharacters(in: .whitespaces).isEmpty {
            let (parts, pieceIssues) = parseComponent(piece, kind: kind)
            issues.append(contentsOf: pieceIssues)
            seqCount += parts.filter { if case .token(.seq, _) = $0 { return true } else { return false } }.count
            components.append(parts)
        }

        if kind == .file {
            if seqCount > 1 { issues.append(.error("Use {seq} only once.")) }
            let uses = Set(components.joined().compactMap { part -> TemplateToken? in
                if case .token(let token, _) = part { return token } else { return nil }
            })
            if !uses.contains(.seq) && !uses.contains(.original) {
                issues.append(.warning("Without {seq} or {original}, files that would get the same name get “_2”, “_3”… added."))
            }
        }

        // Report each message once.
        var seen = Set<String>()
        issues = issues.filter { seen.insert($0.message).inserted }

        guard !issues.contains(where: { $0.severity == .error }) else { return (nil, issues) }
        return (NamingTemplate(kind: kind, raw: trimmed, components: components), issues)
    }

    private static func parseComponent(_ text: String, kind: Kind) -> ([TemplatePart], [TemplateIssue]) {
        var parts: [TemplatePart] = []
        var issues: [TemplateIssue] = []
        var literal = ""
        var index = text.startIndex

        func flushLiteral() {
            guard !literal.isEmpty else { return }
            for character in literal {
                if character == "/" {
                    issues.append(.error("“/” isn’t allowed in the file name. Use the folder structure for folders."))
                } else if NameRules.illegalCharacters.contains(character) {
                    issues.append(.error("“\(character)” isn’t allowed in file or folder names."))
                } else if character.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
                    issues.append(.error("Names can’t contain tabs or line breaks."))
                }
            }
            parts.append(.literal(literal))
            literal = ""
        }

        while index < text.endIndex {
            let character = text[index]
            if character == "{" {
                guard let close = text[index...].firstIndex(of: "}") else {
                    issues.append(.error("A “{” is missing its closing “}”."))
                    literal += String(text[index...])
                    break
                }
                let inside = String(text[text.index(after: index)..<close])
                if inside.contains("{") {
                    issues.append(.error("A “{” is missing its closing “}”."))
                } else if let part = parseToken(inside, kind: kind, issues: &issues) {
                    flushLiteral()
                    parts.append(part)
                }
                index = text.index(after: close)
            } else if character == "}" {
                issues.append(.error("There’s a “}” without a matching “{”."))
                index = text.index(after: index)
            } else {
                literal.append(character)
                index = text.index(after: index)
            }
        }
        flushLiteral()

        if case .literal(let first)? = parts.first, first.trimmingCharacters(in: .whitespaces).hasPrefix(".") {
            issues.append(.error("Names can’t start with “.” — the file or folder would be hidden."))
        }
        return (parts, issues)
    }

    private static func parseToken(_ inside: String, kind: Kind, issues: inout [TemplateIssue]) -> TemplatePart? {
        let pieces = inside.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let name = pieces[0].trimmingCharacters(in: .whitespaces).lowercased()
        guard !name.isEmpty else {
            issues.append(.error("“{}” is an empty token. Pick one from the list below."))
            return nil
        }
        guard let token = TemplateToken(rawValue: name) ?? TemplateToken.aliases[name] else {
            issues.append(.error("{\(pieces[0])} isn’t a known token."))
            return nil
        }
        var padding: Int?
        if pieces.count == 2 {
            guard token == .seq else {
                issues.append(.error("Only {seq} can take a number, like {seq:3}."))
                return nil
            }
            guard let value = Int(pieces[1].trimmingCharacters(in: .whitespaces)), (1...9).contains(value) else {
                issues.append(.error("{seq:…} needs a number from 1 to 9, like {seq:3}."))
                return nil
            }
            padding = value
        }
        if token == .seq && kind == .folder {
            issues.append(.error("{seq} only works in the file name."))
            return nil
        }
        return .token(token, padding: padding)
    }

    /// Every token used anywhere in the template.
    var tokens: Set<TemplateToken> {
        Set(components.joined().compactMap { part in
            if case .token(let token, _) = part { return token } else { return nil }
        })
    }
}

/// The folder + file template pair used for an offload.
struct NamingTemplates: Equatable, Sendable {
    let folder: NamingTemplate
    let file: NamingTemplate

    static let defaultFolder = "{date}/{project}"
    static let defaultFile = "{date}_{project}_{seq}"

    /// The default: Destination/2026-10-25/Coastline/2026-10-25_Coastline_0001.mp4
    static let standard = NamingTemplates(folder: defaultFolder, file: defaultFile)!

    /// Parses both strings; `nil` if either has an error.
    init?(folder: String, file: String) {
        guard let folderTemplate = NamingTemplate.parse(folder, kind: .folder).template,
              let fileTemplate = NamingTemplate.parse(file, kind: .file).template else { return nil }
        self.folder = folderTemplate
        self.file = fileTemplate
    }

    func uses(_ token: TemplateToken) -> Bool {
        folder.tokens.contains(token) || file.tokens.contains(token)
    }
}

/// Ready-made template pairs offered in Settings.
struct NamingPreset: Identifiable, Equatable, Sendable {
    let name: String
    let folder: String
    let file: String
    var id: String { name }

    static let all: [NamingPreset] = [
        NamingPreset(name: "Date / Project", folder: NamingTemplates.defaultFolder, file: NamingTemplates.defaultFile),
        NamingPreset(name: "Project / Date / Camera", folder: "{project}/{date}/{camera}", file: "{date}_{project}_{camera}_{seq}"),
        NamingPreset(name: "Project / Type / Date", folder: "{project}/{type}/{date}", file: "{date}_{project}_{seq}"),
        NamingPreset(name: "Year / Month / Day", folder: "{year}/{month}/{day}", file: "{date}_{project}_{seq}"),
        NamingPreset(name: "Date / Project, Original Names", folder: "{date}/{project}", file: "{original}"),
        NamingPreset(name: "Flat", folder: "", file: "{date}_{project}_{seq}"),
    ]
}

/// The values tokens are replaced with (already cleaned up for file names).
struct NamingContext: Equatable, Sendable {
    var project: String
    var camera: String
    var card: String

    init(project: String = "", camera: String = "", card: String = "") {
        self.project = project
        self.camera = camera
        self.card = card
    }

    /// Cleans raw user input the same way everywhere: "Beach Day" -> "BeachDay".
    static func clean(_ raw: String) -> String { Renamer.sanitizeName(raw) }

    /// Shown in previews while a field is still empty.
    static let placeholders = NamingContext(project: "Project", camera: "Camera", card: "Card")

    /// This context with any empty field replaced by its placeholder.
    func fillingBlanks() -> NamingContext {
        NamingContext(
            project: project.isEmpty ? Self.placeholders.project : project,
            camera: camera.isEmpty ? Self.placeholders.camera : camera,
            card: card.isEmpty ? Self.placeholders.card : card)
    }
}

/// Turns templates into actual folder and file names for one file.
enum TemplateRenderer {
    /// Used when a rendered name comes out empty (e.g. "{project}" with no project).
    static let fallbackName = "Untitled"
    static let maxComponentLength = 180

    /// "2026-10-25/Coastline" (empty string = straight into the destination).
    static func folderPath(_ template: NamingTemplate, file: Clip, context: NamingContext, date: Date? = nil) -> String {
        template.components
            .map { finish(renderLevel($0, file: file, context: context, date: date)) }
            .joined(separator: "/")
    }

    /// Characters that join tokens side by side in a folder level ("{project}_{date}").
    static let joiners: Set<Character> = ["_", "-", " "]

    /// One folder level. Tokens side by side keep their separators, except that a token
    /// that comes out empty takes one separator next to it along, so "{camera}_{date}"
    /// without a camera is "2026-10-25", not "_2026-10-25".
    static func renderLevel(_ parts: [TemplatePart], file: Clip, context: NamingContext, date: Date? = nil) -> String {
        var pieces: [(text: String, emptyToken: Bool, joiner: Bool)] = parts.map { part in
            switch part {
            case .literal(let text):
                return (text, false, !text.isEmpty && text.allSatisfy { joiners.contains($0) })
            case .token(let token, let padding):
                let value = NameRules.safeComponent(value(of: token, padding: padding, file: file, context: context,
                                                          sequence: nil, date: date))
                return (value, value.isEmpty, false)
            }
        }
        var dropped = Set<Int>()
        for index in pieces.indices where pieces[index].emptyToken {
            // The nearest piece before it that's still there, if it's a separator with text before it…
            let before = pieces.indices.prefix(index).last { !dropped.contains($0) }
            if let before, pieces[before].joiner,
               pieces.indices.prefix(before).contains(where: { !dropped.contains($0) && !pieces[$0].text.isEmpty }) {
                dropped.insert(before)
            } else if index + 1 < pieces.count, pieces[index + 1].joiner {
                // …otherwise the separator right after it.
                dropped.insert(index + 1)
            }
        }
        for index in dropped { pieces[index].text = "" }
        return pieces.map(\.text).joined()
    }

    /// The file name split around `{seq}`: text before it, the padding, and text after.
    /// Without `{seq}`, everything is in `before` and `padding` is nil.
    struct FileStem: Equatable {
        var before: String
        var padding: Int?
        var after: String
        /// The fixed text right after `{seq}`, up to the first token that changes per file.
        var fixedAfter: String
        /// True when nothing after `{seq}` changes per file (so `fixedAfter` is the whole ending).
        var afterIsFixed: Bool = true

        func name(sequence: Int?) -> String {
            guard let padding, let sequence else { return TemplateRenderer.finish(before + after) }
            return TemplateRenderer.finish(before + String(format: "%0\(padding)d", sequence) + after)
        }
    }

    static func fileStem(_ template: NamingTemplate, file: Clip, context: NamingContext, date: Date? = nil) -> FileStem {
        let parts = template.components.first ?? []
        guard let seqIndex = parts.firstIndex(where: { if case .token(.seq, _) = $0 { return true } else { return false } }),
              case .token(_, let padding) = parts[seqIndex] else {
            return FileStem(before: render(parts, file: file, context: context, sequence: nil, date: date),
                            padding: nil, after: "", fixedAfter: "")
        }
        let beforeParts = Array(parts[..<seqIndex])
        let afterParts = Array(parts[parts.index(after: seqIndex)...])
        let fixedParts = afterParts.prefix { part in
            if case .token(let token, _) = part { return !token.variesPerFile }
            return true
        }
        return FileStem(
            before: render(beforeParts, file: file, context: context, sequence: nil, date: date),
            padding: padding ?? 4,
            after: render(afterParts, file: file, context: context, sequence: nil, date: date),
            fixedAfter: render(Array(fixedParts), file: file, context: context, sequence: nil, date: date),
            afterIsFixed: fixedParts.count == afterParts.count)
    }

    /// Value for one token.
    static func value(of token: TemplateToken, padding: Int?, file: Clip, context: NamingContext,
                      sequence: Int?, date: Date? = nil) -> String {
        let when = date ?? file.captureDate
        switch token {
        case .project: return context.project
        case .camera: return context.camera
        case .card: return context.card
        case .date: return format(when, "yyyy-MM-dd")
        case .year: return format(when, "yyyy")
        case .month: return format(when, "MM")
        case .day: return format(when, "dd")
        case .time: return format(when, "HHmmss")
        case .type: return file.category.tokenValue
        case .original: return NameRules.safeComponent((file.url.lastPathComponent as NSString).deletingPathExtension)
        case .ext: return file.url.pathExtension.lowercased()
        case .seq: return sequence.map { String(format: "%0\(padding ?? 4)d", $0) } ?? ""
        }
    }

    private static func render(_ parts: [TemplatePart], file: Clip, context: NamingContext,
                               sequence: Int?, date: Date?) -> String {
        parts.map { part in
            switch part {
            case .literal(let text): return text
            case .token(let token, let padding):
                return NameRules.safeComponent(value(of: token, padding: padding, file: file, context: context,
                                                     sequence: sequence, date: date))
            }
        }.joined()
    }

    /// Final clean-up of one rendered name: safe characters, not empty, not too long.
    static func finish(_ name: String) -> String {
        var result = NameRules.safeComponent(name)
        if result.count > maxComponentLength { result = String(result.prefix(maxComponentLength)) }
        return result.isEmpty ? fallbackName : result
    }

    private static func makeFormatter(_ pattern: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = pattern
        return formatter
    }

    // DateFormatter is expensive to create but safe to share for formatting.
    private static let formatters: [String: DateFormatter] = Dictionary(
        uniqueKeysWithValues: ["yyyy-MM-dd", "yyyy", "MM", "dd", "HHmmss"].map { ($0, makeFormatter($0)) })

    private static func format(_ date: Date, _ pattern: String) -> String {
        (formatters[pattern] ?? makeFormatter(pattern)).string(from: date)
    }
}

/// Brings templates saved by older versions up to date.
enum TemplateMigration {
    /// `{shoot}` (any case, spaces allowed inside the braces) — merged into `{project}`.
    private static let shootPattern = try! NSRegularExpression(pattern: #"\{\s*shoot\s*\}"#, options: [.caseInsensitive])
    /// Two `{project}` tokens side by side, optionally joined by "_", "-" or a space.
    private static let doubledProject = try! NSRegularExpression(pattern: #"\{project\}[_\- ]?\{project\}"#)

    /// Replaces `{shoot}` with `{project}`. Only when that happened, it also merges
    /// the duplicates it just created: "{project}/{project}" -> "{project}" and
    /// "{date}_{project}_{project}" -> "{date}_{project}". Anything else is left alone.
    static func migrate(_ raw: String, kind: NamingTemplate.Kind) -> String {
        let range = NSRange(raw.startIndex..., in: raw)
        guard shootPattern.firstMatch(in: raw, range: range) != nil else { return raw }
        let replaced = shootPattern.stringByReplacingMatches(in: raw, range: range, withTemplate: "{project}")

        func collapseDoubles(_ text: String) -> String {
            var result = text
            while true {
                let next = doubledProject.stringByReplacingMatches(
                    in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "{project}")
                if next == result { return result }
                result = next
            }
        }

        switch kind {
        case .file:
            return collapseDoubles(replaced)
        case .folder:
            var levels: [String] = []
            for level in replaced.split(separator: "/", omittingEmptySubsequences: false).map(String.init) {
                let level = collapseDoubles(level)
                // Drop a level that's just "{project}" right after another "{project}" level.
                if level.trimmingCharacters(in: .whitespaces) == "{project}",
                   levels.last?.trimmingCharacters(in: .whitespaces) == "{project}" { continue }
                levels.append(level)
            }
            return levels.joined(separator: "/")
        }
    }
}
