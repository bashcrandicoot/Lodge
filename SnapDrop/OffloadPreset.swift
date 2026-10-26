import Foundation

/// A saved setup you switch to in one click ("Drone Day", "Client B-Roll"): where files go,
/// how they're named, which camera, short-clip skipping, quick dump and the file rules.
/// (Different from `NamingPreset`, which is just an example pair of templates.)
struct OffloadPreset: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    /// The destination folder (usually a favorite). `nil` = keep the current destination.
    var destinationPath: String?
    var folderTemplate: String
    var fileTemplate: String
    /// The camera for `{camera}`. `nil` = keep the camera SnapDrop suggests for the card.
    var cameraID: UUID?
    var skipShortClips: Bool
    var shortClipSeconds: Int
    var quickDump: Bool
    var fileRules: FileRules

    init(id: UUID = UUID(), name: String, destinationPath: String? = nil,
         folderTemplate: String = NamingTemplates.defaultFolder, fileTemplate: String = NamingTemplates.defaultFile,
         cameraID: UUID? = nil, skipShortClips: Bool = true, shortClipSeconds: Int = 5,
         quickDump: Bool = false, fileRules: FileRules = .standard) {
        self.id = id
        self.name = name
        self.destinationPath = destinationPath
        self.folderTemplate = folderTemplate
        self.fileTemplate = fileTemplate
        self.cameraID = cameraID
        self.skipShortClips = skipShortClips
        self.shortClipSeconds = shortClipSeconds
        self.quickDump = quickDump
        self.fileRules = fileRules
    }

    /// Name for menus (never blank).
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Untitled Preset" : trimmed
    }

    /// The parts of the preset that are settings (everything but the id and name), for
    /// "does the current setup still match this preset?".
    func sameSettings(as other: OffloadPreset) -> Bool {
        var copy = other
        copy.id = id
        copy.name = name
        return copy == self
    }

    /// "Date / Project · 5 s" — a short description for menus and the Settings list.
    var summary: String {
        var parts: [String] = []
        let folder = quickDump ? QuickDump.folderTemplate(folderTemplate) : folderTemplate
        parts.append(folder.isEmpty ? "No folders" : TemplateDescription.levels(folder))
        if quickDump { parts.append("Quick dump") }
        parts.append(skipShortClips ? "Skips < \(shortClipSeconds) s" : "Keeps short clips")
        return parts.joined(separator: " · ")
    }
}

/// "{date}/{project}" → "Date / Project".
enum TemplateDescription {
    static func levels(_ template: String) -> String {
        FolderTemplateEditor.levels(template).map(level).joined(separator: " / ")
    }

    /// "{date}" → "Date", "{date}_{camera}" → "Date_Camera", "Clients" → "Clients".
    static func level(_ level: String) -> String {
        var result = ""
        var index = level.startIndex
        while index < level.endIndex {
            if level[index] == "{", let close = level[index...].firstIndex(of: "}") {
                let inside = level[level.index(after: index)..<close]
                let name = inside.split(separator: ":").first.map(String.init) ?? String(inside)
                let token = TemplateToken(rawValue: name.lowercased()) ?? TemplateToken.aliases[name.lowercased()]
                result += token.map { $0.rawValue.prefix(1).uppercased() + $0.rawValue.dropFirst() } ?? String(inside)
                index = level.index(after: close)
            } else {
                result.append(level[index])
                index = level.index(after: index)
            }
        }
        return result
    }
}

/// The saved presets, and which one is in use.
/// Saved as JSON at ~/Library/Application Support/SnapDrop/presets.json.
@MainActor
final class PresetStore: ObservableObject {
    @Published private(set) var presets: [OffloadPreset] = []
    /// The preset picked last (shown in the switcher). Changing a setting afterwards shows it as edited.
    @Published private(set) var activeID: UUID?
    @Published private(set) var lastError: String?

    /// `nil` keeps everything in memory (previews, demo mode, tests).
    let fileURL: URL?

    nonisolated static var defaultFileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support
            .appendingPathComponent("SnapDrop", isDirectory: true)
            .appendingPathComponent("presets.json")
    }

    private struct Stored: Codable {
        var presets: [OffloadPreset]
        var activeID: UUID?
    }

    init(fileURL: URL? = PresetStore.defaultFileURL, presets: [OffloadPreset] = [], activeID: UUID? = nil) {
        self.fileURL = fileURL
        self.presets = presets
        self.activeID = activeID
        load()
    }

    func preset(id: UUID?) -> OffloadPreset? {
        guard let id else { return nil }
        return presets.first { $0.id == id }
    }

    var activePreset: OffloadPreset? { preset(id: activeID) }

    // MARK: Editing

    /// Adds a preset with a unique name ("Preset", "Preset 2"…) and returns it.
    @discardableResult
    func add(_ preset: OffloadPreset) -> OffloadPreset {
        var preset = preset
        preset.name = uniqueName(preset.displayName)
        presets.append(preset)
        save()
        return preset
    }

    /// Replaces the saved preset with the same id (its name is kept unique).
    func update(_ preset: OffloadPreset) {
        guard let index = presets.firstIndex(where: { $0.id == preset.id }), presets[index] != preset else { return }
        presets[index] = preset
        save()
    }

    func rename(_ id: UUID, to name: String) {
        guard let index = presets.firstIndex(where: { $0.id == id }), presets[index].name != name else { return }
        presets[index].name = name
        save()
    }

    func delete(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        presets.removeAll { ids.contains($0.id) }
        if let id = activeID, ids.contains(id) { activeID = nil }
        save()
    }

    func duplicate(_ id: UUID) {
        guard let original = preset(id: id) else { return }
        var copy = original
        copy.id = UUID()
        copy.name = original.displayName + " Copy"
        add(copy)
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.sorted().map { presets[$0] }
        var remaining = presets
        for index in source.sorted(by: >) { remaining.remove(at: index) }
        let insertAt = destination - source.filter { $0 < destination }.count
        remaining.insert(contentsOf: moving, at: max(0, min(insertAt, remaining.count)))
        presets = remaining
        save()
    }

    /// Remembers the preset in use (`nil` = none).
    func markActive(_ id: UUID?) {
        let id = preset(id: id)?.id
        guard activeID != id else { return }
        activeID = id
        save()
    }

    func uniqueName(_ base: String, excluding id: UUID? = nil) -> String {
        var candidate = base
        var number = 2
        while presets.contains(where: { $0.id != id && $0.displayName.caseInsensitiveCompare(candidate) == .orderedSame }) {
            candidate = "\(base) \(number)"
            number += 1
        }
        return candidate
    }

    // MARK: Disk

    private func load() {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let stored = try JSONDecoder().decode(Stored.self, from: Data(contentsOf: fileURL))
            presets = stored.presets
            activeID = stored.activeID.flatMap { id in presets.contains { $0.id == id } ? id : nil }
        } catch {
            lastError = "Couldn’t read your presets: \(error.localizedDescription)"
        }
    }

    private func save() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(Stored(presets: presets, activeID: activeID)).write(to: fileURL, options: .atomic)
            lastError = nil
        } catch {
            lastError = "Couldn’t save your presets: \(error.localizedDescription)"
        }
    }
}
