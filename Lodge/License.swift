import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Polar license keys for Lodge. The app talks only to Polar's public customer-portal
/// endpoints and never sends an API token.
///
/// A Mac without a key works for 3 days from the first launch stored in the Keychain.
/// After that, or when a license's last confirmation is 14 days old and cannot be
/// repeated, Lodge does not offload.
enum LodgeLicense {
    static let keyPrefix = "LODGE"
    /// Product limit configured on the Polar benefit. Polar enforces it; the app
    /// states it and does not invent a different cap.
    static let activationLimit = 3
    static let priceUSD = 10
    static let trialLength: TimeInterval = 3 * 24 * 60 * 60
    static let buyURL = URL(string: "https://buy.polar.sh/polar_cl_gS9NEtdIPJuJDXu8sdui02XetKbkwKuHgiYxi4FBkM1")!
    /// Confirm again after a week. The check is skipped until this age.
    static let revalidateAfter: TimeInterval = 7 * 24 * 60 * 60
    /// Keep working without a network until this long after the last confirmation.
    static let offlineGrace: TimeInterval = 14 * 24 * 60 * 60

    static let liveOrganizationID = "ece11ea2-d5d5-4acc-ad68-68f2ba66a6f9"
    static let sandboxOrganizationID = "6501e028-3477-48a7-b174-df0c4d223b6c"
    static let liveAPIRoot = URL(string: "https://api.polar.sh")!
    static let sandboxAPIRoot = URL(string: "https://sandbox-api.polar.sh")!

    static let activatePath = "/v1/customer-portal/license-keys/activate"
    static let validatePath = "/v1/customer-portal/license-keys/validate"
    static let deactivatePath = "/v1/customer-portal/license-keys/deactivate"
}

/// Live Polar, or the sandbox org. Release builds always resolve to live.
struct PolarEndpoint: Equatable {
    var apiRoot: URL
    var organizationID: String

    static let live = PolarEndpoint(apiRoot: LodgeLicense.liveAPIRoot, organizationID: LodgeLicense.liveOrganizationID)
    static let sandbox = PolarEndpoint(apiRoot: LodgeLicense.sandboxAPIRoot, organizationID: LodgeLicense.sandboxOrganizationID)

    /// `sandboxSetting` is the Info.plist value of `LodgePolarSandbox` (the
    /// `LODGE_POLAR_SANDBOX` build setting). `environment` is the
    /// `LODGE_POLAR_SANDBOX` environment variable. Both are ignored unless
    /// `allowSandbox` is true, which the app sets only for Debug builds.
    static func resolve(sandboxSetting: String?, environment: String?, allowSandbox: Bool) -> PolarEndpoint {
        guard allowSandbox else { return .live }
        if isSandboxFlag(sandboxSetting) || isSandboxFlag(environment) { return .sandbox }
        return .live
    }

    static func isSandboxFlag(_ raw: String?) -> Bool {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "yes", "true", "sandbox": return true
        default: return false
        }
    }

    /// What the running app should call. Debug honors the build setting and the
    /// environment variable. Release does not.
    static var current: PolarEndpoint {
        let setting = Bundle.main.object(forInfoDictionaryKey: "LodgePolarSandbox") as? String
        let environment = ProcessInfo.processInfo.environment["LODGE_POLAR_SANDBOX"]
        #if DEBUG
        let allowSandbox = true
        #else
        let allowSandbox = false
        #endif
        return resolve(sandboxSetting: setting, environment: environment, allowSandbox: allowSandbox)
    }

    func url(for path: String) -> URL {
        var root = apiRoot.absoluteString
        while root.hasSuffix("/") { root.removeLast() }
        return URL(string: root + path)!
    }
}

enum LicenseRoute: String {
    case activate = "/v1/customer-portal/license-keys/activate"
    case validate = "/v1/customer-portal/license-keys/validate"
    case deactivate = "/v1/customer-portal/license-keys/deactivate"
}

