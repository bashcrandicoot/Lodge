import Foundation

/// A camera you shoot with. Its short code (or name) fills the `{camera}` token.
struct Camera: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    /// Optional short code like "A" or "FX3", used in names instead of the full name.
    var code: String

    init(id: UUID = UUID(), name: String, code: String = "") {
        self.id = id
        self.name = name
        self.code = code
    }

    /// What `{camera}` becomes: the code if there is one, otherwise the name, cleaned up.
    var tokenValue: String {
        let code = NamingContext.clean(code)
        return code.isEmpty ? NamingContext.clean(name) : code
    }

    /// Name for menus (never blank).
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Untitled Camera" : trimmed
    }
}

/// The user's camera list, plus which camera was last used (overall and per card).
/// Saved as JSON at ~/Library/Application Support/Lodge/cameras.json.
@MainActor
final class CameraStore: ObservableObject {
    @Published private(set) var cameras: [Camera] = []
    /// The camera picked most recently, on any card.
    @Published private(set) var lastCameraID: UUID?
    /// Card identity (volume UUID, or name) → the camera last used with that card.
    private(set) var perCard: [String: UUID] = [:]
    /// Set if loading or saving failed.
    @Published private(set) var lastError: String?

    /// `nil` keeps everything in memory (previews, demo mode).
    let fileURL: URL?

    nonisolated static var defaultFileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support
            .appendingPathComponent("Lodge", isDirectory: true)
            .appendingPathComponent("cameras.json")
    }

    private struct Stored: Codable {
        var cameras: [Camera]
        var lastCameraID: UUID?
        var perCard: [String: UUID]
    }

    init(fileURL: URL? = CameraStore.defaultFileURL, cameras: [Camera] = []) {
        self.fileURL = fileURL
        self.cameras = cameras
        load()
    }

    func camera(id: UUID?) -> Camera? {
        guard let id else { return nil }
        return cameras.first { $0.id == id }
    }

    // MARK: Editing

    /// Adds a camera with a unique name ("New Camera", "New Camera 2"…) and returns it.
    @discardableResult
    func add(name: String = "New Camera", code: String = "") -> Camera {
        var candidate = name
        var number = 2
        while cameras.contains(where: { $0.name.caseInsensitiveCompare(candidate) == .orderedSame }) {
            candidate = "\(name) \(number)"
            number += 1
        }
        let camera = Camera(name: candidate, code: code)
        cameras.append(camera)
        save()
        return camera
    }

    func rename(_ id: UUID, to name: String) {
        guard let index = cameras.firstIndex(where: { $0.id == id }), cameras[index].name != name else { return }
        cameras[index].name = name
        save()
    }

    func setCode(_ id: UUID, to code: String) {
        guard let index = cameras.firstIndex(where: { $0.id == id }), cameras[index].code != code else { return }
        cameras[index].code = code
        save()
    }

    /// Removes cameras and forgets them as anyone's "last used" camera.
    func delete(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        cameras.removeAll { ids.contains($0.id) }
        if let last = lastCameraID, ids.contains(last) { lastCameraID = nil }
        perCard = perCard.filter { !ids.contains($0.value) }
        save()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        // (Same as Array.move(fromOffsets:toOffset:), which lives in SwiftUI.)
        let moving = source.sorted().map { cameras[$0] }
        var remaining = cameras
        for index in source.sorted(by: >) { remaining.remove(at: index) }
        let insertAt = destination - source.filter { $0 < destination }.count
        remaining.insert(contentsOf: moving, at: max(0, min(insertAt, remaining.count)))
        cameras = remaining
        save()
    }

    // MARK: Remembering

    /// Remembers `id` as the camera for this card (and as the last camera overall).
    func remember(_ id: UUID?, forCard identity: String) {
        guard let id, camera(id: id) != nil else { return }
        guard lastCameraID != id || perCard[identity] != id else { return }
        lastCameraID = id
        perCard[identity] = id
        save()
    }

    /// The camera to pre-select for a card: the one last used with it, else the last used one.
    func suggestedCamera(forCard identity: String) -> UUID? {
        if let id = perCard[identity], camera(id: id) != nil { return id }
        if let id = lastCameraID, camera(id: id) != nil { return id }
        return nil
    }

    // MARK: Disk

    private func load() {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let stored = try JSONDecoder().decode(Stored.self, from: Data(contentsOf: fileURL))
            cameras = stored.cameras
            lastCameraID = stored.lastCameraID
            perCard = stored.perCard
        } catch {
            lastError = "Couldn’t read the camera list: \(error.localizedDescription)"
        }
    }

    private func save() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(Stored(cameras: cameras, lastCameraID: lastCameraID, perCard: perCard))
            try data.write(to: fileURL, options: .atomic)
            lastError = nil
        } catch {
            lastError = "Couldn’t save the camera list: \(error.localizedDescription)"
        }
    }
}
