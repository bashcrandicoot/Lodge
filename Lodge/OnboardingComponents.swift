import SwiftUI

/// Colours and surfaces for setup (Design/onboarding/SPEC.md). Neutral macOS greys; every
/// control is system blue (the app's AccentColor), green is only for status.
struct OnboardingPalette {
    let dark: Bool

    init(_ scheme: ColorScheme) { dark = scheme == .dark }

    var window: Color { dark ? Color(hex: 0x1A1A1C) : Color(nsColor: .windowBackgroundColor) }
    var sidebar: Color { dark ? Color(hex: 0x202022) : Color(hex: 0xF2F2F5) }
    var card: Color { dark ? .white.opacity(0.045) : .white }
    var stroke: Color { dark ? .white.opacity(0.08) : .black.opacity(0.08) }
    var well: Color { dark ? .black.opacity(0.22) : .black.opacity(0.035) }
    var wellStroke: Color { dark ? .white.opacity(0.1) : .black.opacity(0.1) }
    var helper: Color { dark ? .white.opacity(0.42) : .black.opacity(0.45) }
    var tertiary: Color { dark ? .white.opacity(0.25) : .black.opacity(0.26) }
    var chip: Color { dark ? .white.opacity(0.08) : .black.opacity(0.06) }
    var rowSelected: Color { dark ? .white.opacity(0.08) : .black.opacity(0.06) }
    var green: Color { .green }
    var greenText: Color { dark ? Color(hex: 0x7BE38E) : Color(hex: 0x1E8E3E) }
}

/// A rounded card: white 4.5% + a 1 pt stroke (white with a hairline in Light).
struct OnboardingCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    var padding: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        let palette = OnboardingPalette(scheme)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(palette.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(palette.stroke))
    }
}

/// A small capsule label ("Required", "Always on").
struct OnboardingChip: View {
    @Environment(\.colorScheme) private var scheme
    let text: String
    var green = false

    var body: some View {
        let palette = OnboardingPalette(scheme)
        Text(text)
            .font(.system(size: green ? 10 : 11, weight: .medium))
            .foregroundStyle(green ? palette.greenText : Color.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(green ? Color.green.opacity(0.14) : palette.chip, in: Capsule())
    }
}

/// `{project}` and friends as coloured pills, with the text between them in mono.
/// Colours by kind (SPEC "Token pills"): project indigo, dates cyan, camera pink,
/// card/type/original green, sequence yellow.
struct TemplatePills: View {
    @Environment(\.colorScheme) private var scheme
    let text: String
    var size: CGFloat = 12

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(TemplatePieces.split(text).enumerated()), id: \.offset) { _, piece in
                switch piece {
                case .literal(let literal):
                    Text(literal)
                        .font(.system(size: size, design: .monospaced))
                        .foregroundStyle(.primary)
                case .token(let raw, let token):
                    TokenPill(label: raw, token: token, size: size)
                }
            }
        }
        .fixedSize()
    }
}

struct TokenPill: View {
    @Environment(\.colorScheme) private var scheme
    let label: String
    let token: TemplateToken?
    var size: CGFloat = 12