enum LicenseKey {
    static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func hasLodgePrefix(_ raw: String) -> Bool {
        let key = normalize(raw)
        return key.count > LodgeLicense.keyPrefix.count
            && key.uppercased().hasPrefix(LodgeLicense.keyPrefix)
    }

    /// Shows the prefix and the last four characters.
    static func mask(_ raw: String) -> String {
        let key = normalize(raw)
        guard key.count > 8 else { return "••••" }
        return "\(key.prefix(5))…\(key.suffix(4))"
    }
}

/// Saved on this Mac after a successful activate, and refreshed by validate.
struct StoredLicense: Codable, Equatable {
    var key: String
    var activationID: String
    var lastValidatedAt: Date
}

enum LicenseFreshness: Equatable {
    /// Confirmed less than a week ago. No network call.
    case current
    /// Due for a weekly check, still inside the 14-day offline period.
    case stale
    /// The offline period is over. Lodge waits for a successful validate.
    case graceExpired
}

enum LicensePhase: Equatable {
    /// The 3-day trial is still running. `daysLeft` is at least 1.
    case trial(daysLeft: Int)
    case unlicensed
    case licensed(StoredLicense, LicenseFreshness)
}

/// First launch of this Mac, kept in the Keychain so deleting the app does not start the trial over.
struct TrialRecord: Codable, Equatable {
    var firstLaunch: Date
    /// Latest clock reading that moved forward. A backward step does not replace this.
    var lastSeen: Date
}

enum TrialAccess: Equatable {
    case active(daysLeft: Int)
    case expired
}

enum TrialPolicy {
    /// Days remaining, rounded up, while `elapsed` is still inside the 3 days.
    static func daysLeft(elapsed: TimeInterval) -> Int {
        let remaining = LodgeLicense.trialLength - elapsed
        let day: TimeInterval = 24 * 60 * 60
        return max(1, Int((remaining / day).rounded(.up)))
    }

    /// A clock that moves backward does not lengthen the trial. It is treated as over.
    static func access(record: TrialRecord, now: Date) -> TrialAccess {
        if now < record.firstLaunch || now < record.lastSeen { return .expired }
        let elapsed = now.timeIntervalSince(record.firstLaunch)
        if elapsed >= LodgeLicense.trialLength { return .expired }
        return .active(daysLeft: daysLeft(elapsed: elapsed))
    }

    /// Records the first launch, or moves `lastSeen` forward. Never rewrites either date backward.
    static func advance(record: TrialRecord?, now: Date) -> TrialRecord {
        guard var record else { return TrialRecord(firstLaunch: now, lastSeen: now) }
        if now < record.firstLaunch || now < record.lastSeen { return record }
        record.lastSeen = now
        return record
    }

    /// Time still left, or nil when the trial is over (including a clock that moved backward).
    static func remaining(record: TrialRecord, now: Date) -> TimeInterval? {
        guard case .active = access(record: record, now: now) else { return nil }
        return LodgeLicense.trialLength - now.timeIntervalSince(record.firstLaunch)
    }
}

/// The note shown once each launch while the trial is running and this Mac has no license.
enum TrialLaunchNotice {
    static let continueTitle = "Continue"
    static let enterLicense = "Enter License Key…"

    static func shouldPresent(isTrial: Bool, isLicensed: Bool, isDemo: Bool, alreadyPresented: Bool) -> Bool {
        isTrial && !isLicensed && !isDemo && !alreadyPresented
    }

    /// "2 days left", or "5 hours left" when under a day. Rounded up, and never 0 while time remains.
    static func timeLeft(_ remaining: TimeInterval) -> String {
        let hour: TimeInterval = 60 * 60
        let day = 24 * hour
        if remaining < day {
            let hours = min(23, max(1, Int((remaining / hour).rounded(.up))))
            return hours == 1 ? "1 hour left" : "\(hours) hours left"
        }
        let days = max(1, Int((remaining / day).rounded(.up)))
        return days == 1 ? "1 day left" : "\(days) days left"
    }

