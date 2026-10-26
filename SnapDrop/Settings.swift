import Foundation
import AppKit

/// User preferences: destination folder, naming templates, eject after offload…
///
/// Stored in `UserDefaults` (a small built-in key/value store). A plain folder path is
/// fine because SnapDrop is not sandboxed.
@MainActor
final class AppSettings: ObservableObject {
    private enum Key {
        static let destination = "destinationPath"
        static let eject = "ejectAfterOffload"
        static let folderTemplate = "folderTemplate"
        static let fileTemplate = "fileTemplate"
        static let lastProject = "lastProject"
        static let recentProjects = "recentProjects"
        static let excludedCategories = "excludedCategories"
        static let successSound = "playSuccessSound"
        static let theme = "theme"
        static let skipShort = "skipShortClips"
        static let shortSeconds = "shortClipSeconds"
        static let appearance = "appearance"
        static let mediaLayout = "mediaLayout"
        static let listThumbnails = "listThumbnails"
        static let quickDump = "quickDump"
        static let fileRules = "fileRules"
        static let destinationMigrated = "destinationMovedToFavorites"
    }

    static let maxRecentProjects = 6

    /// Where settings are saved. `nil` = don't save (used for previews and demo mode).
    private let defaults: UserDefaults?

    /// Absolute path of the folder files are offloaded into, or `nil` if not chosen yet.
    @Published var destinationPath: String? {
        didSet { defaults?.set(destinationPath, forKey: Key.destination) }
    }

    /// Eject the card automatically after an offload where every file verified. Off by default.
    @Published var ejectAfterOffload: Bool {
        didSet { defaults?.set(ejectAfterOffload, forKey: Key.eject) }
    }

    /// Folder structure template, e.g. "{date}/{project}" ("/" separates levels).
    @Published var folderTemplate: String {
        didSet { defaults?.set(folderTemplate, forKey: Key.folderTemplate) }
    }

    /// File name template, e.g. "{date}_{project}_{seq}" (the extension is added automatically).
    @Published var fileTemplate: String {
        didSet { defaults?.set(fileTemplate, forKey: Key.fileTemplate) }
    }

    /// The project used last time (pre-filled for the next card).
    @Published private(set) var lastProject: String {
        didSet { defaults?.set(lastProject, forKey: Key.lastProject) }
    }

    /// Recently used projects, newest first.
    @Published private(set) var recentProjects: [String] {
        didSet { defaults?.set(recentProjects, forKey: Key.recentProjects) }
    }

    /// Which kinds of files get offloaded (all of them by default).
    @Published var includedCategories: Set<MediaCategory> {
        didSet {
            // Stored as the *excluded* list so categories added in the future default to on.
            let excluded = MediaCategory.allCases.filter { !includedCategories.contains($0) }.map(\.rawValue)
            defaults?.set(excluded, forKey: Key.excludedCategories)
        }
    }

    /// Plays a soft sound when an offload finishes without problems.
    @Published var playSuccessSound: Bool {
        didSet { defaults?.set(playSuccessSound, forKey: Key.successSound) }
    }

    /// Leave accidental short videos on the card (Settings ▸ General). On by default.
    @Published var skipShortClips: Bool {
        didSet { defaults?.set(skipShortClips, forKey: Key.skipShort) }
    }

    /// "Shorter than N seconds", 1–60.
    @Published var shortClipSeconds: Int {
        didSet {
            let clamped = min(max(shortClipSeconds, ShortClipRule.thresholdRange.lowerBound), ShortClipRule.thresholdRange.upperBound)
            if clamped != shortClipSeconds { shortClipSeconds = clamped; return }
            defaults?.set(shortClipSeconds, forKey: Key.shortSeconds)
        }
    }

    var shortClipRule: ShortClipRule {
        ShortClipRule(isEnabled: skipShortClips, threshold: Double(shortClipSeconds))
    }

