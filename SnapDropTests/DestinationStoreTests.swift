import XCTest
@testable import SnapDrop

/// Favorite destinations: saving, the one-time migration, "Not connected", and which one is used.
@MainActor
final class DestinationStoreTests: XCTestCase {
    private var folder: URL!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("snapdrop-dest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private var fileURL: URL { folder.appendingPathComponent("destinations.json") }

    /// A store where only `connected` paths exist.
    private func store(connected: Set<String>, file: URL? = nil) -> DestinationStore {
        DestinationStore(fileURL: file, folderExists: { connected.contains($0) })
    }

    func testFavoritesAreSavedAndReloaded() {
        let saved = store(connected: [], file: fileURL)
        let ssd = saved.add(path: "/Volumes/Footage SSD/Jobs", name: "Footage SSD")
        let movies = saved.add(path: "/Users/me/Movies")
        saved.rename(movies.id, to: "Client Deliveries")
        saved.setDefault(movies.id)
        saved.markUsed(ssd.id)
        saved.move(fromOffsets: [1], toOffset: 0)

        let reloaded = store(connected: [], file: fileURL)
        XCTAssertEqual(reloaded.favorites.map(\.name), ["Client Deliveries", "Footage SSD"])
        XCTAssertEqual(reloaded.favorites.map(\.path), ["/Users/me/Movies", "/Volumes/Footage SSD/Jobs"])
        XCTAssertEqual(reloaded.defaultID, movies.id)
        XCTAssertEqual(reloaded.lastUsedID, ssd.id)
        XCTAssertNil(reloaded.lastError)
    }

    func testAddingSkipsDuplicatesAndKeepsNamesUnique() {
        let store = store(connected: [])
        let first = store.add(path: "/A/Footage")
        XCTAssertEqual(store.add(path: "/A/Footage/").id, first.id, "Same folder isn't added twice")
        let second = store.add(path: "/B/Footage")
        XCTAssertEqual(second.name, "Footage 2")
        XCTAssertEqual(store.favorites.count, 2)
        XCTAssertEqual(store.defaultID, first.id, "The first favorite becomes the default")
    }

    func testExistingDestinationBecomesTheFirstFavoriteOnce() throws {
        let first = store(connected: ["/Users/me/Movies/SnapDrop"], file: fileURL)
        XCTAssertTrue(first.migrate(legacyPath: "/Users/me/Movies/SnapDrop"))
        let favorite = try XCTUnwrap(first.favorites.first)
        XCTAssertEqual(first.favorites.count, 1)
        XCTAssertEqual(favorite.name, "SnapDrop", "Named after the folder")
        XCTAssertEqual(first.defaultID, favorite.id)
        XCTAssertEqual(first.lastUsedID, favorite.id)

        // Removing every favorite doesn't bring the old destination back on the next launch.
        first.delete([favorite.id])
        let next = store(connected: ["/Users/me/Movies/SnapDrop"], file: fileURL)
        XCTAssertFalse(next.migrate(legacyPath: "/Users/me/Movies/SnapDrop"))
        XCTAssertTrue(next.favorites.isEmpty)
    }

    func testNothingToMigrateWithoutADestination() {
        let store = store(connected: [], file: fileURL)
        XCTAssertFalse(store.migrate(legacyPath: nil))
        XCTAssertFalse(store.migrate(legacyPath: ""))
        XCTAssertTrue(store.favorites.isEmpty)
    }

    func testOfflineFavoritesAreNotConnected() {
        let store = store(connected: ["/Users/me/Movies"])
        let movies = store.add(path: "/Users/me/Movies")
        let ssd = store.add(path: "/Volumes/Footage SSD")
        XCTAssertTrue(store.isConnected(movies))
        XCTAssertFalse(store.isConnected(ssd))
        XCTAssertEqual(ssd.symbol, "externaldrive.fill")
        XCTAssertEqual(movies.symbol, "folder.fill")
    }

    func testRealFolderCheck() throws {
        let file = folder.appendingPathComponent("file.txt")
        try Data("x".utf8).write(to: file)
        XCTAssertTrue(DestinationStore.isFolder(folder.path))
        XCTAssertFalse(DestinationStore.isFolder(file.path))
        XCTAssertFalse(DestinationStore.isFolder(folder.appendingPathComponent("missing").path))
    }

    func testLaunchUsesLastFavoriteThenDefaultThenAnyConnected() {
        var connected: Set<String> = ["/Movies", "/Volumes/SSD", "/Pictures"]
        let make = { (connected: Set<String>) -> DestinationStore in
            DestinationStore(fileURL: self.fileURL, folderExists: { connected.contains($0) })
        }
        let setup = make(connected)
        let movies = setup.add(path: "/Movies")
        let ssd = setup.add(path: "/Volumes/SSD")
        setup.add(path: "/Pictures")
        setup.markUsed(ssd.id)

        XCTAssertEqual(make(connected).launchDestination(currentPath: "/Volumes/SSD"), "/Volumes/SSD")
        connected.remove("/Volumes/SSD")
        XCTAssertEqual(make(connected).launchDestination(currentPath: "/Volumes/SSD"), "/Movies",
                       "The default is used when the last favorite isn't plugged in")
        connected.remove("/Movies")
        XCTAssertEqual(make(connected).launchDestination(currentPath: "/Volumes/SSD"), "/Pictures")
        XCTAssertEqual(make([]).launchDestination(currentPath: "/Volumes/SSD"), "/Volumes/SSD",
                       "With nothing connected the old choice stays (and the Offload button explains)")
        XCTAssertEqual(movies.id, make([]).defaultID)
    }

    func testLaunchKeepsAnOtherFolderThatWasPickedLast() {
        let store = store(connected: ["/Movies", "/Elsewhere"])
        store.add(path: "/Movies")
        store.markUsed(nil)
        XCTAssertEqual(store.launchDestination(currentPath: "/Elsewhere"), "/Elsewhere")
        XCTAssertEqual(store.launchDestination(currentPath: "/Gone"), "/Movies")
    }

    func testRemovingTheDefaultPicksANewOne() {
        let store = store(connected: [])
        let a = store.add(path: "/A")
        let b = store.add(path: "/B")
        store.markUsed(a.id)
        store.delete([a.id])
        XCTAssertEqual(store.defaultID, b.id)
        XCTAssertNil(store.lastUsedID)
        store.markUsed(UUID())
        XCTAssertNil(store.lastUsedID, "Unknown favorites aren't remembered")
    }

    func testModelMigratesAndSwitchesFavorites() throws {
        let other = folder.appendingPathComponent("Other", isDirectory: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let settings = AppSettings(defaults: nil)
        settings.destinationPath = folder.path
        let destinations = DestinationStore(fileURL: nil)
        let model = AppModel(settings: settings, ledger: Ledger(fileURL: fileURL.appendingPathExtension("ledger")),
                             cameras: CameraStore(fileURL: nil), destinations: destinations, startWatching: false)
        XCTAssertEqual(destinations.favorites.map(\.path), [folder.path])
        XCTAssertEqual(model.currentFavorite?.id, destinations.defaultID)

        let second = destinations.add(path: other.path, name: "Other")
        model.useFavorite(second)
        XCTAssertEqual(settings.destinationPath, other.path)
        XCTAssertEqual(destinations.lastUsedID, second.id)

        let offline = destinations.add(path: folder.appendingPathComponent("Unplugged").path)
        model.useFavorite(offline)
        XCTAssertEqual(settings.destinationPath, other.path, "A favorite that isn't connected can't be picked")
    }

    func testOffloadIsBlockedWhenTheDestinationIsNotConnected() {
        let blocker = OffloadReadiness.blocker(hasCard: true, isScanning: false, newFileCount: 3, project: "Coastline",
                                               hasDestination: true, destinationConnected: false,
                                               requiredBytes: 1, availableBytes: nil)
        XCTAssertEqual(blocker, "The destination folder isn’t connected — choose another")
    }
}