    static func title(remaining: TimeInterval) -> String {
        "Lodge trial: \(timeLeft(remaining))"
    }

    static func toolbar(_ remaining: TimeInterval) -> String {
        "Trial: \(timeLeft(remaining))"
    }
}

enum LicensePolicy {
    static func freshness(lastValidatedAt: Date, now: Date) -> LicenseFreshness {
        // A stamp in the future means the clock moved back after a check. That does not
        // extend the offline grace: the license is treated as expired until it validates again.
        if lastValidatedAt > now { return .graceExpired }
        let age = now.timeIntervalSince(lastValidatedAt)
        if age < LodgeLicense.revalidateAfter { return .current }
        if age < LodgeLicense.offlineGrace { return .stale }
        return .graceExpired
    }

    static func phase(stored: StoredLicense?, now: Date) -> LicensePhase {
        guard let stored else { return .unlicensed }
        return .licensed(stored, freshness(lastValidatedAt: stored.lastValidatedAt, now: now))
    }

    static func allowsUse(_ phase: LicensePhase) -> Bool {
        switch phase {
        case .trial, .licensed(_, .current), .licensed(_, .stale):
            return true
        case .unlicensed, .licensed(_, .graceExpired):
            return false
        }
    }
}

/// Every sentence the license screens show.
enum LicenseCopy {
    static let section = "License"
    static let price = "Lodge is $10 once, try free 3 days. A license key works on 3 Macs and does not expire."
    static let buy = "Buy Lodge"
    static let activate = "Activate"
    static let deactivate = "Deactivate"
    static let checkAgain = "Check Again"
    static let enterLicense = "Enter License"
    static let enterLicenseKey = "Enter License Key"
    static let keyPrompt = "License key"
    static let thisMac = "This Mac"
    static let prefixError = "License keys start with LODGE."
    static let enterKey = "Enter a license key."
    static let licensed = "This Mac is licensed."
    static let offlineGrace = "This Mac is licensed. Lodge will confirm the license when it is next online."
    static let graceEnded = "Lodge could not confirm this license, and the 14-day offline period has ended."
    static let unlicensed = "Enter the license key from your purchase, or buy Lodge."
    static let checking = "Checking the license…"
    static let unreachable = "Lodge could not reach the license server. Try again when you are online."
    static let activateRejected = "This license could not be activated."
    static let activationLimitReached = "This key is already active on 3 Macs. Deactivate it on another Mac in Lodge Settings, then try again."
    static let keyNotFound = "No license key matches that. Check the key and try again."
    static let unreadableKey = "That license key could not be read. Check it and try again."
    static let validateRejected = "This license is no longer valid on this Mac."
    static let expired = "This license has expired."
    static let unreadable = "Lodge could not read the reply from the license server."
    static let keychainRead = "Lodge could not read the saved license."
    static let keychainWrite = "Lodge could not save the license in the Keychain."

    static func trialStatus(_ days: Int) -> String {
        days == 1 ? "Trial: 1 day left" : "Trial: \(days) days left"
    }

    static func status(for phase: LicensePhase) -> String {
        switch phase {
        case .trial(let days): return trialStatus(days)
        case .unlicensed: return unlicensed
        case .licensed(_, .current): return licensed
        case .licensed(_, .stale): return offlineGrace
        case .licensed(_, .graceExpired): return graceEnded
        }
    }

    static let userFacing = [
        section, price, buy, activate, deactivate, checkAgain, enterLicense, enterLicenseKey, keyPrompt, thisMac,
        trialStatus(1), trialStatus(3),
        prefixError, enterKey, licensed, offlineGrace, graceEnded, unlicensed, checking,
        unreachable, activateRejected, activationLimitReached, keyNotFound, unreadableKey,
        validateRejected, expired, unreadable,
        keychainRead, keychainWrite,
    ]
}

