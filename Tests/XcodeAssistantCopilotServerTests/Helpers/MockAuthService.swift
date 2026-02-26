@testable import XcodeAssistantCopilotServer

final class MockAuthService: AuthServiceProtocol, @unchecked Sendable {
    var token: String = "mock-github-token"
    var credentials: CopilotCredentials = CopilotCredentials(
        token: "mock-copilot-token",
        apiEndpoint: "https://api.github.com"
    )
    var credentialsSequence: [CopilotCredentials] = []
    var shouldThrow: Error?
    private(set) var invalidateCallCount = 0
    private(set) var getValidCopilotTokenCallCount = 0

    func getGitHubToken() async throws -> String {
        if let error = shouldThrow { throw error }
        return token
    }

    func getValidCopilotToken() async throws -> CopilotCredentials {
        if let error = shouldThrow { throw error }
        let index = getValidCopilotTokenCallCount
        getValidCopilotTokenCallCount += 1
        if index < credentialsSequence.count {
            return credentialsSequence[index]
        }
        return credentials
    }

    func invalidateCachedToken() async {
        invalidateCallCount += 1
    }
}