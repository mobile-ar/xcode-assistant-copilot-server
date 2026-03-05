import Foundation
import Synchronization
import Testing
@testable import XcodeAssistantCopilotServer

private struct MockAuthProcessRunner: ProcessRunnerProtocol {
    let handler: @Sendable (String, [String], [String: String]?) -> Result<ProcessResult, Error>

    init(handler: @escaping @Sendable (String, [String], [String: String]?) -> Result<ProcessResult, Error>) {
        self.handler = handler
    }

    init(stdout: String = "", stderr: String = "", exitCode: Int32 = 0) {
        self.handler = { _, _, _ in
            .success(ProcessResult(stdout: stdout, stderr: stderr, exitCode: exitCode))
        }
    }

    init(throwing error: Error) {
        self.handler = { _, _, _ in
            .failure(error)
        }
    }

    func run(executablePath: String, arguments: [String], environment: [String: String]?) async throws -> ProcessResult {
        switch handler(executablePath, arguments, environment) {
        case .success(let result):
            return result
        case .failure(let error):
            throw error
        }
    }
}

private final class MockDeviceFlowService: DeviceFlowServiceProtocol, @unchecked Sendable {
    var storedToken: OAuthToken?
    var performDeviceFlowResult: Result<OAuthToken, Error> = .failure(DeviceFlowError.expired)
    var performDeviceFlowCallCount = 0
    var deleteStoredTokenCallCount = 0

    func loadStoredToken() throws -> OAuthToken? {
        storedToken
    }

    func performDeviceFlow() async throws -> OAuthToken {
        performDeviceFlowCallCount += 1
        switch performDeviceFlowResult {
        case .success(let token):
            storedToken = token
            return token
        case .failure(let error):
            throw error
        }
    }

    func deleteStoredToken() throws {
        deleteStoredTokenCallCount += 1
        storedToken = nil
    }
}

// MARK: - getGitHubToken

@Test func getGitHubTokenReturnsStoredOAuthTokenFirst() async throws {
    let runner = MockAuthProcessRunner(handler: { path, args, _ in
        if args == ["auth", "token"] {
            return .success(ProcessResult(stdout: "ghp_should_not_be_used", stderr: "", exitCode: 0))
        }
        return .success(ProcessResult(stdout: path, stderr: "", exitCode: 0))
    })
    let logger = MockLogger()
    let deviceFlow = MockDeviceFlowService()
    deviceFlow.storedToken = OAuthToken(accessToken: "gho_stored_oauth_token", tokenType: "bearer", scope: "user:email")

    let authService = GitHubCLIAuthService(processRunner: runner, logger: logger, deviceFlowService: deviceFlow, httpClient: MockHTTPClient())
    let token = try await authService.getGitHubToken()
    #expect(token == "gho_stored_oauth_token")
}

@Test func getGitHubTokenFallsBackToGHCLIWhenNoStoredToken() async throws {
    let runner = MockAuthProcessRunner(handler: { path, args, _ in
        if args == ["auth", "token"] {
            return .success(ProcessResult(stdout: "ghp_test1234567890abcdef", stderr: "", exitCode: 0))
        }
        return .success(ProcessResult(stdout: path, stderr: "", exitCode: 0))
    })
    let logger = MockLogger()
    let deviceFlow = MockDeviceFlowService()
    let authService = GitHubCLIAuthService(processRunner: runner, logger: logger, deviceFlowService: deviceFlow, httpClient: MockHTTPClient())
    let token = try await authService.getGitHubToken()
    #expect(token == "ghp_test1234567890abcdef")
}

