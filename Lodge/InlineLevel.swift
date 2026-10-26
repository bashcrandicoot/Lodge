import Foundation

/// One folder level seen as the tokens that sit side by side in it:
/// "{project}_{date}" is `{project}` and `{date}` joined by "_".
///
/// Nothing new is saved: a level is still plain template text, so every template and
/// preset made before keeps working, and `text` always gives back exactly what was parsed.
/// Pure, so it's unit tested.
struct InlineLevel: Equatable, Sendable {
    /// Each piece, as template text: "{project}", "{date}", or plain text like "Clients".
    var items: [String]
    /// What goes between the pieces: "_", "-", " " or "" (none).
    var separator: String

    /// The separators offered in the menu, in order.
    static let separators = ["_", "-", " ", ""]
    static let defaultSeparator = "_"

    init(items: [String], separator: String = InlineLevel.defaultSeparator) {
        self.items = items
        self.separator = separator
    }

    /// Splits a level into its side-by-side pieces.
    /// - Tokens with nothing between them ("{project}{date}") use no separator.
    /// - Otherwise the first "_", "-" or space outside the braces is the separator, as long as
    ///   splitting on it leaves no empty pieces and at least one piece has a token.
    /// - Anything else ("Clients", "{date}") is a single piece.
    init(_ level: String) {
        let level = level.trimmingCharacters(in: .whitespaces)
        let chunks = Self.chunks(level)
        if chunks.count >= 2, chunks.allSatisfy(\.isToken) {
            self.init(items: chunks.map(\.text), separator: "")
            return
        }
        if let separator = Self.firstSeparator(in: level) {
            let pieces = Self.split(level, on: separator)
            if pieces.count >= 2, !pieces.contains(where: \.isEmpty), pieces.contains(where: { $0.contains("{") }) {
                self.init(items: pieces, separator: separator)
                return
            }
        }
        self.init(items: level.isEmpty ? [] : [level])
    }

    /// The level as template text: "{project}_{date}".
    var text: String { items.joined(separator: separator) }

    /// More than one piece side by side.
    var isCombined: Bool { items.count > 1 }

    /// "Underscore", "Hyphen", "Space", "None".
    static func name(ofSeparator separator: String) -> String {
        switch separator {
        case "_": return "Underscore"
        case "-": return "Hyphen"
        case " ": return "Space"
        case "": return "None"
        default: return "“\(separator)”"
        }
    }

    /// What the separator looks like in a menu or tag: "_", "-", "␣", "none".
    static func symbol(ofSeparator separator: String) -> String {
        switch separator {
        case " ": return "␣"
        case "": return "none"
        default: return separator
        }
    }

    // MARK: Parsing helpers

    private struct Chunk {
        var text: String
        var isToken: Bool
    }

