import Foundation

/// Lodge was called SnapDrop before 1.0. The first time Lodge starts it copies SnapDrop's data
/// so nothing is lost:
/// - every file in ~/Library/Application Support/SnapDrop/ (ledger.json, destinations.json,
///   cameras.json, presets.json, …) is copied into ~/Library/Application Support/Lodge/;
/// - SnapDrop's settings (templates, theme, appearance, presets in use, …) are copied from its
///   UserDefaults domain into Lodge's.
///
/// Everything is **copied, never moved**, so SnapDrop keeps working as a backup. Anything Lodge
/// already has wins, and the migration runs once (a flag is saved when it's done).
enum LegacyMigration {
    /// The app's old name and identifiers. These are the only intentional "SnapDrop" mentions.
    static let legacyFolderName = "SnapDrop"
    static let legacyBundleIdentifier = "com.sebastianphillips.SnapDrop"
    /// Unfinished copies SnapDrop left behind; they still reserve their sequence numbers.
    static let legacyPartialSuffix = ".snapdrop-partial"
    /// Saved in Lodge's defaults once the migration has run.
    static let doneKey = "migratedFromSnapDrop"

    struct Outcome: Equatable {
        var copiedFiles: [String] = []
        var copiedSettings: [String] = []
    }

    static var applicationSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }
    static var legacyFolder: URL { applicationSupport.appendingPathComponent(legacyFolderName, isDirectory: true) }
    static var folder: URL { applicationSupport.appendingPathComponent("Lodge", isDirectory: true) }

    /// Runs the migration once. Returns `nil` if it has already run.
    @discardableResult
    static func runIfNeeded(defaults: UserDefaults = .standard,
                            legacySettings: [String: Any]? = nil,
                            legacyFolder: URL = LegacyMigration.legacyFolder,
                            folder: URL = LegacyMigration.folder,
                            fileManager: FileManager = .default) -> Outcome? {
        guard !defaults.bool(forKey: doneKey) else { return nil }
        let outcome = Outcome(
            copiedFiles: copyFiles(from: legacyFolder, to: folder, fileManager: fileManager),
            copiedSettings: copySettings(legacySettings ?? readLegacySettings(), into: defaults))
        defaults.set(true, forKey: doneKey)
        return outcome
    }

    /// Copies each item in `legacyFolder` that `folder` doesn't have yet. Returns the names copied.
    static func copyFiles(from legacyFolder: URL, to folder: URL, fileManager: FileManager = .default) -> [String] {
        guard let items = try? fileManager.contentsOfDirectory(at: legacyFolder, includingPropertiesForKeys: nil),
              !items.isEmpty else { return [] }
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        var copied: [String] = []
        for item in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = item.lastPathComponent
            guard name != ".DS_Store" else { continue }
            let target = folder.appendingPathComponent(name)
            guard !fileManager.fileExists(atPath: target.path) else { continue }
            if (try? fileManager.copyItem(at: item, to: target)) != nil { copied.append(name) }
        }
        return copied
    }

    /// Whether a SnapDrop setting is worth bringing over. System keys (window frames, open
    /// panel state) and screenshot flags are left behind.
    static func shouldCopySetting(_ key: String) -> Bool {
        let skipped = ["NS", "Apple", "com.apple.", "SnapDropDemo", "LodgeDemo"]
        return key != doneKey && !skipped.contains(where: { key.hasPrefix($0) })
    }

    /// Copies `settings` into `defaults`, keeping any value Lodge already has. Returns the keys copied.
    static func copySettings(_ settings: [String: Any], into defaults: UserDefaults) -> [String] {
        var copied: [String] = []
        for key in settings.keys.sorted() where shouldCopySetting(key) && defaults.object(forKey: key) == nil {
            defaults.set(settings[key], forKey: key)
            copied.append(key)
        }
        return copied
    }

    /// SnapDrop's saved settings (its UserDefaults domain), read without changing them.
    static func readLegacySettings(domain: String = LegacyMigration.legacyBundleIdentifier) -> [String: Any] {
        let app = domain as CFString
        guard let keys = CFPreferencesCopyKeyList(app, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String],
              !keys.isEmpty,
              let values = CFPreferencesCopyMultiple(keys as CFArray, app, kCFPreferencesCurrentUser,
                                                     kCFPreferencesAnyHost) as? [String: Any]
        else { return [:] }
        return values
    }

    /// The file name without an unfinished-copy suffix (Lodge's own or SnapDrop's).
    static func withoutPartialSuffix(_ name: String) -> String {
        for suffix in [Copier.partialSuffix, legacyPartialSuffix] where name.hasSuffix(suffix) {
            return String(name.dropLast(suffix.count))
        }
        return name
    }
}
