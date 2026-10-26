import Foundation
import AppKit

/// First-launch setup ("Set up your first preset"): a splash, five steps that build a real
/// `OffloadPreset`, and a done screen. The logic lives here; the screens are in OnboardingView.swift
/// and the window in OnboardingWindow.swift. Design: Design/onboarding/.
enum OnboardingStep: String, CaseIterable, Codable, Identifiable, Sendable {
    case splash, template, destination, folders, naming, review, done

    var id: String { rawValue }

    /// The five steps in the sidebar (not the splash or the done screen).
    static let numbered: [OnboardingStep] = [.template, .destination, .folders, .naming, .review]

    /// 1…5 for the numbered steps.
    var number: Int? { Self.numbered.firstIndex(of: self).map { $0 + 1 } }

    var sidebarTitle: String {
        switch self {
        case .splash: "Welcome"
        case .template: "What’s a preset?"
        case .destination: "Destination"
        case .folders: "Folder structure"
        case .naming: "Naming & safety"
        case .review: "Review & save"
        case .done: "Done"
        }
    }

    var next: OnboardingStep? {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self), index + 1 < all.count else { return nil }
        return all[index + 1]
    }

    var previous: OnboardingStep? {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self), index > 0 else { return nil }
        return all[index - 1]
    }

    /// The splash and the done screen keep the night scene, so they're always dark.
    var forcesDarkAppearance: Bool { self == .splash || self == .done }
}

/// The starting points on "Folder structure". Each is one of the naming examples Lodge already
/// has (Settings ▸ Naming ▸ Examples), so every choice maps onto real templates.
enum OnboardingStarter: String, CaseIterable, Codable, Identifiable, Sendable {
    case filmShoot, photoSession, podcast, dailyArchive, blank

    var id: String { rawValue }

    var title: String {
        switch self {
        case .filmShoot: "Film shoot"
        case .photoSession: "Photo session"
        case .podcast: "Podcast"
        case .dailyArchive: "Daily archive"
        case .blank: "Blank"
        }
    }

    var symbol: String {
        switch self {
        case .filmShoot: "film"
        case .photoSession: "camera"
        case .podcast: "mic"
        case .dailyArchive: "calendar"
        case .blank: "plus"
        }
    }

    /// The Settings ▸ Naming example it uses.
    var namingPreset: NamingPreset {
        let name: String
        switch self {
        case .filmShoot: name = "Project / Date / Camera"
        case .photoSession: name = "Date / Project"
        case .podcast: name = "Project / Type / Date"
        case .dailyArchive: name = "Year / Month / Day"
        case .blank: name = "Flat"
        }
        return NamingPreset.all.first { $0.name == name } ?? NamingPreset.all[0]
    }

    /// The preset's suggested name.
    var presetName: String {
        switch self {
        case .filmShoot: "Film Shoot"
        case .photoSession: "Photo Session"
        case .podcast: "Podcast"
        case .dailyArchive: "Daily Archive"
        case .blank: "My Preset"
        }
    }
}

/// Everything chosen so far. Saved after every change, so setup picks up where it was left.
struct OnboardingDraft: Codable, Equatable, Sendable {
    var starter: OnboardingStarter = .filmShoot
    var presetName: String = OnboardingStarter.filmShoot.presetName
    /// True once the name was typed by hand (picking another starter then keeps it).
    var nameEdited = false
    var destinationPath: String?
    var makeDefaultDestination = true
    var folderTemplate: String = OnboardingStarter.filmShoot.namingPreset.folder
    /// Off = keep the camera's file names (`{original}`).
    var renameFiles = true
    var fileTemplate: String = OnboardingStarter.filmShoot.namingPreset.file
    var skipShortClips = true
    var shortClipSeconds = 5
    var ejectAfterOffload = false
    var playSuccessSound = true
    var askToImport = true
    /// "Switch to this preset now" on Review.
    var useNow = true

    /// `{original}` when renaming is off.
    var effectiveFileTemplate: String { renameFiles ? fileTemplate : "{original}" }

