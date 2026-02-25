import Foundation
import Testing
@testable import XcodeAssistantCopilotServer

@Test func chatCompletionsStreamEndpointHasPostMethod() throws {
    let endpoint = try ChatCompletionsStreamEndpoint(
        request: CopilotChatRequest(
            model: "gpt-4o",
            messages: [ChatCompletionMessage(role: .user, content: .text("Hi"))]
        ),
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://api.example.com")
    )
    #expect(endpoint.method == .post)
}

@Test func chatCompletionsStreamEndpointHasCorrectPath() throws {
    let endpoint = try ChatCompletionsStreamEndpoint(
        request: CopilotChatRequest(
            model: "gpt-4o",
            messages: [ChatCompletionMessage(role: .user, content: .text("Hi"))]
        ),
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://api.example.com")
    )
    #expect(endpoint.path == "/chat/completions")
}

@Test func chatCompletionsStreamEndpointUsesCredentialsBaseURL() throws {
    let endpoint = try ChatCompletionsStreamEndpoint(
        request: CopilotChatRequest(
            model: "gpt-4o",
            messages: [ChatCompletionMessage(role: .user, content: .text("Hi"))]
        ),
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://copilot.example.com")
    )
    #expect(endpoint.baseURL == "https://copilot.example.com")
}

@Test func chatCompletionsStreamEndpointHas300SecondTimeout() throws {
    let endpoint = try ChatCompletionsStreamEndpoint(
        request: CopilotChatRequest(
            model: "gpt-4o",
            messages: [ChatCompletionMessage(role: .user, content: .text("Hi"))]
        ),
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://api.example.com")
    )
    #expect(endpoint.timeoutInterval == 300)
}

@Test func chatCompletionsStreamEndpointIncludesBearerAuthHeader() throws {
    let endpoint = try ChatCompletionsStreamEndpoint(
        request: CopilotChatRequest(
            model: "gpt-4o",
            messages: [ChatCompletionMessage(role: .user, content: .text("Hi"))]
        ),
        credentials: CopilotCredentials(token: "my-secret-token", apiEndpoint: "https://api.example.com")
    )
    #expect(endpoint.headers["Authorization"] == "Bearer my-secret-token")
}

@Test func chatCompletionsStreamEndpointIncludesContentTypeHeader() throws {
    let endpoint = try ChatCompletionsStreamEndpoint(
        request: CopilotChatRequest(
            model: "gpt-4o",
            messages: [ChatCompletionMessage(role: .user, content: .text("Hi"))]
        ),
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://api.example.com")
    )
    #expect(endpoint.headers["Content-Type"] == "application/json")
}

@Test func chatCompletionsStreamEndpointIncludesSSEAcceptHeader() throws {
    let endpoint = try ChatCompletionsStreamEndpoint(
        request: CopilotChatRequest(
            model: "gpt-4o",
            messages: [ChatCompletionMessage(role: .user, content: .text("Hi"))]
        ),
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://api.example.com")
    )
    #expect(endpoint.headers["Accept"] == "text/event-stream")
}

@Test func chatCompletionsStreamEndpointIncludesOpenaiIntentHeader() throws {
    let endpoint = try ChatCompletionsStreamEndpoint(
        request: CopilotChatRequest(
            model: "gpt-4o",
            messages: [ChatCompletionMessage(role: .user, content: .text("Hi"))]
        ),
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://api.example.com")
    )
    #expect(endpoint.headers["Openai-Intent"] == "conversation-panel")
}

@Test func chatCompletionsStreamEndpointIncludesEditorVersionHeader() throws {
    let endpoint = try ChatCompletionsStreamEndpoint(
        request: CopilotChatRequest(
            model: "gpt-4o",
            messages: [ChatCompletionMessage(role: .user, content: .text("Hi"))]
        ),
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://api.example.com")
    )
    #expect(endpoint.headers["Editor-Version"] == "Xcode/26.0")
}

@Test func chatCompletionsStreamEndpointIncludesEditorPluginVersionHeader() throws {
    let endpoint = try ChatCompletionsStreamEndpoint(
        request: CopilotChatRequest(
            model: "gpt-4o",
            messages: [ChatCompletionMessage(role: .user, content: .text("Hi"))]
        ),
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://api.example.com")
    )
    #expect(endpoint.headers["Editor-Plugin-Version"] == "copilot-xcode/0.1.0")
}

@Test func chatCompletionsStreamEndpointIncludesCopilotIntegrationIdHeader() throws {
    let endpoint = try ChatCompletionsStreamEndpoint(
        request: CopilotChatRequest(
            model: "gpt-4o",
            messages: [ChatCompletionMessage(role: .user, content: .text("Hi"))]
        ),
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://api.example.com")
    )
    #expect(endpoint.headers["Copilot-Integration-Id"] == "vscode-chat")
}

@Test func chatCompletionsStreamEndpointIncludesOpenaiOrganizationHeader() throws {
    let endpoint = try ChatCompletionsStreamEndpoint(
        request: CopilotChatRequest(
            model: "gpt-4o",
            messages: [ChatCompletionMessage(role: .user, content: .text("Hi"))]
        ),
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://api.example.com")
    )
    #expect(endpoint.headers["Openai-Organization"] == "github-copilot")
}

@Test func chatCompletionsStreamEndpointIncludesRequestIdHeader() throws {
    let endpoint = try ChatCompletionsStreamEndpoint(
        request: CopilotChatRequest(
            model: "gpt-4o",
            messages: [ChatCompletionMessage(role: .user, content: .text("Hi"))]
        ),
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://api.example.com")
    )
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
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://api.example.com")
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
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://api.example.com")
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
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://api.individual.githubcopilot.com")
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
    let endpoint1 = try ChatCompletionsStreamEndpoint(request: chatRequest, credentials: credentials)
    let endpoint2 = try ChatCompletionsStreamEndpoint(request: chatRequest, credentials: credentials)
    #expect(endpoint1.headers["X-Request-Id"] != endpoint2.headers["X-Request-Id"])
}