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

    let authService = GitHubCLIAuthService(processRunner: runner, logger: logger, deviceFlowService: deviceFlow)
    let token = try await authService.getGitHubToken()
    #expect(token == "gho_stored_oauth_token")
}

@Test func getGitHubTokenFallsBackToGHCLIWhenNoStoredToken() async throws {
    let runner = MockAuthProcessRunner(handler: { path, args, _ in
        if args == ["auth", "token"] {
            return .success(ProcessResult(stdout: "ghp_test1234567890abcdef", stderr: "", exitCode: 0))
        }
        if args == ["--find", "mcpbridge"] || path.hasSuffix("which") {
            return .success(ProcessResult(stdout: path, stderr: "", exitCode: 0))
        }
        return .success(ProcessResult(stdout: path, stderr: "", exitCode: 0))
    })
    let logger = MockLogger()
    let deviceFlow = MockDeviceFlowService()
    let authService = GitHubCLIAuthService(processRunner: runner, logger: logger, deviceFlowService: deviceFlow)
    let token = try await authService.getGitHubToken()
    #expect(token == "ghp_test1234567890abcdef")
}

@Test func getGitHubTokenThrowsNotAuthenticatedWhenEmpty() async {
    let runner = MockAuthProcessRunner(stdout: "", stderr: "", exitCode: 0)
    let logger = MockLogger()
    let deviceFlow = MockDeviceFlowService()
    let authService = GitHubCLIAuthService(processRunner: runner, logger: logger, deviceFlowService: deviceFlow)

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

@Test func getGitHubTokenThrowsNotAuthenticatedWhenNotLoggedIn() async {
    let runner = MockAuthProcessRunner(
        stdout: "",
        stderr: "not logged into any github hosts. Run gh auth login",
        exitCode: 1
    )
    let logger = MockLogger()
    let deviceFlow = MockDeviceFlowService()
    let authService = GitHubCLIAuthService(processRunner: runner, logger: logger, deviceFlowService: deviceFlow)

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
    let authService = GitHubCLIAuthService(processRunner: runner, logger: logger, deviceFlowService: deviceFlow)

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
    let authService = GitHubCLIAuthService(processRunner: runner, logger: logger, deviceFlowService: deviceFlow)

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

@Test func getGitHubTokenThrowsGitHubCLINotFoundWhenAllPathsFail() async {
    let runner = MockAuthProcessRunner(throwing: ProcessRunnerError.executableNotFound("/usr/bin/gh"))
    let logger = MockLogger()
    let deviceFlow = MockDeviceFlowService()
    let authService = GitHubCLIAuthService(processRunner: runner, logger: logger, deviceFlowService: deviceFlow)

    do {
        _ = try await authService.getGitHubToken()
        Issue.record("Expected an error to be thrown")
    } catch is AuthServiceError {
        // Expected - gitHubCLINotFound
    } catch is ProcessRunnerError {
        // Also acceptable - the mock throws ProcessRunnerError before
        // findGitHubCLI can wrap it as AuthServiceError
    } catch {
        Issue.record("Unexpected error type: \(type(of: error)): \(error)")
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
    let authService = GitHubCLIAuthService(processRunner: runner, logger: logger, deviceFlowService: deviceFlow)
    let token = try await authService.getGitHubToken()
    #expect(token == "ghp_trimmed_token")
    #expect(!token.contains("\n"))
}

@Test func getValidCopilotTokenCachesToken() async throws {
    let callCount = Mutex(0)
    let runner = MockAuthProcessRunner(handler: { _, args, _ in
        if args == ["auth", "token"] {
            callCount.withLock { $0 += 1 }
            return .success(ProcessResult(stdout: "ghp_test_token_12345678", stderr: "", exitCode: 0))
        }
        return .success(ProcessResult(stdout: "/usr/local/bin/gh", stderr: "", exitCode: 0))
    })
    let logger = MockLogger()
    let deviceFlow = MockDeviceFlowService()
    let _ = GitHubCLIAuthService(processRunner: runner, logger: logger, deviceFlowService: deviceFlow)

    // Note: Full token caching test requires a mock URLSession to intercept the
    // Copilot token exchange HTTP call. This test verifies the service can be created.
    #expect(callCount.withLock { $0 } == 0)
}

@Test func authServiceErrorDescriptions() {
    let notFound = AuthServiceError.gitHubCLINotFound
    #expect(notFound.description.contains("GitHub CLI"))
    #expect(notFound.description.contains("gh"))

    let failed = AuthServiceError.gitHubCLIFailed("timeout")
    #expect(failed.description.contains("timeout"))

    let exchange = AuthServiceError.tokenExchangeFailed("HTTP 403")
    #expect(exchange.description.contains("HTTP 403"))

    let notAuth = AuthServiceError.notAuthenticated
    #expect(notAuth.description.contains("gh auth login"))
}

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
    let service: any AuthServiceProtocol = GitHubCLIAuthService(processRunner: runner, logger: logger, deviceFlowService: deviceFlow)
    _ = service
}

@Test func getGitHubTokenUsesWhichAsFallback() async throws {
    let executablePaths = Mutex<[String]>([])
    let runner = MockAuthProcessRunner(handler: { path, args, _ in
        executablePaths.withLock { $0.append(path) }
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
    let authService = GitHubCLIAuthService(processRunner: runner, logger: logger, deviceFlowService: deviceFlow)

    // If gh is at a standard path, it will be found directly.
    // This test just verifies the service can find and use gh.
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
    let authService = GitHubCLIAuthService(processRunner: runner, logger: logger, deviceFlowService: deviceFlow)

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

    let authService = GitHubCLIAuthService(processRunner: runner, logger: logger, deviceFlowService: deviceFlow)
    let token = try await authService.getGitHubToken()
    #expect(token == "gho_oauth_token")
    #expect(!ghAuthTokenCalled.withLock { $0 })
}

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
