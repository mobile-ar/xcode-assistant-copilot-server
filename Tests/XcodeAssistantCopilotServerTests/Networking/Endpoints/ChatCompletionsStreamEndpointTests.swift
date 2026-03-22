import Foundation
import Testing
@testable import XcodeAssistantCopilotServer

private let testRequestHeaders = CopilotRequestHeaders(editorVersion: "Xcode/26.0")

private func makeEndpoint(
    model: String = "gpt-4o",
    message: String = "Hi",
    token: String = "test-token",
    apiEndpoint: String = "https://api.example.com",
    requestHeaders: CopilotRequestHeadersProtocol = testRequestHeaders,
    timeoutInterval: TimeInterval = 300
) throws -> ChatCompletionsStreamEndpoint {
    try ChatCompletionsStreamEndpoint(
        request: CopilotChatRequest(
            model: model,
            messages: [ChatCompletionMessage(role: .user, content: .text(message))]
        ),
        credentials: CopilotCredentials(token: token, apiEndpoint: apiEndpoint),
        requestHeaders: requestHeaders,
        timeoutInterval: timeoutInterval
    )
}

@Test func chatCompletionsStreamEndpointHasPostMethod() throws {
    let endpoint = try makeEndpoint()
    #expect(endpoint.method == .post)
}

@Test func chatCompletionsStreamEndpointHasCorrectPath() throws {
    let endpoint = try makeEndpoint()
    #expect(endpoint.path == "/chat/completions")
}

@Test func chatCompletionsStreamEndpointUsesCredentialsBaseURL() throws {
    let endpoint = try makeEndpoint(apiEndpoint: "https://copilot.example.com")
    #expect(endpoint.baseURL == "https://copilot.example.com")
}

@Test func chatCompletionsStreamEndpointUsesDefaultTimeout() throws {
    let endpoint = try makeEndpoint(timeoutInterval: 300)
    #expect(endpoint.timeoutInterval == 300)
}

@Test func chatCompletionsStreamEndpointUsesCustomTimeout() throws {
    let endpoint = try makeEndpoint(timeoutInterval: 120)
    #expect(endpoint.timeoutInterval == 120)
}

@Test func chatCompletionsStreamEndpointIncludesBearerAuthHeader() throws {
    let endpoint = try makeEndpoint(token: "my-secret-token")
    #expect(endpoint.headers["Authorization"] == "Bearer my-secret-token")
}

@Test func chatCompletionsStreamEndpointIncludesContentTypeHeader() throws {
    let endpoint = try makeEndpoint()
    #expect(endpoint.headers["Content-Type"] == "application/json")
}

@Test func chatCompletionsStreamEndpointIncludesSSEAcceptHeader() throws {
    let endpoint = try makeEndpoint()
    #expect(endpoint.headers["Accept"] == "text/event-stream")
}

@Test func chatCompletionsStreamEndpointIncludesOpenaiIntentHeader() throws {
    let endpoint = try makeEndpoint()
    #expect(endpoint.headers["Openai-Intent"] == "conversation-panel")
}

@Test func chatCompletionsStreamEndpointIncludesEditorVersionHeader() throws {
    let endpoint = try makeEndpoint()
    #expect(endpoint.headers["Editor-Version"] == "Xcode/26.0")
}

@Test func chatCompletionsStreamEndpointReflectsCustomEditorVersion() throws {
    let endpoint = try makeEndpoint(requestHeaders: CopilotRequestHeaders(editorVersion: "Xcode/16.2.1"))
    #expect(endpoint.headers["Editor-Version"] == "Xcode/16.2.1")
}

@Test func chatCompletionsStreamEndpointIncludesEditorPluginVersionHeader() throws {
    let endpoint = try makeEndpoint()
    #expect(endpoint.headers["Editor-Plugin-Version"] == CopilotConstants.plugginVersion)
}

@Test func chatCompletionsStreamEndpointIncludesCopilotIntegrationIdHeader() throws {
    let endpoint = try makeEndpoint()
    #expect(endpoint.headers["Copilot-Integration-Id"] == "vscode-chat")
}

@Test func chatCompletionsStreamEndpointIncludesOpenaiOrganizationHeader() throws {
    let endpoint = try makeEndpoint()
    #expect(endpoint.headers["Openai-Organization"] == "github-copilot")
}

@Test func chatCompletionsStreamEndpointIncludesRequestIdHeader() throws {
    let endpoint = try makeEndpoint()
    #expect(endpoint.headers["X-Request-Id"] != nil)
    #expect(!endpoint.headers["X-Request-Id"]!.isEmpty)
}

@Test func chatCompletionsStreamEndpointEncodesRequestBody() throws {
    let chatRequest = CopilotChatRequest(
        model: "gpt-4o",
        messages: [ChatCompletionMessage(role: .user, content: .text("Hello world"))]
    )
    let endpoint = try ChatCompletionsStreamEndpoint(
        request: chatRequest,
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://api.example.com"),
        requestHeaders: testRequestHeaders
    )
    #expect(endpoint.body != nil)
    let bodyString = String(data: endpoint.body!, encoding: .utf8)!
    #expect(bodyString.contains("gpt-4o"))
    #expect(bodyString.contains("Hello world"))
}

@Test func chatCompletionsStreamEndpointBodyIncludesStreamTrue() throws {
    let chatRequest = CopilotChatRequest(
        model: "gpt-4o",
        messages: [ChatCompletionMessage(role: .user, content: .text("Hi"))],
        stream: true
    )
    let endpoint = try ChatCompletionsStreamEndpoint(
        request: chatRequest,
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://api.example.com"),
        requestHeaders: testRequestHeaders
    )
    let bodyString = String(data: endpoint.body!, encoding: .utf8)!
    #expect(bodyString.contains("\"stream\":true"))
}

@Test func chatCompletionsStreamEndpointBuildURLRequestProducesFullURL() throws {
    let endpoint = try ChatCompletionsStreamEndpoint(
        request: CopilotChatRequest(
            model: "gpt-4o",
            messages: [ChatCompletionMessage(role: .user, content: .text("Hi"))]
        ),
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://api.individual.githubcopilot.com"),
        requestHeaders: testRequestHeaders
    )
    let urlRequest = try endpoint.buildURLRequest()
    #expect(urlRequest.url?.absoluteString == "https://api.individual.githubcopilot.com/chat/completions")
    #expect(urlRequest.httpMethod == "POST")
    #expect(urlRequest.timeoutInterval == 300)
    #expect(urlRequest.httpBody != nil)
}

@Test func chatCompletionsStreamEndpointRequestIdIsUniquePerInstance() throws {
    let credentials = CopilotCredentials(token: "test-token", apiEndpoint: "https://api.example.com")
    let chatRequest = CopilotChatRequest(
        model: "gpt-4o",
        messages: [ChatCompletionMessage(role: .user, content: .text("Hi"))]
    )
    let endpoint1 = try ChatCompletionsStreamEndpoint(request: chatRequest, credentials: credentials, requestHeaders: testRequestHeaders)
    let endpoint2 = try ChatCompletionsStreamEndpoint(request: chatRequest, credentials: credentials, requestHeaders: testRequestHeaders)
    #expect(endpoint1.headers["X-Request-Id"] != endpoint2.headers["X-Request-Id"])
}