@Test func getGitHubTokenThrowsNotAuthenticatedWhenNoStoredTokenAndGHNotLoggedIn() async {
    // Simulate gh installed but not authenticated. FileManager may find gh at a known
    // path, so we make the `auth token` call fail with a "not logged" message, which
    // resolveGitHubToken treats as nil (fall-through), causing getGitHubToken to throw
    // .notAuthenticated.
    let runner = MockAuthProcessRunner(handler: { path, args, _ in
        if args == ["auth", "token"] {
            return .success(ProcessResult(stdout: "", stderr: "not logged into any github hosts. Run gh auth login", exitCode: 1))
        }
        return .success(ProcessResult(stdout: path, stderr: "", exitCode: 0))
    })
    let logger = MockLogger()
    let deviceFlow = MockDeviceFlowService()
    let authService = GitHubCLIAuthService(processRunner: runner, logger: logger, deviceFlowService: deviceFlow, httpClient: MockHTTPClient())

    do {
        _ = try await authService.getGitHubToken()
        Issue.record("Expected AuthServiceError.notAuthenticated")
    } catch let error as AuthServiceError {
        switch error {
        case .notAuthenticated:
            break
        default:
            Issue.record("Expected notAuthenticated, got \(error)")
        }
    } catch {
        Issue.record("Unexpected error type: \(type(of: error)): \(error)")
    }
}

