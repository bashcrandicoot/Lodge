import Foundation

/// Pure naming rules. No disk access except in `SequenceAllocator`, so it's easy to test.
///
/// Layout: Destination/YYYY-MM-DD/ShootName/YYYY-MM-DD_ShootName_####.ext
enum Renamer {
    /// Turns what the user typed into a safe shoot name.
    /// Keeps letters, digits and "-". Everything else splits words, and each word
    /// starts with a capital letter: "beach shoot" -> "BeachShoot".
    static func sanitizeShootName(_ raw: String, maxLength: Int = 60) -> String {
        var result = ""
        var capitalizeNext = true
        for character in raw {
            if character == "-" {
                result.append(character)
            } else if character.isLetter || (character.isASCII && character.isNumber) {
                result += capitalizeNext ? String(character).uppercased() : String(character)
                capitalizeNext = false
            } else {
                // Space, underscore, punctuation, emoji… acts as a word break.
                capitalizeNext = true
            }
        }
        let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return String(trimmed.prefix(maxLength))
    }

    /// "2026-10-25" for the given date, in the Mac's local time zone.
    static func dateString(for date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// "2026-10-25_BeachShoot"
    static func prefix(dateString: String, shootName: String) -> String {
        "\(dateString)_\(shootName)"
    }

    /// "2026-10-25_BeachShoot_0007.mp4" (extension always lowercased).
    static func fileName(prefix: String, sequence: Int, fileExtension: String) -> String {
        let number = String(format: "%04d", sequence)
        let ext = fileExtension.lowercased()
        return ext.isEmpty ? "\(prefix)_\(number)" : "\(prefix)_\(number).\(ext)"
    }

    /// Destination/2026-10-25/BeachShoot/
    static func folderURL(destination: URL, dateString: String, shootName: String) -> URL {
        destination
            .appendingPathComponent(dateString, isDirectory: true)
            .appendingPathComponent(shootName, isDirectory: true)
    }

    /// Reads the sequence number out of a file name that starts with `prefix`, e.g.
    /// "2026-10-25_BeachShoot_0012.mp4" -> 12. Returns nil for unrelated names.
    /// Comparison ignores upper/lower case, like the Mac's file system does.
    static func sequenceNumber(in fileName: String, prefix: String) -> Int? {
        let lowerName = fileName.lowercased()
        let start = prefix.lowercased() + "_"
        guard lowerName.hasPrefix(start) else { return nil }
        let rest = lowerName.dropFirst(start.count)
        let digits = rest.prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty else { return nil }
        let after = rest.dropFirst(digits.count)
        guard after.isEmpty || after.hasPrefix(".") else { return nil }
        return Int(digits)
    }

    /// The highest sequence number already used by any of `names` (0 if none).
    static func highestSequence(in names: [String], prefix: String) -> Int {
        names.compactMap { sequenceNumber(in: $0, prefix: prefix) }.max() ?? 0
    }
}

/// Hands out the next free file name in each date/shoot folder.
/// The first time it sees a folder it looks at what's already there and continues
/// after the highest number, and it always double-checks a name is unused.
struct SequenceAllocator {
    private var nextNumber: [String: Int] = [:]

    mutating func nextFileURL(
        folder: URL,
        prefix: String,
        fileExtension: String,
        fileManager: FileManager = .default
    ) -> URL {
        let key = folder.standardizedFileURL.path + "|" + prefix.lowercased()
        var number: Int
        if let cached = nextNumber[key] {
            number = cached
        } else {
            let existing = (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []
            number = Renamer.highestSequence(in: existing, prefix: prefix) + 1
        }

        while true {
            let name = Renamer.fileName(prefix: prefix, sequence: number, fileExtension: fileExtension)
            let candidate = folder.appendingPathComponent(name)
            let taken = fileManager.fileExists(atPath: candidate.path)
                || fileManager.fileExists(atPath: Copier.partialURL(for: candidate).path)
            if !taken {
                nextNumber[key] = number + 1
                return candidate
            }
            number += 1
        }
    }
}
