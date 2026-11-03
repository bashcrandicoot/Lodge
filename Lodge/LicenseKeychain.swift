import Foundation
import Combine
import Security

/// The license key and its Polar activation id, in the login Keychain.
/// Not synced (each Mac has its own activation). Readable after the first unlock
/// so Open at login can confirm a license.
final class KeychainLicenseStore: LicenseStore {
    static let service = "com.sebastianphillips.Lodge.license"
    static let account = "license"

    func load() throws -> StoredLicense? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainLicenseError(status: status)
        }
        return try LicenseJSON.decoder().decode(StoredLicense.self, from: data)
    }

    func save(_ license: StoredLicense) throws {
        let data = try LicenseJSON.encoder().encode(license)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
        ]
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        if update != errSecItemNotFound { throw KeychainLicenseError(status: update) }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainLicenseError(status: status) }
    }

    func clear() throws {
        try delete(account: Self.account)
    }

    func loadTrial() throws -> TrialRecord? {
        guard let data = try loadData(account: Self.trialAccount) else { return nil }
        return try LicenseJSON.decoder().decode(TrialRecord.self, from: data)
    }

    func saveTrial(_ record: TrialRecord) throws {
        try saveData(LicenseJSON.encoder().encode(record), account: Self.trialAccount)
    }

    /// Separate from the license item, so deactivating this Mac does not restart the trial.
    static let trialAccount = "trial"

    private func loadData(account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainLicenseError(status: status)
        }
        return data
    }

    private func saveData(_ data: Data, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
        ]
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        if update != errSecItemNotFound { throw KeychainLicenseError(status: update) }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainLicenseError(status: status) }
    }

    private func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound { return }
        throw KeychainLicenseError(status: status)
    }
}

struct KeychainLicenseError: Error {
    var status: OSStatus
}

/// SwiftUI face of `LicenseController`. Sends `objectWillChange` before the controller mutates.
@MainActor
final class LicenseModel: ObservableObject {
    let controller: LicenseController

    init(controller: LicenseController) {
        self.controller = controller
        controller.onChange = { [weak self] in self?.objectWillChange.send() }
    }

    var phase: LicensePhase { controller.phase }
    var statusLine: String { controller.statusLine }
    var isWorking: Bool { controller.isWorking }
    var banner: String? { controller.banner }
    var allowsUse: Bool { controller.allowsUse }
    var trialDaysLeft: Int? { controller.trialDaysLeft }
    var trialRemaining: TimeInterval? { controller.trialRemaining }
    var offersPurchase: Bool { controller.offersPurchase }
    var trialToolbarText: String? {
        guard let remaining = controller.trialRemaining else { return nil }
        return TrialLaunchNotice.toolbar(remaining)
    }

    func launchNoticeTitle(isDemo: Bool) -> String? { controller.launchNoticeTitle(isDemo: isDemo) }
    func markLaunchNoticePresented() { controller.markLaunchNoticePresented() }
    var canDeactivate: Bool { controller.canDeactivate }
    var needsCheck: Bool { controller.needsCheck }
    var maskedKey: String? { controller.maskedKey }

    var keyDraft: String {
        get { controller.keyDraft }
        set { controller.keyDraft = newValue }
    }

    func refresh() async { await controller.refresh() }
    func activate() async { await controller.activate() }
    func deactivate() async { await controller.deactivate() }

    /// The model the app keeps for its lifetime.
    /// Unit tests and demo mode never touch the Keychain and never call Polar.
    static func live() -> LicenseModel {
        if AppModel.isRunningUnitTests {
            return LicenseModel(controller: LicenseController(store: MemoryLicenseStore(), client: .refusing))
        }
        if AppModel.isDemo {
            return previewLicensed()
        }
        let controller = LicenseController(
            store: KeychainLicenseStore(),
            client: LicenseClient(transport: URLSessionLicenseTransport(), endpoint: .current))
        let model = LicenseModel(controller: controller)
        Task {
            while true {
                await model.refresh()
                try? await Task.sleep(for: .seconds(6 * 60 * 60))
                if Task.isCancelled { break }
            }
        }
        return model
    }

    /// Screenshots and SwiftUI previews: already licensed, in memory only.
    static func previewLicensed() -> LicenseModel {
        let store = MemoryLicenseStore()
        store.saved = StoredLicense(
            key: "LODGE-DEMO-0000",
            activationID: "00000000-0000-0000-0000-000000000000",
            lastValidatedAt: Date())
        return LicenseModel(controller: LicenseController(store: store, client: .refusing))
    }
}