    var naming: NamingTemplates? { NamingTemplates(folder: folderTemplate, file: effectiveFileTemplate) }

    var folderIssues: [TemplateIssue] { NamingTemplate.parse(folderTemplate, kind: .folder).issues }
    var fileIssues: [TemplateIssue] { NamingTemplate.parse(effectiveFileTemplate, kind: .file).issues }

    var trimmedName: String { presetName.trimmingCharacters(in: .whitespaces) }

    mutating func choose(_ starter: OnboardingStarter) {
        self.starter = starter
        folderTemplate = starter.namingPreset.folder
        fileTemplate = starter.namingPreset.file
        if !nameEdited { presetName = starter.presetName }
    }

    /// Can the user go on from this step?
    func canLeave(_ step: OnboardingStep) -> Bool {
        switch step {
        case .destination: destinationPath != nil
        case .folders: NamingTemplate.parse(folderTemplate, kind: .folder).template != nil
        case .naming: NamingTemplate.parse(effectiveFileTemplate, kind: .file).template != nil
        case .review: naming != nil && destinationPath != nil && !trimmedName.isEmpty
        default: true
        }
    }

    /// The preset this draft saves.
    func makePreset(fileRules: FileRules) -> OffloadPreset {
        OffloadPreset(name: trimmedName.isEmpty ? starter.presetName : trimmedName,
                      destinationPath: destinationPath, folderTemplate: folderTemplate,
                      fileTemplate: effectiveFileTemplate, cameraID: nil,
                      skipShortClips: skipShortClips, shortClipSeconds: shortClipSeconds,
                      quickDump: false, fileRules: fileRules)
    }
}

/// Where setup is and what's been chosen. `defaults == nil` keeps it in memory (demo, tests).
@MainActor
final class OnboardingStore: ObservableObject {
    enum Key {
        static let finished = "onboardingFinished"
        static let step = "onboardingStep"
        static let draft = "onboardingDraft"
    }

    @Published var step: OnboardingStep {
        didSet { defaults?.set(step.rawValue, forKey: Key.step) }
    }
    @Published var draft: OnboardingDraft {
        didSet {
            guard draft != oldValue else { return }
            defaults?.set(try? JSONEncoder().encode(draft), forKey: Key.draft)
        }
    }
    @Published private(set) var isFinished: Bool
    /// The preset saved on Review (shown on the done screen).
    @Published private(set) var savedPreset: OffloadPreset?

    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        isFinished = defaults?.bool(forKey: Key.finished) ?? false
        step = defaults?.string(forKey: Key.step).flatMap(OnboardingStep.init(rawValue:)) ?? .splash
        draft = defaults?.data(forKey: Key.draft).flatMap { try? JSONDecoder().decode(OnboardingDraft.self, from: $0) }
            ?? OnboardingDraft()
    }

    /// Show setup at launch? Only until it's finished or skipped, and never for someone who has
    /// used Lodge before (presets, favorite destinations or offloads already there): they're
    /// marked as finished instead, so an update never greets them with it.
    func shouldShow(for model: AppModel) -> Bool {
        guard !isFinished else { return false }
        if Self.hasExistingSetup(model) {
            markFinished()
            return false
        }
        return true
    }

    static func hasExistingSetup(_ model: AppModel) -> Bool {
        !model.presets.presets.isEmpty || !model.destinations.favorites.isEmpty || !model.ledger.entries.isEmpty
    }

    func go(to step: OnboardingStep) { self.step = step }

    func goForward() {
        guard draft.canLeave(step), let next = step.next else { return }
        step = next
    }

    func goBack() {
        guard let previous = step.previous else { return }
        step = previous
    }

    /// Steps the sidebar lets you jump to: those already passed, and the current one.
    func canJump(to target: OnboardingStep) -> Bool {
        guard let current = OnboardingStep.allCases.firstIndex(of: step),
              let wanted = OnboardingStep.allCases.firstIndex(of: target) else { return false }
        return wanted <= current && target != .splash && step != .done
    }

    /// "Save preset": writes everything to the real settings, favorites and presets, then
    /// moves on to the done screen.
    @discardableResult
    func save(into model: AppModel) -> OffloadPreset? {
        guard draft.canLeave(.review) else { return nil }
        let preset = OnboardingApplier.apply(draft, to: model)
        savedPreset = preset
        step = .done
        return preset
    }

    /// Skip setup: nothing is changed (Lodge keeps its defaults) and it won't show again.
    func skip() { markFinished() }

    /// `-LodgeDemoOnboarding YES` after setup was finished: start again from the splash.
    func restart() {
        isFinished = false
        defaults?.removeObject(forKey: Key.finished)
        savedPreset = nil
        draft = OnboardingDraft()
        step = .splash
    }

    func markFinished() {
        isFinished = true
        defaults?.set(true, forKey: Key.finished)
        defaults?.removeObject(forKey: Key.step)
        defaults?.removeObject(forKey: Key.draft)
    }
}