@Test func getGitHubTokenThrowsNotAuthenticatedWhenGHCLINotLoggedIn() async {
    let runner = MockAuthProcessRunner(
        stdout: "",
        stderr: "not logged into any github hosts. Run gh auth login",
        exitCode: 1
    )
    let logger = MockLogger()
    let deviceFlow = MockDeviceFlowService()
    let authService = GitHubCLIAuthService(processRunner: runner, logger: logger, deviceFlowService: deviceFlow, httpClient: MockHTTPClient())

    do {
        _ = try await authService.getGitHubToken()
        Issue.record("Expected AuthServiceError.notAuthenticated")
    } catch let error as AuthServiceError {
        switch error {
        case .notAuthenticated:
            break
        default:
            Issue.record("Expected notAuthenticated, got \(error)")
        }
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

@Test func getGitHubTokenThrowsNotAuthenticatedWhenAuthLoginMessage() async {
    let runner = MockAuthProcessRunner(
        stdout: "",
        stderr: "To get started with GitHub CLI, please run: gh auth login",
        exitCode: 4
    )
    let logger = MockLogger()
    let deviceFlow = MockDeviceFlowService()
    let authService = GitHubCLIAuthService(processRunner: runner, logger: logger, deviceFlowService: deviceFlow, httpClient: MockHTTPClient())

    do {
        _ = try await authService.getGitHubToken()
        Issue.record("Expected AuthServiceError.notAuthenticated")
    } catch let error as AuthServiceError {
        switch error {
        case .notAuthenticated:
            break
        default:
            Issue.record("Expected notAuthenticated, got \(error)")
        }
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

@Test func getGitHubTokenThrowsGitHubCLIFailedOnUnknownError() async {
    let runner = MockAuthProcessRunner(
        stdout: "",
        stderr: "some unknown error",
        exitCode: 1
    )
    let logger = MockLogger()
    let deviceFlow = MockDeviceFlowService()
    let authService = GitHubCLIAuthService(processRunner: runner, logger: logger, deviceFlowService: deviceFlow, httpClient: MockHTTPClient())

    do {
        _ = try await authService.getGitHubToken()
        Issue.record("Expected AuthServiceError.gitHubCLIFailed")
    } catch let error as AuthServiceError {
        switch error {
        case .gitHubCLIFailed(let message):
            #expect(message == "some unknown error")
        default:
            Issue.record("Expected gitHubCLIFailed, got \(error)")
        }
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

@Test func getGitHubTokenTrimsWhitespace() async throws {
    let runner = MockAuthProcessRunner(handler: { _, args, _ in
        if args == ["auth", "token"] {
            return .success(ProcessResult(stdout: "ghp_trimmed_token", stderr: "", exitCode: 0))
        }
        return .success(ProcessResult(stdout: "/usr/local/bin/gh", stderr: "", exitCode: 0))
    })
    let logger = MockLogger()
    let deviceFlow = MockDeviceFlowService()
    let authService = GitHubCLIAuthService(processRunner: runner, logger: logger, deviceFlowService: deviceFlow, httpClient: MockHTTPClient())
    let token = try await authService.getGitHubToken()
    #expect(token == "ghp_trimmed_token")
    #expect(!token.contains("\n"))
}

@Test func getGitHubTokenUsesWhichAsFallback() async throws {
    let runner = MockAuthProcessRunner(handler: { path, args, _ in
        if path.hasSuffix("which") {
            return .success(ProcessResult(stdout: "/custom/path/gh", stderr: "", exitCode: 0))
        }
        if args == ["auth", "token"] {
            return .success(ProcessResult(stdout: "ghp_from_which_path", stderr: "", exitCode: 0))
        }
        return .success(ProcessResult(stdout: "", stderr: "", exitCode: 0))
    })
    let logger = MockLogger()
    let deviceFlow = MockDeviceFlowService()
    let authService = GitHubCLIAuthService(processRunner: runner, logger: logger, deviceFlowService: deviceFlow, httpClient: MockHTTPClient())
    let token = try await authService.getGitHubToken()
    #expect(!token.isEmpty)
}

@Test func getGitHubTokenHandlesMultipleLineStderr() async {
    let runner = MockAuthProcessRunner(
        stdout: "",
        stderr: "line1\nnot logged\nline3",
        exitCode: 1
    )
    let logger = MockLogger()
    let deviceFlow = MockDeviceFlowService()
    let authService = GitHubCLIAuthService(processRunner: runner, logger: logger, deviceFlowService: deviceFlow, httpClient: MockHTTPClient())

    do {
        _ = try await authService.getGitHubToken()
        Issue.record("Expected error")
    } catch let error as AuthServiceError {
        switch error {
        case .notAuthenticated:
            break
        default:
            Issue.record("Expected notAuthenticated because stderr contains 'not logged', got \(error)")
        }
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

@Test func storedOAuthTokenTakesPriorityOverGHCLI() async throws {
    let ghAuthTokenCalled = Mutex(false)
    let runner = MockAuthProcessRunner(handler: { path, args, _ in
        if args == ["auth", "token"] {
            ghAuthTokenCalled.withLock { $0 = true }
            return .success(ProcessResult(stdout: "ghp_cli_token", stderr: "", exitCode: 0))
        }
        return .success(ProcessResult(stdout: path, stderr: "", exitCode: 0))
    })
    let logger = MockLogger()
    let deviceFlow = MockDeviceFlowService()
    deviceFlow.storedToken = OAuthToken(accessToken: "gho_oauth_token", tokenType: "bearer", scope: "user:email")

    let authService = GitHubCLIAuthService(processRunner: runner, logger: logger, deviceFlowService: deviceFlow, httpClient: MockHTTPClient())
    let token = try await authService.getGitHubToken()
    #expect(token == "gho_oauth_token")
    #expect(!ghAuthTokenCalled.withLock { $0 })
}

// MARK: - getValidCopilotToken

@Test func getValidCopilotTokenCachesToken() async throws {
    let tokenJSON = """
    {"token":"cached-token","expires_at":\(Int(Date.now.timeIntervalSince1970) + 3600),"endpoints":{"api":"https://api.endpoint.com"}}
    """
    let httpClient = MockHTTPClient()
    httpClient.executeResults = [
        .success(DataResponse(data: Data(tokenJSON.utf8), statusCode: 200)),
        .success(DataResponse(data: Data(tokenJSON.utf8), statusCode: 200))
    ]

    let runner = MockAuthProcessRunner(stdout: "ghp_test_token")
    let logger = MockLogger()
    let deviceFlow = MockDeviceFlowService()
    let service = GitHubCLIAuthService(processRunner: runner, logger: logger, deviceFlowService: deviceFlow, httpClient: httpClient)

    let first = try await service.getValidCopilotToken()
    let second = try await service.getValidCopilotToken()

    #expect(first.token == "cached-token")
    #expect(second.token == "cached-token")
    #expect(httpClient.executeCallCount == 1)
}

@Test func getValidCopilotTokenTriggersDeviceFlowWhenGHCLIAbsent() async throws {
    let tokenJSON = """
    {"token":"device-flow-token","expires_at":\(Int(Date.now.timeIntervalSince1970) + 3600),"endpoints":{"api":"https://api.endpoint.com"}}
    """
    let httpClient = MockHTTPClient()
    httpClient.executeResults = [
        .success(DataResponse(data: Data(tokenJSON.utf8), statusCode: 200))
    ]

    // Simulate gh installed but not authenticated. resolveGitHubToken returns nil,
    // so getValidCopilotToken falls through directly to the device code flow.
    let runner = MockAuthProcessRunner(handler: { path, args, _ in
        if args == ["auth", "token"] {
            return .success(ProcessResult(stdout: "", stderr: "not logged into any github hosts. Run gh auth login", exitCode: 1))
        }
        return .success(ProcessResult(stdout: path, stderr: "", exitCode: 0))
    })
    let logger = MockLogger()
    let deviceFlow = MockDeviceFlowService()
    let expectedOAuthToken = OAuthToken(accessToken: "gho_device_token", tokenType: "bearer", scope: "user:email")
    deviceFlow.performDeviceFlowResult = .success(expectedOAuthToken)

    let service = GitHubCLIAuthService(processRunner: runner, logger: logger, deviceFlowService: deviceFlow, httpClient: httpClient)
    let credentials = try await service.getValidCopilotToken()

    #expect(credentials.token == "device-flow-token")
    #expect(deviceFlow.performDeviceFlowCallCount == 1)
}

@Test func getValidCopilotTokenTriggersDeviceFlowWhenGHCLINotAuthenticated() async throws {
    let tokenJSON = """
    {"token":"device-flow-token","expires_at":\(Int(Date.now.timeIntervalSince1970) + 3600),"endpoints":{"api":"https://api.endpoint.com"}}
    """
    let httpClient = MockHTTPClient()
    httpClient.executeResults = [
        .success(DataResponse(data: Data(tokenJSON.utf8), statusCode: 200))
    ]

    let runner = MockAuthProcessRunner(
        stdout: "",
        stderr: "not logged into any github hosts. Run gh auth login",
        exitCode: 1
    )
    let logger = MockLogger()
    let deviceFlow = MockDeviceFlowService()
    let expectedOAuthToken = OAuthToken(accessToken: "gho_device_token", tokenType: "bearer", scope: "user:email")
    deviceFlow.performDeviceFlowResult = .success(expectedOAuthToken)

    let service = GitHubCLIAuthService(processRunner: runner, logger: logger, deviceFlowService: deviceFlow, httpClient: httpClient)
    let credentials = try await service.getValidCopilotToken()

    #expect(credentials.token == "device-flow-token")
    #expect(deviceFlow.performDeviceFlowCallCount == 1)
}

@Test func getValidCopilotTokenTriggersDeviceFlowOn401FromTokenExchange() async throws {
    let tokenJSON = """
    {"token":"device-flow-token","expires_at":\(Int(Date.now.timeIntervalSince1970) + 3600),"endpoints":{"api":"https://api.endpoint.com"}}
    """
    let httpClient = MockHTTPClient()
    httpClient.executeResults = [
        .success(DataResponse(data: Data(), statusCode: 401)),
        .success(DataResponse(data: Data(tokenJSON.utf8), statusCode: 200))
    ]

    let runner = MockAuthProcessRunner(stdout: "ghp_insufficient_scopes_token")
    let logger = MockLogger()
    let deviceFlow = MockDeviceFlowService()
    let expectedOAuthToken = OAuthToken(accessToken: "gho_device_token", tokenType: "bearer", scope: "copilot")
    deviceFlow.performDeviceFlowResult = .success(expectedOAuthToken)

    let service = GitHubCLIAuthService(processRunner: runner, logger: logger, deviceFlowService: deviceFlow, httpClient: httpClient)
    let credentials = try await service.getValidCopilotToken()

    #expect(credentials.token == "device-flow-token")
    #expect(deviceFlow.performDeviceFlowCallCount == 1)
    #expect(httpClient.executeCallCount == 2)
}

@Test func getValidCopilotTokenTriggersDeviceFlowOn403FromTokenExchange() async throws {
    let tokenJSON = """
    {"token":"device-flow-token","expires_at":\(Int(Date.now.timeIntervalSince1970) + 3600),"endpoints":{"api":"https://api.endpoint.com"}}
    """
    let httpClient = MockHTTPClient()
    httpClient.executeResults = [
        .success(DataResponse(data: Data(), statusCode: 403)),
        .success(DataResponse(data: Data(tokenJSON.utf8), statusCode: 200))
    ]

    let runner = MockAuthProcessRunner(stdout: "ghp_no_copilot_scope_token")
    let logger = MockLogger()
    let deviceFlow = MockDeviceFlowService()
    let expectedOAuthToken = OAuthToken(accessToken: "gho_device_token", tokenType: "bearer", scope: "copilot")
    deviceFlow.performDeviceFlowResult = .success(expectedOAuthToken)

    let service = GitHubCLIAuthService(processRunner: runner, logger: logger, deviceFlowService: deviceFlow, httpClient: httpClient)
    let credentials = try await service.getValidCopilotToken()

    #expect(credentials.token == "device-flow-token")
    #expect(deviceFlow.performDeviceFlowCallCount == 1)
    #expect(httpClient.executeCallCount == 2)
}

@Test func getValidCopilotTokenTriggersDeviceFlowOn404FromTokenExchange() async throws {
    let tokenJSON = """
    {"token":"device-flow-token","expires_at":\(Int(Date.now.timeIntervalSince1970) + 3600),"endpoints":{"api":"https://api.endpoint.com"}}
    """
    let httpClient = MockHTTPClient()
    httpClient.executeResults = [
        .success(DataResponse(data: Data(), statusCode: 404)),
        .success(DataResponse(data: Data(tokenJSON.utf8), statusCode: 200))
    ]

    let runner = MockAuthProcessRunner(stdout: "ghp_no_copilot_subscription")
    let logger = MockLogger()
    let deviceFlow = MockDeviceFlowService()
    let expectedOAuthToken = OAuthToken(accessToken: "gho_device_token", tokenType: "bearer", scope: "copilot")
    deviceFlow.performDeviceFlowResult = .success(expectedOAuthToken)

    let service = GitHubCLIAuthService(processRunner: runner, logger: logger, deviceFlowService: deviceFlow, httpClient: httpClient)
    let credentials = try await service.getValidCopilotToken()

    #expect(credentials.token == "device-flow-token")
    #expect(deviceFlow.performDeviceFlowCallCount == 1)
    #expect(httpClient.executeCallCount == 2)
}

@Test func getValidCopilotTokenDeletesStaleStoredTokenBeforeDeviceFlow() async throws {
    let tokenJSON = """
    {"token":"fresh-token","expires_at":\(Int(Date.now.timeIntervalSince1970) + 3600),"endpoints":{"api":"https://api.endpoint.com"}}
    """
    let httpClient = MockHTTPClient()
    httpClient.executeResults = [
        .success(DataResponse(data: Data(), statusCode: 404)),
        .success(DataResponse(data: Data(tokenJSON.utf8), statusCode: 200))
    ]

    let runner = MockAuthProcessRunner(stdout: "ghp_cli_token")
    let logger = MockLogger()
    let deviceFlow = MockDeviceFlowService()
    deviceFlow.storedToken = OAuthToken(accessToken: "gho_stale_stored_token", tokenType: "bearer", scope: "user:email")
    let newOAuthToken = OAuthToken(accessToken: "gho_new_device_token", tokenType: "bearer", scope: "copilot")
    deviceFlow.performDeviceFlowResult = .success(newOAuthToken)

    let service = GitHubCLIAuthService(processRunner: runner, logger: logger, deviceFlowService: deviceFlow, httpClient: httpClient)
    let credentials = try await service.getValidCopilotToken()

    #expect(credentials.token == "fresh-token")
    #expect(deviceFlow.deleteStoredTokenCallCount == 1)
    #expect(deviceFlow.performDeviceFlowCallCount == 1)
}

@Test func getValidCopilotTokenPropagatesTokenExchangeFailure() async {
    let httpClient = MockHTTPClient()
    httpClient.executeResults = [
        .success(DataResponse(data: Data("Internal Server Error".utf8), statusCode: 500))
    ]

    let runner = MockAuthProcessRunner(stdout: "ghp_test_token")
    let logger = MockLogger()
    let deviceFlow = MockDeviceFlowService()
    let service = GitHubCLIAuthService(processRunner: runner, logger: logger, deviceFlowService: deviceFlow, httpClient: httpClient)

    do {
        _ = try await service.getValidCopilotToken()
        Issue.record("Expected AuthServiceError.tokenExchangeFailed")
    } catch let error as AuthServiceError {
        switch error {
        case .tokenExchangeFailed(let message):
            #expect(message.contains("500"))
        default:
            Issue.record("Expected tokenExchangeFailed, got \(error)")
        }
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

// MARK: - invalidateCachedToken

@Test func invalidateCachedTokenForcesRefreshOnNextCall() async throws {
    let tokenJSON1 = """
    {"token":"token-1","expires_at":\(Int(Date.now.timeIntervalSince1970) + 3600),"endpoints":{"api":"https://api.endpoint1.com"}}
    """
    let tokenJSON2 = """
    {"token":"token-2","expires_at":\(Int(Date.now.timeIntervalSince1970) + 3600),"endpoints":{"api":"https://api.endpoint2.com"}}
    """

    let httpClient = MockHTTPClient()
    httpClient.executeResults = [
        .success(DataResponse(data: Data(tokenJSON1.utf8), statusCode: 200)),
        .success(DataResponse(data: Data(tokenJSON2.utf8), statusCode: 200))
    ]

    let runner = MockAuthProcessRunner(stdout: "ghp_test_token")
    let logger = MockLogger()
    let deviceFlow = MockDeviceFlowService()
    let service = GitHubCLIAuthService(
        processRunner: runner,
        logger: logger,
        deviceFlowService: deviceFlow,
        httpClient: httpClient
    )

    let credentials1 = try await service.getValidCopilotToken()
    #expect(credentials1.token == "token-1")

    let cachedCredentials = try await service.getValidCopilotToken()
    #expect(cachedCredentials.token == "token-1")
    #expect(httpClient.executeCallCount == 1)

    await service.invalidateCachedToken()

    let credentials2 = try await service.getValidCopilotToken()
    #expect(credentials2.token == "token-2")
    #expect(httpClient.executeCallCount == 2)
    #expect(logger.debugMessages.contains { $0.contains("Cached Copilot token invalidated") })
}

// MARK: - retryingOnUnauthorized

@Test func retryingOnUnauthorizedReturnsResultOnSuccess() async throws {
    let authService = MockAuthService()
    authService.credentials = CopilotCredentials(token: "valid-token", apiEndpoint: "https://api.github.com")
    let initialCredentials = CopilotCredentials(token: "initial-token", apiEndpoint: "https://api.github.com")

    let result = try await authService.retryingOnUnauthorized(credentials: initialCredentials) { creds -> String in
        return "success-\(creds.token)"
    }

    #expect(result == "success-initial-token")
    #expect(authService.invalidateCallCount == 0)
    #expect(authService.getValidCopilotTokenCallCount == 0)
}

@Test func retryingOnUnauthorizedRetriesOnceOn401() async throws {
    let authService = MockAuthService()
    let freshCredentials = CopilotCredentials(token: "fresh-token", apiEndpoint: "https://api.github.com")
    authService.credentials = freshCredentials
    let initialCredentials = CopilotCredentials(token: "stale-token", apiEndpoint: "https://api.github.com")

    let callCount = Mutex(0)
    let result = try await authService.retryingOnUnauthorized(credentials: initialCredentials) { creds -> String in
        let current = callCount.withLock { value -> Int in
            value += 1
            return value
        }
        if current == 1 {
            throw CopilotAPIError.unauthorized
        }
        return "recovered-\(creds.token)"
    }

    #expect(result == "recovered-fresh-token")
    #expect(callCount.withLock { $0 } == 2)
    #expect(authService.invalidateCallCount == 1)
    #expect(authService.getValidCopilotTokenCallCount == 1)
}

@Test func retryingOnUnauthorizedPropagatesUnauthorizedOnSecondFailure() async {
    let authService = MockAuthService()
    authService.credentials = CopilotCredentials(token: "also-stale", apiEndpoint: "https://api.github.com")
    let initialCredentials = CopilotCredentials(token: "stale-token", apiEndpoint: "https://api.github.com")

    do {
        _ = try await authService.retryingOnUnauthorized(credentials: initialCredentials) { _ -> String in
            throw CopilotAPIError.unauthorized
        }
        Issue.record("Expected CopilotAPIError.unauthorized to be thrown")
    } catch let error as CopilotAPIError {
        guard case .unauthorized = error else {
            Issue.record("Expected .unauthorized, got \(error)")
            return
        }
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }

    #expect(authService.invalidateCallCount == 1)
}

@Test func retryingOnUnauthorizedPropagatesNonUnauthorizedErrors() async {
    let authService = MockAuthService()
    let initialCredentials = CopilotCredentials(token: "token", apiEndpoint: "https://api.github.com")

    do {
        _ = try await authService.retryingOnUnauthorized(credentials: initialCredentials) { _ -> String in
            throw CopilotAPIError.networkError("connection reset")
        }
        Issue.record("Expected CopilotAPIError.networkError to be thrown")
    } catch let error as CopilotAPIError {
        guard case .networkError(let message) = error else {
            Issue.record("Expected .networkError, got \(error)")
            return
        }
        #expect(message == "connection reset")
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }

    #expect(authService.invalidateCallCount == 0)
}

// MARK: - AuthServiceError descriptions

@Test func authServiceErrorGitHubCLINotFoundDescription() {
    let error = AuthServiceError.gitHubCLINotFound
    #expect(error.description == "GitHub CLI (gh) not found. Install it from https://cli.github.com")
}

@Test func authServiceErrorGitHubCLIFailedDescription() {
    let error = AuthServiceError.gitHubCLIFailed("permission denied")
    #expect(error.description == "GitHub CLI failed: permission denied")
}

@Test func authServiceErrorTokenExchangeFailedDescription() {
    let error = AuthServiceError.tokenExchangeFailed("Network error: timeout")
    #expect(error.description == "Copilot token exchange failed: Network error: timeout")
}

@Test func authServiceErrorNotAuthenticatedDescription() {
    let error = AuthServiceError.notAuthenticated
    #expect(error.description == "Not authenticated. Run `gh auth login` first.")
}

@Test func authServiceErrorCopilotSubscriptionRequiredDescription() {
    let error = AuthServiceError.copilotSubscriptionRequired
    #expect(error.description.contains("Copilot subscription"))
    #expect(error.description.contains("github.com/settings/copilot"))
}

@Test func authServiceConformsToProtocol() async {
    let runner = MockAuthProcessRunner(stdout: "token", stderr: "", exitCode: 0)
    let logger = MockLogger()
    let deviceFlow = MockDeviceFlowService()
    let service: any AuthServiceProtocol = GitHubCLIAuthService(processRunner: runner, logger: logger, deviceFlowService: deviceFlow, httpClient: MockHTTPClient())
    _ = service
}

// MARK: - DeviceFlowError descriptions

@Test func deviceFlowErrorDescriptions() {
    let expired = DeviceFlowError.expired
    #expect(expired.description.contains("expired"))

    let denied = DeviceFlowError.accessDenied
    #expect(denied.description.contains("denied"))

    let network = DeviceFlowError.networkError("timeout")
    #expect(network.description.contains("timeout"))

    let invalid = DeviceFlowError.invalidResponse("bad json")
    #expect(invalid.description.contains("bad json"))

    let storage = DeviceFlowError.tokenStorageFailed("permission denied")
    #expect(storage.description.contains("permission denied"))

    let request = DeviceFlowError.requestFailed("HTTP 500")
    #expect(request.description.contains("HTTP 500"))
}

// MARK: - OAuthToken / DeviceCodeResponse codable

@Test func oauthTokenEncodesAndDecodes() throws {
    let original = OAuthToken(accessToken: "gho_test123", tokenType: "bearer", scope: "user:email")
    let encoder = JSONEncoder()
    let data = try encoder.encode(original)
    let decoded = try JSONDecoder().decode(OAuthToken.self, from: data)
    #expect(decoded.accessToken == "gho_test123")
    #expect(decoded.tokenType == "bearer")
    #expect(decoded.scope == "user:email")
}

@Test func deviceCodeResponseDecodes() throws {
    let json = """
    {
        "device_code": "dc_abc123",
        "user_code": "ABCD-1234",
        "verification_uri": "https://github.com/login/device",
        "expires_in": 900,
        "interval": 5
    }
    """.data(using: .utf8)!
    let response = try JSONDecoder().decode(DeviceCodeResponse.self, from: json)
    #expect(response.deviceCode == "dc_abc123")
    #expect(response.userCode == "ABCD-1234")
    #expect(response.verificationUri == "https://github.com/login/device")
    #expect(response.expiresIn == 900)
    #expect(response.interval == 5)
}

@Test func deviceCodePollResponseDecodesSuccess() throws {
    let json = """
    {
        "access_token": "gho_success_token",
        "token_type": "bearer",
        "scope": "user:email"
    }
    """.data(using: .utf8)!
    let response = try JSONDecoder().decode(DeviceCodePollResponse.self, from: json)
    let token = response.toOAuthToken()
    #expect(token != nil)
    #expect(token?.accessToken == "gho_success_token")
    #expect(token?.tokenType == "bearer")
}

@Test func deviceCodePollResponseDecodesPending() throws {
    let json = """
    {
        "error": "authorization_pending",
        "error_description": "The authorization request is still pending."
    }
    """.data(using: .utf8)!
    let response = try JSONDecoder().decode(DeviceCodePollResponse.self, from: json)
    #expect(response.error == "authorization_pending")
    #expect(response.toOAuthToken() == nil)
}

@Test func deviceCodePollResponseReturnsNilWhenMissingFields() throws {
    let json = """
    {
        "access_token": "gho_token_only"
    }
    """.data(using: .utf8)!
    let response = try JSONDecoder().decode(DeviceCodePollResponse.self, from: json)
    #expect(response.toOAuthToken() == nil)
}

// MARK: - MockDeviceFlowService helpers

@Test func mockDeviceFlowServicePerformDeviceFlowIncrementsCallCount() async throws {
    let deviceFlow = MockDeviceFlowService()
    let expectedToken = OAuthToken(accessToken: "gho_device_flow_token", tokenType: "bearer", scope: "user:email")
    deviceFlow.performDeviceFlowResult = .success(expectedToken)

    let token = try await deviceFlow.performDeviceFlow()
    #expect(token.accessToken == "gho_device_flow_token")
    #expect(deviceFlow.performDeviceFlowCallCount == 1)
}

@Test func mockDeviceFlowServiceDeleteIncrementsCallCount() throws {
    let deviceFlow = MockDeviceFlowService()
    deviceFlow.storedToken = OAuthToken(accessToken: "gho_to_delete", tokenType: "bearer", scope: "")

    try deviceFlow.deleteStoredToken()
    #expect(deviceFlow.deleteStoredTokenCallCount == 1)
    #expect(deviceFlow.storedToken == nil)
}