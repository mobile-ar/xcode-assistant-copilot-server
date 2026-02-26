@testable import XcodeAssistantCopilotServer
import Foundation
import HTTPTypes
import Testing

private func makeModelsHandler(
    authService: AuthServiceProtocol = MockAuthService(),
    copilotAPI: CopilotAPIServiceProtocol = MockCopilotAPIService(),
    logger: LoggerProtocol = MockLogger()
) -> ModelsHandler {
    ModelsHandler(
        authService: authService,
        copilotAPI: copilotAPI,
        logger: logger
    )
}

private func makeCredentials() -> CopilotCredentials {
    CopilotCredentials(token: "mock-token", apiEndpoint: "https://api.github.com")
}

@Test func modelsRetriesOnUnauthorized() async {
    let authService = MockAuthService()
    let freshCredentials = CopilotCredentials(token: "fresh-token", apiEndpoint: "https://api.github.com")
    authService.credentialsSequence = [
        CopilotCredentials(token: "stale-token", apiEndpoint: "https://api.github.com"),
        freshCredentials
    ]

    let copilotAPI = MockCopilotAPIService()
    copilotAPI.listModelsResults = [
        .failure(CopilotAPIError.unauthorized),
        .success([CopilotModel(id: "gpt-4")])
    ]

    let logger = MockLogger()
    let handler = makeModelsHandler(
        authService: authService,
        copilotAPI: copilotAPI,
        logger: logger
    )

    let response = await handler.buildModelsResponse(credentials: makeCredentials())

    #expect(response.status == HTTPResponse.Status.ok)
    #expect(copilotAPI.listModelsCallCount == 2)
    #expect(authService.invalidateCallCount == 1)
}

@Test func modelsFailsWhenRetryAlsoReturnsUnauthorized() async {
    let authService = MockAuthService()
    let copilotAPI = MockCopilotAPIService()
    copilotAPI.listModelsResults = [
        .failure(CopilotAPIError.unauthorized),
        .failure(CopilotAPIError.unauthorized)
    ]

    let logger = MockLogger()
    let handler = makeModelsHandler(
        authService: authService,
        copilotAPI: copilotAPI,
        logger: logger
    )

    let response = await handler.buildModelsResponse(credentials: makeCredentials())

    #expect(response.status == HTTPResponse.Status.internalServerError)
    #expect(copilotAPI.listModelsCallCount == 2)
    #expect(authService.invalidateCallCount == 1)
}

@Test func modelsSucceedsWithoutRetryWhenTokenIsValid() async {
    let copilotAPI = MockCopilotAPIService()
    copilotAPI.models = [CopilotModel(id: "gpt-4")]

    let authService = MockAuthService()
    let handler = makeModelsHandler(
        authService: authService,
        copilotAPI: copilotAPI
    )

    let response = await handler.buildModelsResponse(credentials: makeCredentials())

    #expect(response.status == HTTPResponse.Status.ok)
    #expect(copilotAPI.listModelsCallCount == 1)
    #expect(authService.invalidateCallCount == 0)
}