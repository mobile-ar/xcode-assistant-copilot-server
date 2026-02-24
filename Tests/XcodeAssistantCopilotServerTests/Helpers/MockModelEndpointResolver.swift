@testable import XcodeAssistantCopilotServer

final class MockModelEndpointResolver: ModelEndpointResolverProtocol, @unchecked Sendable {
    var endpoint: ModelEndpoint = .chatCompletions
    private(set) var resolvedModels: [String] = []

    func endpoint(for modelId: String, credentials: CopilotCredentials) async -> ModelEndpoint {
        resolvedModels.append(modelId)
        return endpoint
    }
}