    /// The "Skip videos shorter than" slider: 0 = off, otherwise the threshold in seconds.
    var shortClipSliderSeconds: Int {
        get { skipShortClips ? shortClipSeconds : 0 }
        set {
            if newValue <= 0 {
                skipShortClips = false
            } else {
                shortClipSeconds = newValue
                skipShortClips = true
            }
        }
    }

    /// "Quick dump: skip project name" (main window): `{project}` is left out of the names.
    @Published var quickDump: Bool {
        didSet { defaults?.set(quickDump, forKey: Key.quickDump) }
    }

    /// Proxy and sidecar extensions, and the ignore list (Settings ▸ Files).
    @Published var fileRules: FileRules {
        didSet {
            guard fileRules != oldValue else { return }
            defaults?.set(try? JSONEncoder().encode(fileRules), forKey: Key.fileRules)
        }
    }

    /// True once the old single "Destination" setting was added to the favorites.
    var destinationMigrated: Bool {
        get { defaults?.bool(forKey: Key.destinationMigrated) ?? migratedInMemory }
        set {
            if let defaults { defaults.set(newValue, forKey: Key.destinationMigrated) } else { migratedInMemory = newValue }
        }
    }
    private var migratedInMemory = false

    /// The colour theme (Settings ▸ Appearance). Default (neutral black) unless chosen.
    @Published var themeID: ThemePalette.ID {
        didSet { defaults?.set(themeID.rawValue, forKey: Key.theme) }
    }

    /// Light, Dark, or follow the system. Dark unless chosen.
    @Published var appearance: AppAppearance {
        didSet { defaults?.set(appearance.rawValue, forKey: Key.appearance) }
    }

    /// The Media stage as a list or a thumbnail grid (the switch above the files).
    @Published var mediaLayout: MediaLayout {
        didSet { defaults?.set(mediaLayout.rawValue, forKey: Key.mediaLayout) }
    }

    /// Small thumbnails at the start of list rows. Off by default.
    @Published var showListThumbnails: Bool {
        didSet { defaults?.set(showListThumbnails, forKey: Key.listThumbnails) }
    }

