import AppKit
import QuickLookThumbnailing

/// How the Media stage shows files: a list of names, or a grid of thumbnails.
enum MediaLayout: String, CaseIterable, Identifiable, Sendable {
    case list, grid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .list: return "List"
        case .grid: return "Grid"
        }
    }

    var symbol: String {
        switch self {
        case .list: return "list.bullet"
        case .grid: return "square.grid.2x2"
        }
    }
}

/// Which files get a real thumbnail and a Quick Look preview.
enum MediaPreviewSupport {
    /// Camera RAW video, MXF and sidecar metadata: macOS can't draw a thumbnail, so these get a symbol.
    static let noThumbnailExtensions: Set<String> = ["braw", "r3d", "mxf", "xml", "xmp", "crm", "ari", "cine", "nev"]

    /// Formats Quick Look can't open at all (XML still previews as text).
    static let noPreviewExtensions: Set<String> = ["braw", "r3d", "mxf", "crm", "ari", "cine", "nev"]

    static func fileExtension(_ fileName: String) -> String {
        (fileName as NSString).pathExtension.lowercased()
    }

    static func hasThumbnail(fileName: String) -> Bool {
        let ext = fileExtension(fileName)
        guard !ext.isEmpty, !noThumbnailExtensions.contains(ext) else { return false }
        // Photos and videos have pictures; audio and "other" files only ever get a generic icon.
        return MediaCategory.classify(fileName: fileName).isPrimaryMedia
    }

    static func canPreview(fileName: String) -> Bool {
        let ext = fileExtension(fileName)
        return !ext.isEmpty && !noPreviewExtensions.contains(ext)
    }

    /// The symbol drawn instead of a thumbnail.
    static func fallbackSymbol(fileName: String) -> String {
        switch fileExtension(fileName) {
        case "xml", "xmp": return "doc.text"
        case "braw", "r3d", "mxf", "crm", "ari", "cine", "nev": return "film.stack"
        default: return MediaCategory.classify(fileName: fileName).symbol
        }
    }
}

/// Identifies one thumbnail: the file (path, size, modification time) and how many pixels it needs.
/// A changed file, or a bigger tile on a Retina screen, gets a fresh thumbnail.
struct ThumbnailKey: Hashable, Sendable {
    let path: String
    let size: Int64
    let modified: TimeInterval?
    /// The thumbnail's longer side in points, and the screen scale.
    let points: CGFloat
    let scale: CGFloat

    init(path: String, size: Int64, modified: Date?, points: CGFloat, scale: CGFloat) {
        self.path = path
        self.size = size
        self.modified = modified?.timeIntervalSinceReferenceDate
        self.points = points
        self.scale = max(1, scale)
    }

    init(clip: Clip, points: CGFloat, scale: CGFloat) {
        self.init(path: clip.url.path, size: clip.size, modified: clip.modificationDate, points: points, scale: scale)
    }

    /// The longer side in pixels.
    var pixels: Int { Int((points * scale).rounded(.up)) }

    /// The `NSCache` key.
    var cacheKey: String {
        let time = modified.map { String(format: "%.3f", $0) } ?? "-"
        return "\(path)|\(size)|\(time)|\(pixels)"
    }
}

/// Lets at most `limit` tasks run at once; the rest wait their turn (first come, first served).
@MainActor
final class AsyncLimiter {
    var limit: Int {
        didSet { resumeWaiting() }
    }
    private(set) var running = 0
    private var waiting: [(id: Int, continuation: CheckedContinuation<Bool, Never>)] = []
    private var nextID = 0

    var waitingCount: Int { waiting.count }

    init(limit: Int) {
        self.limit = max(1, limit)
    }