protocol LicenseStore: AnyObject {
    func load() throws -> StoredLicense?
    func save(_ license: StoredLicense) throws
    func clear() throws
    func loadTrial() throws -> TrialRecord?
    func saveTrial(_ record: TrialRecord) throws
}

/// In-memory stand-in for the Keychain. Tests use it. Demo mode uses it so screenshots
/// stay licensed without writing the login Keychain.
final class MemoryLicenseStore: LicenseStore {
    var saved: StoredLicense?
    var trial: TrialRecord?
    func load() throws -> StoredLicense? { saved }
    func save(_ license: StoredLicense) throws { saved = license }
    func clear() throws { saved = nil }
    func loadTrial() throws -> TrialRecord? { trial }
    func saveTrial(_ record: TrialRecord) throws { trial = record }
}

struct LicenseRequest: Equatable, Sendable {
    var url: URL
    var body: Data
}

struct LicenseHTTPResponse: Equatable, Sendable {
    var status: Int
    var body: Data
}

protocol LicenseTransport {
    func post(_ request: LicenseRequest) async throws -> LicenseHTTPResponse
}

enum LicenseHTTP {
    /// Public customer-portal call: JSON in, JSON out, no Authorization header.
    static func urlRequest(for request: LicenseRequest) -> URLRequest {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.httpBody = request.body
        return urlRequest
    }
}

enum LicenseRequestEncoder {
    static func data(key: String, organizationID: String, label: String? = nil, activationID: String? = nil) throws -> Data {
        var object: [String: String] = [
            "key": key,
            "organization_id": organizationID,
        ]
        if let label { object["label"] = label }
        if let activationID { object["activation_id"] = activationID }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}

struct URLSessionLicenseTransport: LicenseTransport {
    var session: URLSession = .shared

    func post(_ request: LicenseRequest) async throws -> LicenseHTTPResponse {
        let urlRequest = LicenseHTTP.urlRequest(for: request)
        let (data, response) = try await session.data(for: urlRequest)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        return LicenseHTTPResponse(status: status, body: data)
    }
}

struct FailingLicenseTransport: LicenseTransport {
    func post(_ request: LicenseRequest) async throws -> LicenseHTTPResponse {
        throw URLError(.notConnectedToInternet)
    }
}

enum LicenseServerResult: Equatable {
    case activated(activationID: String)
    case validated
    case deactivated
    case rejected(String)
    case unavailable(String)
}

enum PolarDate {
    static func parse(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }
}

enum LicenseKeyVerdict: Equatable {
    case granted
    case rejected(String)

    /// `granted` and a missing or future `expires_at` is usable. Polar keys for Lodge
    /// are created without an expiry; a past `expires_at` is still honored.
    static func make(status: String, expiresAt: String?, now: Date) -> LicenseKeyVerdict {
        guard status == "granted" else { return .rejected(LicenseCopy.validateRejected) }
        guard let expiresAt else { return .granted }
        let trimmed = expiresAt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .granted }
        guard let date = PolarDate.parse(trimmed) else { return .rejected(LicenseCopy.unreadable) }
        if date <= now { return .rejected(LicenseCopy.expired) }
        return .granted
    }
}

