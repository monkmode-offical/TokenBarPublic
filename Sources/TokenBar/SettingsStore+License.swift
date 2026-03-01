import AppKit
import Foundation

enum LicenseState: String, Sendable {
    case unlicensed
    case verifying
    case active
    case invalid
    case revoked
    case deviceLimit
    case error

    var isActive: Bool {
        self == .active
    }

    var defaultMessage: String {
        switch self {
        case .unlicensed:
            "Enter your license key to unlock TokenBar."
        case .verifying:
            "Verifying license…"
        case .active:
            "License active."
        case .invalid:
            "License key is invalid."
        case .revoked:
            "License has been revoked."
        case .deviceLimit:
            "This license is already active on another device."
        case .error:
            "Could not verify license."
        }
    }
}

private struct LicenseVerifyResponse: Decodable {
    let valid: Bool
    let status: String?
    let reason: String?
    let message: String?
    let licenseKey: String?
    let maxDevices: Int?
    let activeDevices: Int?

    private enum CodingKeys: String, CodingKey {
        case valid
        case status
        case reason
        case message
        case licenseKey = "license_key"
        case maxDevices = "max_devices"
        case activeDevices = "active_devices"
    }
}

private struct LicenseCheckoutSessionResponse: Decodable {
    let checkoutURL: String

    private enum CodingKeys: String, CodingKey {
        case checkoutURL = "checkout_url"
    }
}

private struct LicenseAPIErrorResponse: Decodable {
    let error: String?
    let message: String?
}

private enum LicenseServiceError: LocalizedError {
    case invalidServerURL
    case invalidCheckoutURL
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            "Invalid license server URL"
        case .invalidCheckoutURL:
            "Server returned an invalid checkout URL"
        case .invalidResponse:
            "Server returned an invalid response"
        case let .server(message):
            message
        }
    }
}

enum LicenseService {
    static let defaultServerURL = "https://tokenbar.site"

    static func normalizedServerURL(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return self.defaultServerURL }
        let suffixStripped = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        guard !suffixStripped.isEmpty else { return self.defaultServerURL }
        return suffixStripped
    }

    fileprivate static func verify(
        serverURLString: String,
        licenseKey: String,
        deviceID: String) async throws -> LicenseVerifyResponse
    {
        let endpoint = try self.endpoint(path: "/api/license/verify", serverURLString: serverURLString)
        let payload: [String: String] = [
            "license_key": licenseKey,
            "device_id": deviceID,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LicenseServiceError.invalidResponse
        }

        let decoder = JSONDecoder()
        if let verify = try? decoder.decode(LicenseVerifyResponse.self, from: responseData) {
            if (200..<300).contains(httpResponse.statusCode) || verify.valid == false {
                return verify
            }
        }

        if let apiError = try? decoder.decode(LicenseAPIErrorResponse.self, from: responseData) {
            throw LicenseServiceError.server(apiError.message ?? apiError.error ?? "License verification failed")
        }

        throw LicenseServiceError.server("License verification failed with HTTP \(httpResponse.statusCode)")
    }

    static func createCheckoutSession(
        serverURLString: String,
        deviceID: String) async throws -> URL
    {
        let endpoint = try self.endpoint(path: "/api/checkout/session", serverURLString: serverURLString)
        let payload: [String: String] = ["device_id": deviceID]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LicenseServiceError.invalidResponse
        }

        let decoder = JSONDecoder()
        guard (200..<300).contains(httpResponse.statusCode) else {
            if let apiError = try? decoder.decode(LicenseAPIErrorResponse.self, from: responseData) {
                throw LicenseServiceError
                    .server(apiError.message ?? apiError.error ?? "Checkout session creation failed")
            }
            throw LicenseServiceError.server("Checkout session creation failed with HTTP \(httpResponse.statusCode)")
        }

        guard let decoded = try? decoder.decode(LicenseCheckoutSessionResponse.self, from: responseData),
              let checkoutURL = URL(string: decoded.checkoutURL)
        else {
            throw LicenseServiceError.invalidCheckoutURL
        }

        return checkoutURL
    }

    static func fallbackCheckoutURL(serverURLString: String) -> URL? {
        let normalized = self.normalizedServerURL(serverURLString)
        guard let baseURL = URL(string: normalized) else { return nil }
        return URL(string: "/checkout", relativeTo: baseURL)?.absoluteURL
    }

    private static func endpoint(path: String, serverURLString: String) throws -> URL {
        let normalized = self.normalizedServerURL(serverURLString)
        guard let baseURL = URL(string: normalized) else {
            throw LicenseServiceError.invalidServerURL
        }
        let resolved = URL(string: path, relativeTo: baseURL)?.absoluteURL
        guard let resolved else {
            throw LicenseServiceError.invalidServerURL
        }
        return resolved
    }
}

private enum LicenseDeviceIdentity {
    private static let deviceDefaultsKey = "licenseDeviceID"