    func setCategory(_ category: MediaCategory, included: Bool) {
        if included { includedCategories.insert(category) } else { includedCategories.remove(category) }
    }

    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        destinationPath = defaults?.string(forKey: Key.destination)
        ejectAfterOffload = defaults?.bool(forKey: Key.eject) ?? false
        // Templates saved before {shoot} was merged into {project} are updated once, here.
        let savedFolder = defaults?.string(forKey: Key.folderTemplate)
        let savedFile = defaults?.string(forKey: Key.fileTemplate)
        folderTemplate = savedFolder.map { TemplateMigration.migrate($0, kind: .folder) } ?? NamingTemplates.defaultFolder
        fileTemplate = savedFile.map { TemplateMigration.migrate($0, kind: .file) } ?? NamingTemplates.defaultFile
        lastProject = defaults?.string(forKey: Key.lastProject) ?? ""
        recentProjects = defaults?.stringArray(forKey: Key.recentProjects) ?? []
        let excluded = Set(defaults?.stringArray(forKey: Key.excludedCategories) ?? [])
        includedCategories = Set(MediaCategory.allCases.filter { !excluded.contains($0.rawValue) })
        playSuccessSound = defaults?.object(forKey: Key.successSound) as? Bool ?? true
        skipShortClips = defaults?.object(forKey: Key.skipShort) as? Bool ?? true
        let seconds = defaults?.object(forKey: Key.shortSeconds) as? Int ?? 5
        shortClipSeconds = min(max(seconds, ShortClipRule.thresholdRange.lowerBound), ShortClipRule.thresholdRange.upperBound)
        themeID = ThemePalette.ID(savedValue: defaults?.string(forKey: Key.theme))
        appearance = defaults?.string(forKey: Key.appearance).flatMap(AppAppearance.init(rawValue:)) ?? .dark
        mediaLayout = defaults?.string(forKey: Key.mediaLayout).flatMap(MediaLayout.init(rawValue:)) ?? .list
        showListThumbnails = defaults?.bool(forKey: Key.listThumbnails) ?? false
        quickDump = defaults?.bool(forKey: Key.quickDump) ?? false
        fileRules = defaults?.data(forKey: Key.fileRules).flatMap { try? JSONDecoder().decode(FileRules.self, from: $0) }
            ?? .standard
        // `didSet` doesn't run inside `init`, so save migrated templates explicitly.
        if let savedFolder, savedFolder != folderTemplate { defaults?.set(folderTemplate, forKey: Key.folderTemplate) }
        if let savedFile, savedFile != fileTemplate { defaults?.set(fileTemplate, forKey: Key.fileTemplate) }
        // Themes that no longer exist ("comet", "graphite") are saved as Default.
        if let savedTheme = defaults?.string(forKey: Key.theme), savedTheme != themeID.rawValue {
            defaults?.set(themeID.rawValue, forKey: Key.theme)
        }
    }

    /// The destination as a URL (handier for file operations).
    var destinationURL: URL? {
        destinationPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    // MARK: Naming

    /// The parsed templates, or `nil` while either has an error.
    var naming: NamingTemplates? {
        NamingTemplates(folder: folderTemplate, file: fileTemplate)
    }

    var folderIssues: [TemplateIssue] { NamingTemplate.parse(folderTemplate, kind: .folder).issues }
    var fileIssues: [TemplateIssue] { NamingTemplate.parse(fileTemplate, kind: .file).issues }

    /// The templates actually used: with quick dump on, `{project}` is taken out cleanly.
    var effectiveNaming: NamingTemplates? {
        guard quickDump else { return naming }
        let stripped = QuickDump.templates(folder: folderTemplate, file: fileTemplate)
        return NamingTemplates(folder: stripped.folder, file: stripped.file)
    }

    func apply(_ preset: NamingPreset) {
        folderTemplate = preset.folder
        fileTemplate = preset.file
    }

    // MARK: Presets

    /// The current setup as a preset (destination and camera come from the main window).
    func makePreset(name: String, destinationPath: String?, cameraID: UUID?) -> OffloadPreset {
        OffloadPreset(name: name, destinationPath: destinationPath, folderTemplate: folderTemplate,
                      fileTemplate: fileTemplate, cameraID: cameraID, skipShortClips: skipShortClips,
                      shortClipSeconds: shortClipSeconds, quickDump: quickDump, fileRules: fileRules)
    }

    /// Takes over a preset's templates, short-clip rule, quick dump and file rules
    /// (the destination and camera are applied by `AppModel.applyPreset`).
    func apply(_ preset: OffloadPreset) {
        folderTemplate = preset.folderTemplate
        fileTemplate = preset.fileTemplate
        shortClipSeconds = preset.shortClipSeconds
        skipShortClips = preset.skipShortClips
        quickDump = preset.quickDump
        fileRules = preset.fileRules
    }

    /// Remembers a project for next time and puts it at the top of the recent list.
    func rememberProject(_ project: String) {
        let name = project.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        lastProject = name
        var list = recentProjects.filter { $0.caseInsensitiveCompare(name) != .orderedSame }
        list.insert(name, at: 0)
        recentProjects = Array(list.prefix(Self.maxRecentProjects))
    }

    func clearRecentProjects() {
        recentProjects = []
    }

    // MARK: Destination

    /// Shows the standard macOS "choose a folder" panel.
    func chooseDestination() {
        if let url = Self.pickFolder(startingAt: destinationURL) {
            destinationPath = url.path
        }
    }

    /// The standard folder panel. Returns the chosen folder, or `nil` if cancelled.
    static func pickFolder(startingAt start: URL?,
                           message: String = "Choose the folder SnapDrop should copy your media into.") -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = message
        if let start {
            panel.directoryURL = start
        }
        return panel.runModal() == .OK ? panel.url : nil
    }
}