/// Turns a finished draft into real settings, a favorite destination and a preset.
@MainActor
enum OnboardingApplier {
    @discardableResult
    static func apply(_ draft: OnboardingDraft, to model: AppModel) -> OffloadPreset {
        let settings = model.settings
        // App-wide choices from "Destination" and "Done".
        settings.ejectAfterOffload = draft.ejectAfterOffload
        settings.playSuccessSound = draft.playSuccessSound
        settings.askToImport = draft.askToImport

        // The destination becomes a favorite (Settings ▸ Destinations). With no other favorites it's
        // the default whatever the toggle says (Lodge always has a default once a favorite exists);
        // setup hides the toggle then.
        if let path = draft.destinationPath {
            let canChoose = canChooseDefault(for: path, in: model.destinations)
            let favorite = model.destinations.favorite(forPath: path) ?? model.destinations.add(path: path)
            if draft.makeDefaultDestination || !canChoose { model.destinations.setDefault(favorite.id) }
        }

        let preset = model.presets.add(draft.makePreset(fileRules: settings.fileRules))
        if draft.useNow {
            settings.apply(preset)
            if let path = preset.destinationPath {
                settings.destinationPath = path
                model.destinations.markUsed(model.destinations.favorite(forPath: path)?.id)
            }
            model.presets.markActive(preset.id)
        }
        return preset
    }
}

extension OnboardingApplier {
    /// "Make it my default destination" is only a choice when another favorite could stay the
    /// default. Lodge always has a default once there's a favorite (`DestinationStore` falls back
    /// to the first one), so a first favorite is the default either way.
    static func canChooseDefault(for path: String?, in destinations: DestinationStore) -> Bool {
        let same = destinations.favorite(forPath: path)?.id
        return destinations.favorites.contains { $0.id != same }
    }
}

/// A drive offered on "Destination".
struct OnboardingDrive: Identifiable, Hashable, Sendable {
    var name: String
    /// "Internal" or "External".
    var kind: String
    /// The folder suggested on this drive.
    var suggestedPath: String
    var totalBytes: Int64?
    var freeBytes: Int64?
    var isInternal: Bool

    var id: String { suggestedPath }

    var usedFraction: Double {
        guard let total = totalBytes, let free = freeBytes, total > 0 else { return 0 }
        return min(1, max(0, Double(total - free) / Double(total)))
    }

    var spaceText: String {
        guard let free = freeBytes else { return "Free space unknown" }
        guard let total = totalBytes else { return "\(OffloadFormatting.bytes(free)) free" }
        return "\(OffloadFormatting.bytes(free)) free of \(OffloadFormatting.bytes(total))"
    }