enum PolarErrorMessage {
    static func extract(from data: Data) -> String? {
        guard !data.isEmpty, let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        guard let object = json as? [String: Any] else { return nil }
        if let detail = object["detail"] as? String {
            let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        if let details = object["detail"] as? [Any] {
            let messages = details.compactMap { item -> String? in
                guard let row = item as? [String: Any], let message = row["msg"] as? String else { return nil }
                let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            if !messages.isEmpty { return messages.joined(separator: " ") }
        }
        return nil
    }
}

private struct PolarKeyPayload: Decodable {
    var status: String
    var expiresAt: String?
    var activation: PolarActivationPayload?

    enum CodingKeys: String, CodingKey {
        case status
        case expiresAt = "expires_at"
        case activation
    }
}

private struct PolarActivationPayload: Decodable {
    var id: String
}

private struct PolarActivatePayload: Decodable {
    var id: String
    var licenseKey: PolarKeyPayload

    enum CodingKeys: String, CodingKey {
        case id
        case licenseKey = "license_key"
    }
}

enum LicenseResponseInterpreter {
    static func interpret(route: LicenseRoute, response: LicenseHTTPResponse, expectedActivationID: String?, now: Date) -> LicenseServerResult {
        guard (200...299).contains(response.status) else { return failure(for: response, route: route) }
        switch route {
        case .activate:
            return interpretActivate(response.body, now: now)
        case .validate:
            return interpretValidate(response.body, expectedActivationID: expectedActivationID, now: now)
        case .deactivate:
            return .deactivated
        }
    }

    private static func interpretActivate(_ body: Data, now: Date) -> LicenseServerResult {
        guard let payload = try? JSONDecoder().decode(PolarActivatePayload.self, from: body) else {
            return .unavailable(LicenseCopy.unreadable)
        }
        switch LicenseKeyVerdict.make(status: payload.licenseKey.status, expiresAt: payload.licenseKey.expiresAt, now: now) {
        case .granted:
            let id = payload.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { return .unavailable(LicenseCopy.unreadable) }
            return .activated(activationID: id)
        case .rejected(let message):
            return .rejected(message)
        }
    }

    private static func interpretValidate(_ body: Data, expectedActivationID: String?, now: Date) -> LicenseServerResult {
        guard let payload = try? JSONDecoder().decode(PolarKeyPayload.self, from: body) else {
            return .unavailable(LicenseCopy.unreadable)
        }
        switch LicenseKeyVerdict.make(status: payload.status, expiresAt: payload.expiresAt, now: now) {
        case .granted:
            if let seen = payload.activation?.id.trimmingCharacters(in: .whitespacesAndNewlines),
               let expected = expectedActivationID, seen != expected {
                return .rejected(LicenseCopy.validateRejected)
            }
            return .validated
        case .rejected(let message):
            return .rejected(message)
        }
    }

    private static func failure(for response: LicenseHTTPResponse, route: LicenseRoute) -> LicenseServerResult {
        let detail = PolarErrorMessage.extract(from: response.body)
        let message = LicenseCopy.serverMessage(status: response.status, detail: detail, route: route)
        if response.status == 408 || response.status == 429 || (500...599).contains(response.status) {
            return .unavailable(LicenseCopy.unreachable)
        }
        if (400...499).contains(response.status) {
            return .rejected(message)
        }
        return .unavailable(LicenseCopy.unreachable)
    }
}

extension LicenseCopy {
    /// Turns a Polar error into something a person can act on.
    static func serverMessage(status: Int, detail: String?, route: LicenseRoute) -> String {
        let lower = detail?.lowercased() ?? ""
        if status == 403, route == .activate,
           lower.contains("activat"),
           lower.contains("limit") || lower.contains("maximum") || lower.contains("exceed") {
            return activationLimitReached
        }
        if status == 403, lower.contains("revok") || lower.contains("disabled") {
            return validateRejected
        }
        if status == 404 { return keyNotFound }
        if status == 422 {
            if let detail, !detail.isEmpty { return detail }
            return unreadableKey
        }
        if let detail, !detail.isEmpty { return detail }
        return route == .activate ? activateRejected : validateRejected
    }
}

struct LicenseClient {
    var transport: any LicenseTransport
    var endpoint: PolarEndpoint

    static var refusing: LicenseClient {
        LicenseClient(transport: FailingLicenseTransport(), endpoint: .live)
    }

    func activate(key: String, label: String, now: Date) async -> LicenseServerResult {
        await send(.activate, key: key, label: label, activationID: nil, now: now)
    }

    func validate(key: String, activationID: String, now: Date) async -> LicenseServerResult {
        await send(.validate, key: key, label: nil, activationID: activationID, now: now)
    }

    func deactivate(key: String, activationID: String, now: Date) async -> LicenseServerResult {
        await send(.deactivate, key: key, label: nil, activationID: activationID, now: now)
    }

    private func send(_ route: LicenseRoute, key: String, label: String?, activationID: String?, now: Date) async -> LicenseServerResult {
        let body: Data
        do {
            body = try LicenseRequestEncoder.data(key: key, organizationID: endpoint.organizationID, label: label, activationID: activationID)
        } catch {
            return .unavailable(LicenseCopy.unreachable)
        }
        let request = LicenseRequest(url: endpoint.url(for: route.rawValue), body: body)
        let response: LicenseHTTPResponse
        do {
            response = try await transport.post(request)
        } catch {
            return .unavailable(LicenseCopy.unreachable)
        }
        return LicenseResponseInterpreter.interpret(route: route, response: response, expectedActivationID: activationID, now: now)
    }
}

enum LicenseJSON {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// Drives activate, the weekly validate, and deactivate.
/// `onChange` fires in `willSet` so a SwiftUI wrapper can call `objectWillChange`.
/// The class itself stays on Foundation so the state tests run on Linux.
@MainActor
final class LicenseController {
    var onChange: (() -> Void)?

    private(set) var phase: LicensePhase {
        willSet { onChange?() }
    }
    var keyDraft = "" {
        willSet { onChange?() }
    }
    private(set) var statusLine: String {
        willSet { onChange?() }
    }
    private(set) var isWorking = false {
        willSet { onChange?() }
    }
    private(set) var banner: String? {
        willSet { onChange?() }
    }

    private let store: any LicenseStore
    private let client: LicenseClient
    private let now: () -> Date
    private let machineLabel: () -> String

    init(store: any LicenseStore, client: LicenseClient, now: @escaping () -> Date = Date.init,
         machineLabel: @escaping () -> String = LicenseController.defaultMachineLabel) {
        self.store = store
        self.client = client
        self.now = now
        self.machineLabel = machineLabel
        self.phase = .unlicensed
        self.statusLine = LicenseCopy.unlicensed
        self.trialRemaining = nil
        self.launchNoticePresented = false
        applyStored()
    }

    var allowsUse: Bool { LicensePolicy.allowsUse(phase) }

    var canDeactivate: Bool {
        if case .licensed = phase { return true }
        return false
    }

    var needsCheck: Bool {
        switch phase {
        case .licensed(_, .stale), .licensed(_, .graceExpired): return true
        default: return false
        }
    }

    var maskedKey: String? {
        guard case .licensed(let stored, _) = phase else { return nil }
        return LicenseKey.mask(stored.key)
    }

    var trialDaysLeft: Int? {
        if case .trial(let days) = phase { return days }
        return nil
    }

    /// Seconds left in the trial. Nil when this Mac is licensed or the trial is over.
    private(set) var trialRemaining: TimeInterval? {
        willSet { onChange?() }
    }
    private(set) var launchNoticePresented = false

    /// Title for the once-per-launch trial note, or nil when it should not appear.
    /// A license clears `trialRemaining`, so this stays nil once this Mac is licensed.
    func launchNoticeTitle(isDemo: Bool) -> String? {
        guard let remaining = trialRemaining else { return nil }
        guard TrialLaunchNotice.shouldPresent(isTrial: true, isLicensed: false, isDemo: isDemo,
                                               alreadyPresented: launchNoticePresented) else { return nil }
        return TrialLaunchNotice.title(remaining: remaining)
    }

    func markLaunchNoticePresented() {
        launchNoticePresented = true
    }

    nonisolated static func defaultMachineLabel() -> String {
        let name = Host.current().localizedName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = (name?.isEmpty == false ? name! : nil) ?? "Mac"
        let label = "Lodge on \(host)"
        if label.count <= 64 { return label }
        return String(label.prefix(64))
    }

    func refresh() async {
        guard !isWorking else { return }
        applyStored()
        guard case .licensed(let stored, let freshness) = phase else { return }
        switch freshness {
        case .current:
            return
        case .stale, .graceExpired:
            break
        }
        isWorking = true
        defer { isWorking = false }
        switch await client.validate(key: stored.key, activationID: stored.activationID, now: now()) {
        case .validated:
            var updated = stored
            updated.lastValidatedAt = now()
            do {
                try store.save(updated)
            } catch {
                banner = LicenseCopy.keychainWrite
                return
            }
            applyStored()
            banner = nil
        case .rejected(let message):
            try? store.clear()
            applyStored()
            banner = message
        case .unavailable:
            // Inside the 14 days, stay quiet: the status line already says Lodge will confirm later.
            if case .graceExpired = freshness {
                banner = LicenseCopy.unreachable
            }
        case .activated, .deactivated:
            banner = LicenseCopy.unreadable
        }
    }

    func activate() async {
        guard !isWorking else { return }
        let key = LicenseKey.normalize(keyDraft)
        guard !key.isEmpty else {
            banner = LicenseCopy.enterKey
            return
        }
        guard LicenseKey.hasLodgePrefix(key) else {
            banner = LicenseCopy.prefixError
            return
        }
        isWorking = true
        defer { isWorking = false }
        switch await client.activate(key: key, label: machineLabel(), now: now()) {
        case .activated(let activationID):
            let stored = StoredLicense(key: key, activationID: activationID, lastValidatedAt: now())
            do {
                try store.save(stored)
            } catch {
                banner = LicenseCopy.keychainWrite
                return
            }
            keyDraft = ""
            applyStored()
            banner = nil
        case .rejected(let message):
            banner = message
        case .unavailable:
            banner = LicenseCopy.unreachable
        case .validated, .deactivated:
            banner = LicenseCopy.unreadable
        }
    }

    func deactivate() async {
        guard !isWorking else { return }
        guard let stored = try? store.load() else {
            applyStored()
            return
        }
        isWorking = true
        defer { isWorking = false }
        switch await client.deactivate(key: stored.key, activationID: stored.activationID, now: now()) {
        case .deactivated:
            try? store.clear()
            applyStored()
            banner = nil
        case .rejected(let message):
            // Polar no longer has this activation (or refused the key). Drop the local copy.
            try? store.clear()
            applyStored()
            banner = message
        case .unavailable:
            applyStored()
            banner = LicenseCopy.unreachable
        case .activated, .validated:
            banner = LicenseCopy.unreadable
        }
    }

    private func applyStored() {
        trialRemaining = nil
        let storedLicense: StoredLicense?
        do {
            storedLicense = try store.load()
        } catch {
            phase = .unlicensed
            statusLine = LicenseCopy.status(for: phase)
            banner = LicenseCopy.keychainRead
            return
        }
        if let storedLicense {
            phase = LicensePolicy.phase(stored: storedLicense, now: now())
            statusLine = LicenseCopy.status(for: phase)
            return
        }
        let existing: TrialRecord?
        do {
            existing = try store.loadTrial()
        } catch {
            phase = .unlicensed
            statusLine = LicenseCopy.status(for: phase)
            banner = LicenseCopy.keychainRead
            return
        }
        let next = TrialPolicy.advance(record: existing, now: now())
        if next != existing {
            do {
                try store.saveTrial(next)
            } catch {
                // A trial that was never written down can be restarted by reinstalling.
                if existing == nil {
                    phase = .unlicensed
                    statusLine = LicenseCopy.status(for: phase)
                    banner = LicenseCopy.keychainWrite
                    return
                }
            }
        }
        switch TrialPolicy.access(record: next, now: now()) {
        case .active(let days):
            phase = .trial(daysLeft: days)
            trialRemaining = TrialPolicy.remaining(record: next, now: now())
        case .expired:
            phase = .unlicensed
        }
        statusLine = LicenseCopy.status(for: phase)
    }
}