    /// "{a}x{b}" → "{a}", "x", "{b}". An unclosed "{" stays literal text.
    private static func chunks(_ text: String) -> [Chunk] {
        var result: [Chunk] = []
        var literal = ""
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "{", let close = text[index...].firstIndex(of: "}") {
                if !literal.isEmpty { result.append(Chunk(text: literal, isToken: false)); literal = "" }
                result.append(Chunk(text: String(text[index...close]), isToken: true))
                index = text.index(after: close)
            } else {
                literal.append(text[index])
                index = text.index(after: index)
            }
        }
        if !literal.isEmpty { result.append(Chunk(text: literal, isToken: false)) }
        return result
    }

    /// The first "_", "-" or " " that isn't inside braces.
    private static func firstSeparator(in text: String) -> String? {
        var depth = 0
        for character in text {
            if character == "{" { depth += 1 } else if character == "}" { depth = max(0, depth - 1) }
            else if depth == 0, ["_", "-", " "].contains(character) { return String(character) }
        }
        return nil
    }

    /// Splits on `separator`, but never inside braces.
    private static func split(_ text: String, on separator: String) -> [String] {
        var pieces: [String] = []
        var current = ""
        var depth = 0
        for character in text {
            if character == "{" { depth += 1 } else if character == "}" { depth = max(0, depth - 1) }
            if depth == 0, String(character) == separator {
                pieces.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        pieces.append(current)
        return pieces
    }
}

/// Side-by-side editing of the folder template (dropping a token next to another one).
extension FolderTemplateEditor {
    /// The pieces of the level at `index`, or nil if there's no such level.
    static func inlineLevel(_ template: String, at index: Int) -> InlineLevel? {
        let parts = levels(template)
        return parts.indices.contains(index) ? InlineLevel(parts[index]) : nil
    }

    /// Puts `item` (template text such as "{date}") into level `level`, before the piece at
    /// `position` (clamped; the level's count = at the end).
    static func insertInline(_ item: String, into template: String, level: Int, at position: Int) -> String {
        var parts = levels(template)
        guard parts.indices.contains(level) else { return template }
        var inline = InlineLevel(parts[level])
        inline.items.insert(item, at: clamp(position, inline.items.count))
        parts[level] = inline.text
        return join(parts)
    }

    /// Moves one piece to another place: within its level (reordering) or into another level.
    /// A level left with nothing in it disappears.
    static func moveItem(_ template: String, level from: Int, item: Int, toLevel to: Int, at position: Int) -> String {
        var parts = levels(template)
        guard parts.indices.contains(from), parts.indices.contains(to) else { return template }
        var source = InlineLevel(parts[from])
        guard source.items.indices.contains(item) else { return template }
        let moved = source.items.remove(at: item)
        if from == to {
            var target = position
            if item < position { target -= 1 }
            source.items.insert(moved, at: clamp(target, source.items.count))
            parts[from] = source.text
            return join(parts)
        }
        var destination = InlineLevel(parts[to])
        destination.items.insert(moved, at: clamp(position, destination.items.count))
        parts[to] = destination.text
        if source.items.isEmpty {
            parts.remove(at: from)
        } else {
            parts[from] = source.text
        }
        return join(parts)
    }

    /// Takes one piece out of a combined level and makes it its own level at `slot`
    /// (0 = first level, the level count = after the last). A level with a single piece just moves.
    static func extractItem(_ template: String, level: Int, item: Int, toSlot slot: Int) -> String {
        var parts = levels(template)
        guard parts.indices.contains(level) else { return template }
        var source = InlineLevel(parts[level])
        guard source.items.indices.contains(item) else { return template }
        guard source.isCombined else { return drop(.level(level), on: slot, in: template) }
        let moved = source.items.remove(at: item)
        parts[level] = source.text
        parts.insert(moved, at: clamp(slot, parts.count))
        return join(parts)
    }

    /// Removes one piece. Removing the only piece removes the level.
    static func removeItem(_ template: String, level: Int, item: Int) -> String {
        var parts = levels(template)
        guard parts.indices.contains(level) else { return template }
        var inline = InlineLevel(parts[level])
        guard inline.items.indices.contains(item) else { return template }
        inline.items.remove(at: item)
        if inline.items.isEmpty {
            parts.remove(at: level)
        } else {
            parts[level] = inline.text
        }
        return join(parts)
    }

    /// Joins a whole level into another one, side by side, before the piece at `position`.
    static func mergeLevel(_ template: String, level from: Int, into to: Int, at position: Int) -> String {
        var parts = levels(template)
        guard from != to, parts.indices.contains(from), parts.indices.contains(to) else { return template }
        let moving = InlineLevel(parts[from])
        var destination = InlineLevel(parts[to])
        destination.items.insert(contentsOf: moving.items, at: clamp(position, destination.items.count))
        parts[to] = destination.text
        parts.remove(at: from)
        return join(parts)
    }

    /// Changes what goes between the pieces of level `level` ("_", "-", " " or "").
    static func setSeparator(_ separator: String, in template: String, level: Int) -> String {
        var parts = levels(template)
        guard parts.indices.contains(level) else { return template }
        var inline = InlineLevel(parts[level])
        guard inline.isCombined else { return template }
        inline.separator = separator
        parts[level] = inline.text
        return join(parts)
    }

    /// Applies a drop onto the side of a piece: lands in level `level` before piece `position`.
    static func dropInline(_ payload: Payload, level: Int, at position: Int, in template: String) -> String {
        switch payload {
        case .token(let token):
            return insertInline(token.placeholder, into: template, level: level, at: position)
        case .level(let from):
            return mergeLevel(template, level: from, into: level, at: position)
        case .item(let from, let item):
            return moveItem(template, level: from, item: item, toLevel: level, at: position)
        }
    }

    private static func clamp(_ value: Int, _ count: Int) -> Int {
        max(0, min(value, count))
    }
}