    /// Waits for a free slot. `false` = cancelled while waiting (don't call `release()`).
    func acquire() async -> Bool {
        if Task.isCancelled { return false }
        if running < limit {
            running += 1
            return true
        }
        let id = nextID
        nextID += 1
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiting.append((id, continuation))
            }
        } onCancel: {
            Task { @MainActor in self.cancel(id) }
        }
    }

    func release() {
        running = max(0, running - 1)
        resumeWaiting()
    }

    /// Everyone still waiting gives up (a new card, or the card was ejected).
    func cancelWaiting() {
        let all = waiting
        waiting = []
        for waiter in all { waiter.continuation.resume(returning: false) }
    }

    private func cancel(_ id: Int) {
        guard let index = waiting.firstIndex(where: { $0.id == id }) else { return }
        waiting.remove(at: index).continuation.resume(returning: false)
    }

    private func resumeWaiting() {
        while running < max(1, limit), !waiting.isEmpty {
            let next = waiting.removeFirst()
            running += 1
            next.continuation.resume(returning: true)
        }
    }
}

/// Draws file thumbnails with Quick Look, a few at a time, and keeps them in memory.
///
/// Read-only: Quick Look reads the file on the card and never writes anything to it.
@MainActor
final class ThumbnailProvider {
    static let maxConcurrent = 4
    /// While copying, thumbnails wait their turn one at a time so the card's bandwidth goes to the copy.
    static let maxConcurrentWhileCopying = 1

    private let cache = NSCache<NSString, NSImage>()
    /// Files Quick Look couldn't draw (not retried until the file changes).
    private var failed: Set<String> = []
    private let limiter = AsyncLimiter(limit: maxConcurrent)
    private var requests: [Int: QLThumbnailGenerator.Request] = [:]
    private var nextRequestID = 0
    /// Bumped by `cancelAll()`; work started before that is thrown away.
    private var generation = 0

    /// Demo mode: draw theme placeholders instead of reading files.
    var usesPlaceholders = false

    /// Lower priority while an offload is copying.
    var isThrottled = false {
        didSet { limiter.limit = isThrottled ? Self.maxConcurrentWhileCopying : Self.maxConcurrent }
    }

    init() {
        cache.countLimit = 800
        cache.totalCostLimit = 96 * 1024 * 1024
    }

    func cachedImage(for key: ThumbnailKey) -> NSImage? {
        cache.object(forKey: key.cacheKey as NSString)
    }

    /// The thumbnail for `clip`, or `nil` if there isn't one (unsupported type, unreadable, cancelled).
    func image(for clip: Clip, key: ThumbnailKey) async -> NSImage? {
        guard !usesPlaceholders, MediaPreviewSupport.hasThumbnail(fileName: clip.url.lastPathComponent) else { return nil }
        let cacheKey = key.cacheKey
        if let hit = cache.object(forKey: cacheKey as NSString) { return hit }
        guard !failed.contains(cacheKey) else { return nil }

        let started = generation
        guard await limiter.acquire() else { return nil }
        defer { limiter.release() }
        guard started == generation, !Task.isCancelled else { return nil }
        if let hit = cache.object(forKey: cacheKey as NSString) { return hit }   // another tile drew it meanwhile

        let request = QLThumbnailGenerator.Request(
            fileAt: clip.url,
            size: CGSize(width: key.points, height: key.points),
            scale: key.scale,
            representationTypes: [.lowQualityThumbnail, .thumbnail])
        let id = nextRequestID
        nextRequestID += 1
        requests[id] = request
        defer { requests[id] = nil }

        let image = await withTaskCancellationHandler {
            await Self.generate(request)
        } onCancel: {
            QLThumbnailGenerator.shared.cancel(request)
        }
        guard started == generation, !Task.isCancelled else { return nil }
        guard let image else {
            failed.insert(cacheKey)
            return nil
        }
        cache.setObject(image, forKey: cacheKey as NSString, cost: key.pixels * key.pixels * 4)
        return image
    }

    /// Stops everything in flight or waiting (the card was ejected or is being rescanned).
    func cancelAll() {
        generation += 1
        for request in requests.values { QLThumbnailGenerator.shared.cancel(request) }
        requests = [:]
        limiter.cancelWaiting()
    }

    private nonisolated static func generate(_ request: QLThumbnailGenerator.Request) async -> NSImage? {
        do {
            return try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
        } catch {
            return nil
        }
    }
}