    static func resolve(userDefaults: UserDefaults) -> String {
        if let existing = userDefaults.string(forKey: self.deviceDefaultsKey)?.trimmingCharacters(
            in: .whitespacesAndNewlines),
            !existing.isEmpty
        {
            return existing
        }

        let generated = UUID().uuidString.lowercased()
        userDefaults.set(generated, forKey: self.deviceDefaultsKey)
        return generated
    }
}

extension SettingsStore {
    private static let licenseVerificationTTL: TimeInterval = 6 * 60 * 60

    private static func envFlagEnabled(_ value: String?) -> Bool {
        guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !normalized.isEmpty
        else {
            return false
        }
        return ["1", "true", "yes", "on"].contains(normalized)
    }

    var licenseState: LicenseState {
        get { LicenseState(rawValue: self.licenseStateRaw) ?? .unlicensed }
        set { self.licenseStateRaw = newValue.rawValue }
    }

    var isLicenseEnforcementEnabled: Bool {
        if Self.isRunningTests { return false }
        let env = ProcessInfo.processInfo.environment
        if Self.envFlagEnabled(env["TOKENBAR_SKIP_LICENSE"]) { return false }
        return true
    }

    var isLicenseUnlocked: Bool {
        !self.isLicenseEnforcementEnabled || self.licenseState.isActive
    }

    var licenseDeviceID: String {
        LicenseDeviceIdentity.resolve(userDefaults: self.userDefaults)
    }

    func activateLicenseKey(_ rawKey: String) async {
        self.licenseKey = Self.normalizeLicenseKey(rawKey)
        await self.verifyStoredLicenseIfNeeded(force: true)
    }

    func clearLicenseKey() {
        self.licenseKey = ""
        self.licenseState = .unlicensed
        self.licenseStatusMessage = LicenseState.unlicensed.defaultMessage
        self.licenseLastVerifiedAt = nil
    }

    func verifyStoredLicenseIfNeeded(force: Bool = false) async {
        guard self.isLicenseEnforcementEnabled else {
            self.licenseState = .active
            self.licenseStatusMessage = "License checks disabled by environment."
            return
        }

        let normalizedKey = Self.normalizeLicenseKey(self.licenseKey)
        if normalizedKey.isEmpty {
            self.licenseState = .unlicensed
            self.licenseStatusMessage = LicenseState.unlicensed.defaultMessage
            self.licenseLastVerifiedAt = nil
            return
        }

        if self.licenseState == .verifying, !force {
            return
        }

        if !force,
           let lastVerifiedAt = self.licenseLastVerifiedAt,
           Date().timeIntervalSince(lastVerifiedAt) < Self.licenseVerificationTTL
        {
            return
        }

        self.licenseState = .verifying
        self.licenseStatusMessage = LicenseState.verifying.defaultMessage

        do {
            let response = try await LicenseService.verify(
                serverURLString: self.licenseServerURL,
                licenseKey: normalizedKey,
                deviceID: self.licenseDeviceID)
            self.licenseState = Self.licenseState(from: response)
            self.licenseStatusMessage = Self.licenseMessage(from: response)
            self.licenseLastVerifiedAt = Date()
            self.licenseKey = normalizedKey
        } catch {
            self.licenseState = .error
            self.licenseStatusMessage = error.localizedDescription
        }
    }

    func startLicenseCheckout() async {
        self.licenseState = .verifying
        self.licenseStatusMessage = "Opening checkout…"

        do {
            let checkoutURL = try await LicenseService.createCheckoutSession(
                serverURLString: self.licenseServerURL,
                deviceID: self.licenseDeviceID)
            guard NSWorkspace.shared.open(checkoutURL) else {
                throw LicenseServiceError.server("Could not open checkout URL.")
            }
            self.licenseStatusMessage = "Checkout opened in your browser."
        } catch {
            if let fallbackURL = LicenseService.fallbackCheckoutURL(serverURLString: self.licenseServerURL),
               NSWorkspace.shared.open(fallbackURL)
            {
                self.licenseState = .error
                self.licenseStatusMessage = "Could not create checkout session (\(error.localizedDescription)). " +
                    "Opened the purchase page instead."
                return
            }

            self.licenseState = .error
            self.licenseStatusMessage = error.localizedDescription
        }
    }

    private static func normalizeLicenseKey(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: " ", with: "")
    }

    private static func licenseState(from response: LicenseVerifyResponse) -> LicenseState {
        if response.valid {
            return .active
        }

        let normalizedReason = (response.reason ?? "").lowercased()
        switch normalizedReason {
        case "refund", "dispute", "revoked":
            return .revoked
        case "device_limit":
            return .deviceLimit
        case "not_found", "missing_license", "missing_device", "invalid":
            return .invalid
        default:
            if (response.status ?? "").lowercased() == "revoked" {
                return .revoked
            }
            return .invalid
        }
    }

    private static func licenseMessage(from response: LicenseVerifyResponse) -> String {
        if let message = response.message?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty {
            return message
        }
        let state = self.licenseState(from: response)
        return state.defaultMessage
    }
}
