import Foundation

/// "Quick dump: skip project name". Takes `{project}` out of the templates cleanly: no empty
/// folder levels, no doubled or dangling separators. Pure, so it's unit tested.
enum QuickDump {
    /// Characters that separate parts of a name ("2026-10-25_Coastline_0001").
    static let separators: Set<Character> = ["_", "-", " ", "."]
    /// The file template used when nothing but the project was in it.
    static let fallbackFile = "{date}_{seq}"

    /// The templates without `{project}`: "{date}/{project}" + "{date}_{project}_{seq}"
    /// become "{date}" + "{date}_{seq}".
    static func templates(folder: String, file: String) -> (folder: String, file: String) {
        (folderTemplate(folder), fileTemplate(file))
    }

    /// Each level loses its `{project}`; levels left empty disappear.
    /// "{date}/{project}" → "{date}", "{project}/{camera}" → "{camera}", "{project}" → "".
    static func folderTemplate(_ template: String) -> String {
        template.split(separator: "/", omittingEmptySubsequences: false)
            .map { strip(String($0)) }
            .filter { !$0.isEmpty }
            .joined(separator: "/")
    }

    /// "{date}_{project}_{seq}" → "{date}_{seq}", "{project}_{camera}_{seq}" → "{camera}_{seq}".
    /// Falls back to "{date}_{seq}" if nothing would be left.
    static func fileTemplate(_ template: String) -> String {
        let stripped = strip(template)
        return stripped.contains("{") ? stripped : fallbackFile
    }

    /// True when the template has a `{project}` (or the old `{shoot}`) token.
    static func mentionsProject(_ template: String) -> Bool {
        firstProjectToken(in: template) != nil
    }

    /// Removes every `{project}` / `{shoot}` token together with one separator run next to it.
    static func strip(_ text: String) -> String {
        var chars = Array(text)
        while let range = firstProjectToken(in: String(chars)) {
            var start = range.lowerBound
            var end = range.upperBound
            var before = start
            while before > 0, separators.contains(chars[before - 1]) { before -= 1 }
            var after = end
            while after < chars.count, separators.contains(chars[after]) { after += 1 }
            let contentBefore = before > 0
            let contentAfter = after < chars.count
            switch (contentBefore, contentAfter) {
            case (true, true):
                // "{date}_{project}_{seq}": drop "{project}_"; "{date}_{project}{seq}": keep the "_".
                if after > end { end = after }
            case (true, false):
                start = before   // "{date}_{project}" → "{date}"
                end = after
            case (false, _):
                start = before   // "{project}_{date}" → "{date}"
                end = after
            }
            chars.removeSubrange(start..<end)
        }
        var result = String(chars)
        while let first = result.first, separators.contains(first) { result.removeFirst() }
        while let last = result.last, separators.contains(last) { result.removeLast() }
        return result
    }

    /// Character offsets of the first `{project…}` or `{shoot…}` token ("{project}", "{ Project }").
    private static func firstProjectToken(in text: String) -> Range<Int>? {
        let chars = Array(text)
        var index = 0
        while index < chars.count {
            guard chars[index] == "{", let close = chars[index...].firstIndex(of: "}") else {
                index += 1
                continue
            }
            let inside = String(chars[(index + 1)..<close]).trimmingCharacters(in: .whitespaces).lowercased()
            let name = inside.split(separator: ":", maxSplits: 1).first.map(String.init) ?? inside
            if name.trimmingCharacters(in: .whitespaces) == "project" || name.trimmingCharacters(in: .whitespaces) == "shoot" {
                return index..<(close + 1)
            }
            index = close + 1
        }
        return nil
    }
}

/// Edits the folder template one level at a time (the drag-and-drop tree in the Destination
/// stage). Levels are the parts between "/". Pure, so it's unit tested.
enum FolderTemplateEditor {
    /// Tokens offered as folder levels, in the order shown.
    static let levelTokens: [TemplateToken] = [.date, .project, .camera, .type, .year, .month, .day, .card]

    static func levels(_ template: String) -> [String] {
        template.split(separator: "/", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func join(_ levels: [String]) -> String {
        levels.joined(separator: "/")
    }

    /// Moves the level at `from` so it ends up at index `to` (clamped).
    static func move(_ template: String, from: Int, to: Int) -> String {
        var parts = levels(template)
        guard parts.indices.contains(from) else { return template }
        let level = parts.remove(at: from)
        parts.insert(level, at: max(0, min(to, parts.count)))
        return join(parts)
    }

    /// Adds `{token}` as a new level at `index` (clamped; `nil` = last).
    static func insert(_ token: TemplateToken, into template: String, at index: Int? = nil) -> String {
        var parts = levels(template)
        let level = "{\(token.rawValue)}"
        parts.insert(level, at: max(0, min(index ?? parts.count, parts.count)))
        return join(parts)
    }

    static func remove(_ template: String, at index: Int) -> String {
        var parts = levels(template)
        guard parts.indices.contains(index) else { return template }
        parts.remove(at: index)
        return join(parts)
    }

    /// Drag payloads (plain text, so they never clash with Finder's file drags).
    static let levelPrefix = "lodge-level:"
    static let tokenPrefix = "lodge-token:"

    enum Payload: Equatable {
        case level(Int)
        case token(TemplateToken)
    }

    static func payload(_ text: String) -> Payload? {
        if text.hasPrefix(levelPrefix), let index = Int(text.dropFirst(levelPrefix.count)) { return .level(index) }
        if text.hasPrefix(tokenPrefix), let token = TemplateToken(rawValue: String(text.dropFirst(tokenPrefix.count))) {
            return .token(token)
        }
        return nil
    }

    /// Applies a drop onto the level at `target` (`levels.count` = after the last level):
    /// a dragged level moves there, a token is inserted there.
    static func drop(_ payload: Payload, on target: Int, in template: String) -> String {
        switch payload {
        case .level(let from):
            let to = from < target ? target - 1 : target
            return from == to ? template : move(template, from: from, to: to)
        case .token(let token):
            return insert(token, into: template, at: target)
        }
    }
}