    /// The startup disk (suggesting ~/Movies) and writable drives in /Volumes, external SSDs
    /// included. Left out: removable media (SD/CFexpress cards), volumes with a camera's folders
    /// (DCIM, PRIVATE/M4ROOT…: a card in a USB reader), backup volumes (Time Machine) and disk
    /// images. Loose footage doesn't count: a drive of earlier offloads is a good destination.
    @MainActor
    static func live() -> [OnboardingDrive] {
        let keys: [URLResourceKey] = [.volumeLocalizedNameKey, .volumeTotalCapacityKey,
                                      .volumeAvailableCapacityForImportantUsageKey, .volumeIsInternalKey,
                                      .volumeIsRootFileSystemKey, .volumeIsReadOnlyKey, .volumeIsRemovableKey]
        var drives: [OnboardingDrive] = []
        for url in FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? [] {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            let isRoot = values.volumeIsRootFileSystem ?? false
            if !isRoot {
                // Cheap checks first; the disk image / backup / camera folder checks touch the drive.
                guard url.path.hasPrefix("/Volumes/"), !(values.volumeIsReadOnly ?? true),
                      !(values.volumeIsRemovable ?? false) else { continue }
                let traits = VolumeTraits.read(url)
                guard isOffered(traits, isReadOnly: false,
                                hasCameraFolders: CameraMedia.hasCameraFolders(root: url.path)) else { continue }
            }
            let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first?.path
                ?? NSHomeDirectory() + "/Movies"
            drives.append(OnboardingDrive(
                name: values.volumeLocalizedName ?? url.lastPathComponent,
                kind: isRoot || (values.volumeIsInternal ?? false) ? "Internal" : "External",
                suggestedPath: isRoot ? movies : url.path,
                totalBytes: values.volumeTotalCapacity.map(Int64.init),
                freeBytes: values.volumeAvailableCapacityForImportantUsage,
                isInternal: isRoot))
        }
        // External drives first (that's where footage usually goes), the startup disk last.
        return drives.sorted { !$0.isInternal && $1.isInternal }
    }

    /// Can this volume be offered as a destination on "Destination"? The startup disk always;
    /// otherwise a writable drive in /Volumes that isn't a card, a camera's card, a backup
    /// or a disk image. External SSDs count even though they're ejectable.
    static func isOffered(_ traits: VolumeTraits, isReadOnly: Bool, hasCameraFolders: Bool) -> Bool {
        if traits.isRootFileSystem { return true }
        guard traits.path.hasPrefix("/Volumes/"), !isReadOnly else { return false }
        return !traits.isRemovable && !traits.isDiskImage && !traits.isBackup && !hasCameraFolders
    }
}

/// Sample files for the previews ("With Lodge", the live previews on Naming and Review).
enum OnboardingSamples {
    static let context = NamingContext(project: "Northwind", camera: "FX6", card: "A001")

    static let card = URL(fileURLWithPath: "/Volumes/A001")

    static func clips() -> [Clip] {
        var components = DateComponents()
        components.year = 2026; components.month = 10; components.day = 26; components.hour = 9; components.minute = 14
        let start = Calendar.current.date(from: components) ?? Date()
        let files: [(String, Int64, Double)] = [
            ("XDROOT/Clip/A001C003_230914_R2EK.MXF", 1_800_000_000, 0),
            ("XDROOT/Clip/A001C004_230914_R2EK.MXF", 2_100_000_000, 400),
            ("XDROOT/Clip/A001C005_230914_R2EK.MXF", 1_500_000_000, 900),
            ("DCIM/100MSDCF/DSC00042.ARW", 24_500_000, 1_200),
            ("ZOOM/ZOOM0001_TR1.WAV", 310_000_000, 1_500),
        ]
        return files.map { path, size, offset in
            let date = start.addingTimeInterval(offset)
            return Clip(url: card.appendingPathComponent(path), relativePath: path, size: size,
                        creationDate: date, modificationDate: date)
        }
    }

    /// The sample files as this draft would name them.
    static func plan(_ draft: OnboardingDraft) -> [PlannedFile] {
        guard let naming = draft.naming else { return [] }
        return OffloadPlanner.plan(files: clips(), naming: naming, context: context, rules: .standard,
                                   existingNames: { _ in [] })
    }
}
