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
    func invalidateCachedToken() async
}

extension AuthServiceProtocol {
    func retryingOnUnauthorized<T: Sendable>(credentials: CopilotCredentials, operation: @Sendable (CopilotCredentials) async throws -> T) async throws -> T {
        do {
            return try await operation(credentials)
        } catch CopilotAPIError.unauthorized {
            await invalidateCachedToken()
            let newCredentials = try await getValidCopilotToken()
            return try await operation(newCredentials)
        }
    }
}

public actor GitHubCLIAuthService: AuthServiceProtocol {
    private let processRunner: ProcessRunnerProtocol
    private let logger: LoggerProtocol
    private let httpClient: HTTPClientProtocol
    private let deviceFlowService: DeviceFlowServiceProtocol
    private var cachedToken: CopilotToken?

    private static let ghPaths = ["/usr/local/bin/gh", "/opt/homebrew/bin/gh", "/usr/bin/gh"]

    public init(
        processRunner: ProcessRunnerProtocol,
        logger: LoggerProtocol,
        deviceFlowService: DeviceFlowServiceProtocol,
        httpClient: HTTPClientProtocol
    ) {
        self.processRunner = processRunner
        self.logger = logger
        self.deviceFlowService = deviceFlowService
        self.httpClient = httpClient
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

    public func invalidateCachedToken() {
        cachedToken = nil
        logger.debug("Cached Copilot token invalidated")
    }

    private func exchangeForCopilotToken(githubToken: String) async throws -> CopilotToken {
        let endpoint = CopilotTokenEndpoint(githubToken: githubToken)

        let response: DataResponse
        do {
            response = try await httpClient.execute(endpoint)
        } catch {
            throw AuthServiceError.tokenExchangeFailed("Network error: \(error.localizedDescription)")
        }

        if response.statusCode == 404 {
            throw AuthServiceError.copilotSubscriptionRequired
        }

        guard response.statusCode == 200 else {
            let body = String(data: response.data, encoding: .utf8) ?? ""
            throw AuthServiceError.tokenExchangeFailed(
                "HTTP \(response.statusCode): \(body)"
            )
        }

        let tokenResponse: CopilotTokenResponse
        do {
            tokenResponse = try JSONDecoder().decode(CopilotTokenResponse.self, from: response.data)
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
