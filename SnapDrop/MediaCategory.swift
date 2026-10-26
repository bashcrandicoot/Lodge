import Foundation

/// The kind of file found on a card, decided by its extension (case-insensitive).
enum MediaCategory: String, CaseIterable, Codable, Identifiable, Sendable {
    case video, photo, audio, other

    var id: String { rawValue }

    static let videoExtensions: Set<String> = [
        "mp4", "mov", "mxf", "braw", "r3d", "crm", "mts", "m2ts", "avi", "mkv", "insv", "lrv", "360",
    ]
    static let photoExtensions: Set<String> = [
        "jpg", "jpeg", "heic", "heif", "png", "tif", "tiff", "dng", "arw", "cr2", "cr3",
        "nef", "raf", "orf", "rw2", "srw", "pef", "gpr", "insp",
    ]
    static let audioExtensions: Set<String> = ["wav", "mp3", "aac", "m4a", "bwf"]

    /// Classifies a file by the extension of its name ("C0001.MP4" -> .video).
    static func classify(fileName: String) -> MediaCategory {
        classify(extension: (fileName as NSString).pathExtension)
    }

    static func classify(extension ext: String) -> MediaCategory {
        let lower = ext.lowercased()
        if videoExtensions.contains(lower) { return .video }
        if photoExtensions.contains(lower) { return .photo }
        if audioExtensions.contains(lower) { return .audio }
        return .other
    }

    /// Value of the `{type}` token: "Video", "Photo", "Audio" or "Other".
    var tokenValue: String {
        switch self {
        case .video: return "Video"
        case .photo: return "Photo"
        case .audio: return "Audio"
        case .other: return "Other"
        }
    }

    /// Title used in Settings and the filter control.
    var title: String { tokenValue }

    /// Lower-case plural for counts: "42 video", "3 photos"…
    func countText(_ count: Int) -> String {
        switch self {
        case .video: return "\(count) video"
        case .photo: return count == 1 ? "1 photo" : "\(count) photos"
        case .audio: return "\(count) audio"
        case .other: return "\(count) other"
        }
    }

    var symbol: String {
        switch self {
        case .video: return "film"
        case .photo: return "photo"
        case .audio: return "waveform"
        case .other: return "doc"
        }
    }

    /// Video and photos are "main" media; audio and other files can be sidecars of them.
    var isPrimaryMedia: Bool { self == .video || self == .photo }
}
