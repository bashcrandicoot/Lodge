import XCTest
@testable import Lodge

@MainActor
final class CameraStoreTests: XCTestCase {
    private var fileURL: URL!

    override func setUp() async throws {
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("lodge-cameras-\(UUID().uuidString)")
            .appendingPathComponent("cameras.json")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
    }

    func testListPersistsAddRenameReorderDelete() {
        let store = CameraStore(fileURL: fileURL)
        XCTAssertTrue(store.cameras.isEmpty)
        let fx3 = store.add(name: "FX3", code: "A")
        let a7 = store.add(name: "A7S III")
        let drone = store.add()
        let another = store.add()
        XCTAssertEqual(drone.name, "New Camera")
        XCTAssertEqual(another.name, "New Camera 2", "New cameras get unique names")
        store.rename(drone.id, to: "Mini 4 Pro")
        store.setCode(drone.id, to: "DRONE")
        store.delete([another.id])
        store.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)

        let reloaded = CameraStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.cameras.map(\.name), ["Mini 4 Pro", "FX3", "A7S III"])
        XCTAssertEqual(reloaded.cameras.map(\.id), [drone.id, fx3.id, a7.id])
        XCTAssertEqual(reloaded.camera(id: drone.id)?.code, "DRONE")
        XCTAssertNil(reloaded.lastError)

        reloaded.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        XCTAssertEqual(reloaded.cameras.map(\.name), ["FX3", "A7S III", "Mini 4 Pro"])
    }

    func testTokenValueUsesCodeThenName() {
        XCTAssertEqual(Camera(name: "Sony FX3", code: "A").tokenValue, "A")
        XCTAssertEqual(Camera(name: "Sony FX3").tokenValue, "SonyFX3")
        XCTAssertEqual(Camera(name: "Cam: 1/2", code: "  ").tokenValue, NamingContext.clean("Cam: 1/2"))
        XCTAssertFalse(Camera(name: "Cam: 1/2").tokenValue.contains(":"))
        XCTAssertEqual(Camera(name: "  ").displayName, "Untitled Camera")
    }

    func testRemembersCameraPerCard() {
        let store = CameraStore(fileURL: fileURL)
        let fx3 = store.add(name: "FX3")
        let a7 = store.add(name: "A7S III")
        XCTAssertNil(store.suggestedCamera(forCard: "CARD-1"), "Nothing used yet")

        store.remember(fx3.id, forCard: "CARD-1")
        store.remember(a7.id, forCard: "CARD-2")

        let reloaded = CameraStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.suggestedCamera(forCard: "CARD-1"), fx3.id)
        XCTAssertEqual(reloaded.suggestedCamera(forCard: "CARD-2"), a7.id)
        XCTAssertEqual(reloaded.suggestedCamera(forCard: "NEW-CARD"), a7.id, "Unknown cards get the last used camera")

        reloaded.delete([a7.id])
        XCTAssertNil(reloaded.lastCameraID)
        XCTAssertNil(reloaded.suggestedCamera(forCard: "CARD-2"))
        XCTAssertEqual(reloaded.suggestedCamera(forCard: "CARD-1"), fx3.id)

        reloaded.remember(UUID(), forCard: "CARD-1")
        XCTAssertEqual(reloaded.suggestedCamera(forCard: "CARD-1"), fx3.id, "Unknown camera IDs are ignored")
    }

    func testModelPreselectsAndRecordsCamera() {
        let store = CameraStore(fileURL: nil)
        let fx3 = store.add(name: "FX3", code: "A")
        let a7 = store.add(name: "A7S III", code: "B")
        store.remember(a7.id, forCard: "UUID-1")
        let settings = AppSettings(defaults: nil)
        settings.apply(NamingPreset.all[1])   // Project / Date / Camera
        let ledgerURL = FileManager.default.temporaryDirectory.appendingPathComponent("lodge-ledger-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: ledgerURL) }
        let model = AppModel(settings: settings, ledger: Ledger(fileURL: ledgerURL), cameras: store,
                             destinations: DestinationStore(fileURL: nil), startWatching: false)
        let card = CardVolume(url: URL(fileURLWithPath: "/Volumes/X"), name: "X", uuid: "UUID-1")
        let clip = Clip(url: URL(fileURLWithPath: "/Volumes/X/DCIM/C0001.MP4"), relativePath: "DCIM/C0001.MP4",
                        size: 1, creationDate: Date(), modificationDate: Date())
        model.installDemo(card: card, session: OffloadSession(card: card, clips: [clip], knownKeys: []))
        let session = try! XCTUnwrap(model.session)
        XCTAssertEqual(session.cameraID, a7.id, "The card's last camera is picked automatically")
        XCTAssertEqual(model.cameraTokenValue(for: session), "B")

        model.selectCamera(fx3.id)
        XCTAssertEqual(store.suggestedCamera(forCard: "UUID-1"), fx3.id)
        XCTAssertTrue(model.previewPlan(for: session).first?.folder.hasSuffix("/A") == true)
    }
}
