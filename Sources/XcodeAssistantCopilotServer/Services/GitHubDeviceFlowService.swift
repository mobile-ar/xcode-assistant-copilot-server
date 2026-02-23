import Foundation

public enum DeviceFlowError: Error, CustomStringConvertible {
    case requestFailed(String)
    case expired
    case accessDenied
    case networkError(String)
    case invalidResponse(String)
    case tokenStorageFailed(String)

    public var description: String {
        switch self {
        case .requestFailed(let message):
            "Device flow request failed: \(message)"
        case .expired:
            "Device code expired. Please try again."
        case .accessDenied:
            "Access denied. Please authorize the application when prompted."
        case .networkError(let message):
            "Network error during device flow: \(message)"
        case .invalidResponse(let message):
            "Invalid response during device flow: \(message)"
        case .tokenStorageFailed(let message):
            "Failed to store OAuth token: \(message)"
        }
    }
}

public protocol DeviceFlowServiceProtocol: Sendable {
    func loadStoredToken() throws -> OAuthToken?
    func performDeviceFlow() async throws -> OAuthToken
    func deleteStoredToken() throws
}

public struct GitHubDeviceFlowService: DeviceFlowServiceProtocol {
    private let session: URLSession
    private let logger: LoggerProtocol
    private let tokenStoragePath: String

    static let clientID = "Iv1.b507a08c87ecfe98"
    private static let deviceCodeURL = "https://github.com/login/device/code"
    private static let accessTokenURL = "https://github.com/login/oauth/access_token"
    private static let configDirectoryName = "xcode-assistant-copilot-server"
    private static let tokenFileName = "github-token.json"

    public init(logger: LoggerProtocol, session: URLSession = .shared, tokenStoragePath: String? = nil) {
        self.logger = logger
        self.session = session
        self.tokenStoragePath = tokenStoragePath ?? Self.defaultTokenStoragePath()
    }

    public func loadStoredToken() throws -> OAuthToken? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: tokenStoragePath) else {
            logger.debug("No stored OAuth token found at \(tokenStoragePath)")
            return nil
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: tokenStoragePath))
        let token = try JSONDecoder().decode(OAuthToken.self, from: data)
        logger.debug("Loaded stored OAuth token")
        return token
    }

    public func performDeviceFlow() async throws -> OAuthToken {
        let deviceCode = try await requestDeviceCode()

        logger.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        logger.info("GitHub authentication required.")
        logger.info("Please visit: \(deviceCode.verificationUri)")
        logger.info("and enter code: \(deviceCode.userCode)")
        logger.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        let token = try await pollForToken(deviceCode: deviceCode)

        try storeToken(token)
        logger.info("OAuth token obtained and stored successfully")
        return token
    }

    public func deleteStoredToken() throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: tokenStoragePath) {
            try fileManager.removeItem(atPath: tokenStoragePath)
            logger.debug("Deleted stored OAuth token")
        }
    }

    private func requestDeviceCode() async throws -> DeviceCodeResponse {
        guard let url = URL(string: Self.deviceCodeURL) else {
            throw DeviceFlowError.requestFailed("Invalid device code URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let body: [String: String] = [
            "client_id": Self.clientID,
            "scope": "user:email"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw DeviceFlowError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DeviceFlowError.invalidResponse("Non-HTTP response received")
        }

        guard httpResponse.statusCode == 200 else {
            let responseBody = String(data: data, encoding: .utf8) ?? ""
            throw DeviceFlowError.requestFailed("HTTP \(httpResponse.statusCode): \(responseBody)")
        }

        do {
            return try JSONDecoder().decode(DeviceCodeResponse.self, from: data)
        } catch {
            throw DeviceFlowError.invalidResponse("Failed to decode device code response: \(error.localizedDescription)")
        }
    }

    private func pollForToken(deviceCode: DeviceCodeResponse) async throws -> OAuthToken {
        let pollInterval = max(deviceCode.interval, 5)
        let deadline = Date.now.addingTimeInterval(TimeInterval(deviceCode.expiresIn))

        while Date.now < deadline {
            try await Task.sleep(for: .seconds(pollInterval))

            let pollResponse = try await pollAccessToken(deviceCode: deviceCode.deviceCode)

            if let error = pollResponse.error {
                switch error {
                case "authorization_pending":
                    logger.debug("Waiting for user authorization...")
                    continue
                case "slow_down":
                    logger.debug("Rate limited, slowing down...")
                    try await Task.sleep(for: .seconds(5))
                    continue
                case "expired_token":
                    throw DeviceFlowError.expired
                case "access_denied":
                    throw DeviceFlowError.accessDenied
                default:
                    let description = pollResponse.errorDescription ?? error
                    throw DeviceFlowError.requestFailed(description)
                }
            }

            if let token = pollResponse.toOAuthToken() {
                return token
            }
        }

        throw DeviceFlowError.expired
    }

    private func pollAccessToken(deviceCode: String) async throws -> DeviceCodePollResponse {
        guard let url = URL(string: Self.accessTokenURL) else {
            throw DeviceFlowError.requestFailed("Invalid access token URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let body: [String: String] = [
            "client_id": Self.clientID,
            "device_code": deviceCode,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw DeviceFlowError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DeviceFlowError.invalidResponse("Non-HTTP response received")
        }

        guard httpResponse.statusCode == 200 else {
            let responseBody = String(data: data, encoding: .utf8) ?? ""
            throw DeviceFlowError.requestFailed("HTTP \(httpResponse.statusCode): \(responseBody)")
        }

        do {
            return try JSONDecoder().decode(DeviceCodePollResponse.self, from: data)
        } catch {
            throw DeviceFlowError.invalidResponse("Failed to decode poll response: \(error.localizedDescription)")
        }
    }

    private func storeToken(_ token: OAuthToken) throws {
        let directory = URL(fileURLWithPath: tokenStoragePath).deletingLastPathComponent().path
        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: directory) {
            do {
                try fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)
            } catch {
                throw DeviceFlowError.tokenStorageFailed("Cannot create directory \(directory): \(error.localizedDescription)")
            }
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data: Data
        do {
            data = try encoder.encode(token)
        } catch {
            throw DeviceFlowError.tokenStorageFailed("Cannot encode token: \(error.localizedDescription)")
        }

        let fileURL = URL(fileURLWithPath: tokenStoragePath)
        do {
            try data.write(to: fileURL, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: tokenStoragePath
            )
        } catch {
            throw DeviceFlowError.tokenStorageFailed("Cannot write token file: \(error.localizedDescription)")
        }
    }

    private static func defaultTokenStoragePath() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.config/\(configDirectoryName)/\(tokenFileName)"
    }
}