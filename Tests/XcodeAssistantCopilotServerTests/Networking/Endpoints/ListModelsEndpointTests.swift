import Foundation
import Testing
@testable import XcodeAssistantCopilotServer

@Test func listModelsEndpointMethodIsGet() {
    let endpoint = ListModelsEndpoint(
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://api.example.com")
    )
    #expect(endpoint.method == .get)
}

@Test func listModelsEndpointPathIsModels() {
    let endpoint = ListModelsEndpoint(
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://api.example.com")
    )
    #expect(endpoint.path == "/models")
}

@Test func listModelsEndpointBaseURLMatchesCredentials() {
    let endpoint = ListModelsEndpoint(
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://custom.endpoint.com")
    )
    #expect(endpoint.baseURL == "https://custom.endpoint.com")
}

@Test func listModelsEndpointHasNilBody() {
    let endpoint = ListModelsEndpoint(
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://api.example.com")
    )
    #expect(endpoint.body == nil)
}

@Test func listModelsEndpointUsesDefaultTimeout() {
    let endpoint = ListModelsEndpoint(
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://api.example.com")
    )
    #expect(endpoint.timeoutInterval == 60)
}

@Test func listModelsEndpointHeadersContainBearerAuth() {
    let endpoint = ListModelsEndpoint(
        credentials: CopilotCredentials(token: "my-secret-token", apiEndpoint: "https://api.example.com")
    )
    #expect(endpoint.headers["Authorization"] == "Bearer my-secret-token")
}

@Test func listModelsEndpointHeadersContainContentType() {
    let endpoint = ListModelsEndpoint(
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://api.example.com")
    )
    #expect(endpoint.headers["Content-Type"] == "application/json")
}

@Test func listModelsEndpointHeadersContainEditorVersion() {
    let endpoint = ListModelsEndpoint(
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://api.example.com")
    )
    #expect(endpoint.headers["Editor-Version"] == "Xcode/26.0")
}

@Test func listModelsEndpointHeadersContainEditorPluginVersion() {
    let endpoint = ListModelsEndpoint(
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://api.example.com")
    )
    #expect(endpoint.headers["Editor-Plugin-Version"] == "copilot-xcode/0.1.0")
}

@Test func listModelsEndpointHeadersContainCopilotIntegrationId() {
    let endpoint = ListModelsEndpoint(
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://api.example.com")
    )
    #expect(endpoint.headers["Copilot-Integration-Id"] == "vscode-chat")
}

@Test func listModelsEndpointHeadersContainOrganization() {
    let endpoint = ListModelsEndpoint(
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://api.example.com")
    )
    #expect(endpoint.headers["Openai-Organization"] == "github-copilot")
}

@Test func listModelsEndpointHeadersContainRequestId() {
    let endpoint = ListModelsEndpoint(
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://api.example.com")
    )
    #expect(endpoint.headers["X-Request-Id"] != nil)
    #expect(!endpoint.headers["X-Request-Id"]!.isEmpty)
}

@Test func listModelsEndpointBuildURLRequestProducesCorrectURL() throws {
    let endpoint = ListModelsEndpoint(
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://api.individual.githubcopilot.com")
    )
    let request = try endpoint.buildURLRequest()
    #expect(request.url?.absoluteString == "https://api.individual.githubcopilot.com/models")
}

@Test func listModelsEndpointDoesNotContainStreamingHeaders() {
    let endpoint = ListModelsEndpoint(
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://api.example.com")
    )
    #expect(endpoint.headers["Accept"] == nil)
    #expect(endpoint.headers["Openai-Intent"] == nil)
}