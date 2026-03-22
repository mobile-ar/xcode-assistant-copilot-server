import Foundation
import Testing
@testable import XcodeAssistantCopilotServer

private let testRequestHeaders = CopilotRequestHeaders(editorVersion: "Xcode/26.0")

@Test func listModelsEndpointMethodIsGet() {
    let endpoint = ListModelsEndpoint(
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://api.example.com"),
        requestHeaders: testRequestHeaders
    )
    #expect(endpoint.method == .get)
}

@Test func listModelsEndpointPathIsModels() {
    let endpoint = ListModelsEndpoint(
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://api.example.com"),
        requestHeaders: testRequestHeaders
    )
    #expect(endpoint.path == "/models")
}

@Test func listModelsEndpointBaseURLMatchesCredentials() {
    let endpoint = ListModelsEndpoint(
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://custom.endpoint.com"),
        requestHeaders: testRequestHeaders
    )
    #expect(endpoint.baseURL == "https://custom.endpoint.com")
}

@Test func listModelsEndpointHasNilBody() {
    let endpoint = ListModelsEndpoint(
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://api.example.com"),
        requestHeaders: testRequestHeaders
    )
    #expect(endpoint.body == nil)
}

@Test func listModelsEndpointUsesDefaultTimeout() {
    let endpoint = ListModelsEndpoint(
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://api.example.com"),
        requestHeaders: testRequestHeaders
    )
    #expect(endpoint.timeoutInterval == 60)
}

@Test func listModelsEndpointHeadersContainBearerAuth() {
    let endpoint = ListModelsEndpoint(
        credentials: CopilotCredentials(token: "my-secret-token", apiEndpoint: "https://api.example.com"),
        requestHeaders: testRequestHeaders
    )
    #expect(endpoint.headers["Authorization"] == "Bearer my-secret-token")
}

@Test func listModelsEndpointHeadersContainContentType() {
    let endpoint = ListModelsEndpoint(
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://api.example.com"),
        requestHeaders: testRequestHeaders
    )
    #expect(endpoint.headers["Content-Type"] == "application/json")
}

@Test func listModelsEndpointHeadersContainEditorVersion() {
    let endpoint = ListModelsEndpoint(
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://api.example.com"),
        requestHeaders: testRequestHeaders
    )
    #expect(endpoint.headers["Editor-Version"] == "Xcode/26.0")
}

@Test func listModelsEndpointHeadersReflectCustomEditorVersion() {
    let customHeaders = CopilotRequestHeaders(editorVersion: "Xcode/16.2.1")
    let endpoint = ListModelsEndpoint(
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://api.example.com"),
        requestHeaders: customHeaders
    )
    #expect(endpoint.headers["Editor-Version"] == "Xcode/16.2.1")
}

@Test func listModelsEndpointHeadersContainEditorPluginVersion() {
    let endpoint = ListModelsEndpoint(
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://api.example.com"),
        requestHeaders: testRequestHeaders
    )
    #expect(endpoint.headers["Editor-Plugin-Version"] == CopilotConstants.plugginVersion)
}

@Test func listModelsEndpointHeadersContainCopilotIntegrationId() {
    let endpoint = ListModelsEndpoint(
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://api.example.com"),
        requestHeaders: testRequestHeaders
    )
    #expect(endpoint.headers["Copilot-Integration-Id"] == "vscode-chat")
}

@Test func listModelsEndpointHeadersContainOrganization() {
    let endpoint = ListModelsEndpoint(
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://api.example.com"),
        requestHeaders: testRequestHeaders
    )
    #expect(endpoint.headers["Openai-Organization"] == "github-copilot")
}

@Test func listModelsEndpointHeadersContainRequestId() {
    let endpoint = ListModelsEndpoint(
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://api.example.com"),
        requestHeaders: testRequestHeaders
    )
    #expect(endpoint.headers["X-Request-Id"] != nil)
    #expect(!endpoint.headers["X-Request-Id"]!.isEmpty)
}

@Test func listModelsEndpointBuildURLRequestProducesCorrectURL() throws {
    let endpoint = ListModelsEndpoint(
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://api.individual.githubcopilot.com"),
        requestHeaders: testRequestHeaders
    )
    let request = try endpoint.buildURLRequest()
    #expect(request.url?.absoluteString == "https://api.individual.githubcopilot.com/models")
}

@Test func listModelsEndpointDoesNotContainStreamingHeaders() {
    let endpoint = ListModelsEndpoint(
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://api.example.com"),
        requestHeaders: testRequestHeaders
    )
    #expect(endpoint.headers["Accept"] == nil)
    #expect(endpoint.headers["Openai-Intent"] == nil)
}