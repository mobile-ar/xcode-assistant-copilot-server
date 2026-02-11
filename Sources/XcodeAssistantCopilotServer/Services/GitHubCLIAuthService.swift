import Foundation

public struct CopilotCredentials: Sendable {
    public let token: String
    public let apiEndpoint: String

    public init(token: String, apiEndpoint: String) {
        self.token = token
        self.apiEndpoint = apiEndpoint
    }
}

public enum AuthServiceError: Error, CustomStringConvertible {
    case gitHubCLINotFound
    case gitHubCLIFailed(String)
    case tokenExchangeFailed(String)
    case notAuthenticated
    case copilotSubscriptionRequired

    public var description: String {
        switch self {
        case .gitHubCLINotFound:
            "GitHub CLI (gh) not found. Install it from https://cli.github.com"
        case .gitHubCLIFailed(let message):
            "GitHub CLI failed: \(message)"
        case .tokenExchangeFailed(let message):
            "Copilot token exchange failed: \(message)"
        case .notAuthenticated:
            "Not authenticated. Run `gh auth login` first."
        case .copilotSubscriptionRequired:
            "GitHub Copilot subscription required. Visit https://github.com/settings/copilot to check your subscription."
        }
    }
}

public protocol AuthServiceProtocol: Sendable {
    func getGitHubToken() async throws -> String
    func getValidCopilotToken() async throws -> CopilotCredentials
}

public actor GitHubCLIAuthService: AuthServiceProtocol {
    private let processRunner: ProcessRunnerProtocol
    private let logger: LoggerProtocol
    private let session: URLSession
    private let deviceFlowService: DeviceFlowServiceProtocol
    private var cachedToken: CopilotToken?

    private static let tokenEndpoint = "https://api.github.com/copilot_internal/v2/token"
    private static let ghPaths = ["/usr/local/bin/gh", "/opt/homebrew/bin/gh", "/usr/bin/gh"]

    public init(
        processRunner: ProcessRunnerProtocol,
        logger: LoggerProtocol,
        deviceFlowService: DeviceFlowServiceProtocol,
        session: URLSession = .shared
    ) {
        self.processRunner = processRunner
        self.logger = logger
        self.deviceFlowService = deviceFlowService
        self.session = session
    }

    public func getGitHubToken() async throws -> String {
        if let storedToken = try? deviceFlowService.loadStoredToken() {
            logger.debug("Using stored OAuth token from device flow")
            return storedToken.accessToken
        }

        let ghPath = try await findGitHubCLI()
        let result = try await processRunner.run(executablePath: ghPath, arguments: ["auth", "token"])

        guard result.succeeded else {
            if result.stderr.contains("not logged") || result.stderr.contains("auth login") {
                throw AuthServiceError.notAuthenticated
            }
            throw AuthServiceError.gitHubCLIFailed(result.stderr)
        }

        let token = result.stdout
        guard !token.isEmpty else {
            throw AuthServiceError.notAuthenticated
        }

        return token
    }

    public func getValidCopilotToken() async throws -> CopilotCredentials {
        if let cached = cachedToken, cached.isValid {
            return CopilotCredentials(token: cached.token, apiEndpoint: cached.apiEndpoint)
        }

        logger.debug("Refreshing Copilot token")

        let githubToken = try await getGitHubToken()

        do {
            let copilotToken = try await exchangeForCopilotToken(githubToken: githubToken)
            cachedToken = copilotToken
            logger.info("Copilot token acquired (endpoint: \(copilotToken.apiEndpoint)), expires at \(copilotToken.expiresAt)")
            return CopilotCredentials(token: copilotToken.token, apiEndpoint: copilotToken.apiEndpoint)
        } catch AuthServiceError.copilotSubscriptionRequired {
            logger.info("Token from gh CLI does not have Copilot access. Starting device code flow...")

            if (try? deviceFlowService.loadStoredToken()) != nil {
                logger.debug("Found a stored OAuth token, deleting it as it may be stale")
                try? deviceFlowService.deleteStoredToken()
            }

            let oauthToken = try await deviceFlowService.performDeviceFlow()

            let copilotToken = try await exchangeForCopilotToken(githubToken: oauthToken.accessToken)
            cachedToken = copilotToken
            logger.info("Copilot token acquired via device flow (endpoint: \(copilotToken.apiEndpoint)), expires at \(copilotToken.expiresAt)")
            return CopilotCredentials(token: copilotToken.token, apiEndpoint: copilotToken.apiEndpoint)
        }
    }

    private func exchangeForCopilotToken(githubToken: String) async throws -> CopilotToken {
        guard let url = URL(string: Self.tokenEndpoint) else {
            throw AuthServiceError.tokenExchangeFailed("Invalid token endpoint URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("token \(githubToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Xcode/26.0", forHTTPHeaderField: "Editor-Version")
        request.setValue("copilot-xcode/0.1.0", forHTTPHeaderField: "Editor-Plugin-Version")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AuthServiceError.tokenExchangeFailed("Network error: \(error.localizedDescription)")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthServiceError.tokenExchangeFailed("Invalid response")
        }

        if httpResponse.statusCode == 404 {
            throw AuthServiceError.copilotSubscriptionRequired
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AuthServiceError.tokenExchangeFailed(
                "HTTP \(httpResponse.statusCode): \(body)"
            )
        }

        let tokenResponse: CopilotTokenResponse
        do {
            tokenResponse = try JSONDecoder().decode(CopilotTokenResponse.self, from: data)
        } catch {
            throw AuthServiceError.tokenExchangeFailed("Failed to decode response: \(error.localizedDescription)")
        }

        return tokenResponse.toCopilotToken()
    }

    private func findGitHubCLI() async throws -> String {
        for path in Self.ghPaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        let whichResult = try? await processRunner.run(executablePath: "/usr/bin/which", arguments: ["gh"])
        if let whichResult, whichResult.succeeded, !whichResult.stdout.isEmpty {
            return whichResult.stdout
        }

        throw AuthServiceError.gitHubCLINotFound
    }
}