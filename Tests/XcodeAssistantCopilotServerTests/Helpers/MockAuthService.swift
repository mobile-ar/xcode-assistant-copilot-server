@testable import XcodeAssistantCopilotServer

final class MockAuthService: AuthServiceProtocol, @unchecked Sendable {
    var token: String = "mock-github-token"
    var credentials: CopilotCredentials = CopilotCredentials(
        token: "mock-copilot-token",
        apiEndpoint: "https://api.github.com"
    )
    var shouldThrow: Error?

    func getGitHubToken() async throws -> String {
        if let error = shouldThrow { throw error }
        return token
    }

    func getValidCopilotToken() async throws -> CopilotCredentials {
        if let error = shouldThrow { throw error }
        return credentials
    }
}