    var body: some View {
        let colors = TokenPill.colors(for: token, dark: scheme == .dark)
        Text(label)
            .font(.system(size: size, design: .monospaced))
            .foregroundStyle(colors.text)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(colors.fill, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    static func colors(for token: TemplateToken?, dark: Bool) -> (fill: Color, text: Color) {
        switch token {
        case .project:
            return (Color(hex: 0x5E5CE6).opacity(dark ? 0.22 : 0.14), Color(hex: dark ? 0xB4B3FF : 0x4B49C8))
        case .date, .time, .year, .month, .day:
            return (Color(hex: 0x64D2FF).opacity(dark ? 0.15 : 0.16), Color(hex: dark ? 0x8FDDFF : 0x0A7FA8))
        case .camera:
            return (Color(hex: 0xFF375F).opacity(dark ? 0.16 : 0.12), Color(hex: dark ? 0xFF94AA : 0xD81B4C))
        case .card, .type, .original:
            return (Color(hex: 0x32D74B).opacity(dark ? 0.15 : 0.14), Color(hex: dark ? 0x7BE38E : 0x1E8E3E))
        case .seq:
            return (Color(hex: 0xFFD60A).opacity(dark ? 0.14 : 0.2), Color(hex: dark ? 0xFFE15C : 0x9A7A00))
        case .ext, .none:
            return (dark ? .white.opacity(0.08) : .black.opacity(0.06), .secondary)
        }
    }
}

/// Splits a template into text and `{token}` pieces (for the pills).
enum TemplatePieces {
    enum Piece: Equatable {
        case literal(String)
        case token(String, TemplateToken?)
    }

    static func split(_ text: String) -> [Piece] {
        var pieces: [Piece] = []
        var literal = ""
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "{", let close = text[index...].firstIndex(of: "}") {
                if !literal.isEmpty { pieces.append(.literal(literal)); literal = "" }
                let raw = String(text[index...close])
                let inside = text[text.index(after: index)..<close]
                let name = (inside.split(separator: ":").first.map(String.init) ?? String(inside)).lowercased()
                pieces.append(.token(raw, TemplateToken(rawValue: name) ?? TemplateToken.aliases[name]))
                index = text.index(after: close)
            } else {
                literal.append(text[index])
                index = text.index(after: index)
            }
        }
        if !literal.isEmpty { pieces.append(.literal(literal)) }
        return pieces
    }
}

/// One row of the folder previews.
struct PreviewTreeRow: Identifiable, Equatable {
    enum Kind: Equatable { case root, folder, file, more }
    let id: Int
    let depth: Int
    let name: String
    let kind: Kind
}

/// Turns planned files into an indented folder tree: folders first, then files, a few per folder.
enum PreviewTree {
    private final class Node {
        var folders: [String: Node] = [:]
        var files: [String] = []
    }

    static func rows(root: String, plan: [PlannedFile], filesPerFolder: Int = 3) -> [PreviewTreeRow] {
        let top = Node()
        for file in plan {
            var node = top
            for part in file.folder.split(separator: "/").map(String.init) {
                if node.folders[part] == nil { node.folders[part] = Node() }
                node = node.folders[part]!
            }
            node.files.append(file.fileName)
        }
        var rows: [PreviewTreeRow] = [PreviewTreeRow(id: 0, depth: 0, name: root, kind: .root)]
        func walk(_ node: Node, depth: Int) {
            for name in node.folders.keys.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) {
                rows.append(PreviewTreeRow(id: rows.count, depth: depth, name: name, kind: .folder))
                walk(node.folders[name]!, depth: depth + 1)
            }
            let files = node.files.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            for name in files.prefix(filesPerFolder) {
                rows.append(PreviewTreeRow(id: rows.count, depth: depth, name: name, kind: .file))
            }
            if files.count > filesPerFolder {
                rows.append(PreviewTreeRow(id: rows.count, depth: depth, name: "… \(files.count - filesPerFolder) more", kind: .more))
            }
        }
        walk(top, depth: 1)
        return rows
    }
}

/// The folder tree preview: blue folders (like the main window's tree), files in secondary.
struct PreviewTreeView: View {
    @Environment(\.colorScheme) private var scheme
    let rows: [PreviewTreeRow]
    var rowHeight: CGFloat = 23
    var rootSymbol = "externaldrive"

    var body: some View {
        let palette = OnboardingPalette(scheme)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { row in
                HStack(spacing: 6) {
                    switch row.kind {
                    case .root:
                        Image(systemName: rootSymbol).foregroundStyle(palette.helper)
                        Text(row.name).foregroundStyle(.secondary)
                    case .folder:
                        Image(systemName: "folder.fill").foregroundStyle(.tint)
                        Text(row.name).foregroundStyle(.primary)
                    case .file:
                        Image(systemName: "doc").foregroundStyle(palette.helper)
                        Text(row.name).foregroundStyle(.secondary)
                    case .more:
                        Text(row.name).foregroundStyle(palette.helper)
                    }
                }
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)
                .padding(.leading, CGFloat(row.depth) * 16)
                .frame(height: rowHeight)
            }
        }
    }
}

/// A rounded keycap ("⌘ ,").
struct Keycap: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

/// Glass button for the night scenes (white 10% fill, white 12% stroke).
struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white.opacity(0.8))
            .padding(.horizontal, 18)
            .frame(height: 36)
            .background(.white.opacity(configuration.isPressed ? 0.16 : 0.1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(.white.opacity(0.12)))
            .contentShape(Rectangle())
    }
}
