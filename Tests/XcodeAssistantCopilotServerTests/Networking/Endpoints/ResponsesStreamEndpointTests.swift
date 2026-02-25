import Foundation
import Testing
@testable import XcodeAssistantCopilotServer

@Test func responsesStreamEndpointHasPostMethod() throws {
    let endpoint = try ResponsesStreamEndpoint(
        request: ResponsesAPIRequest(
            model: "gpt-4o",
            input: [.message(ResponsesMessage(role: "user", content: "Hello"))]
        ),
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://api.example.com")
    )
    #expect(endpoint.method == .post)
}

@Test func responsesStreamEndpointHasCorrectPath() throws {
    let endpoint = try ResponsesStreamEndpoint(
        request: ResponsesAPIRequest(
            model: "gpt-4o",
            input: [.message(ResponsesMessage(role: "user", content: "Hello"))]
        ),
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://api.example.com")
    )
    #expect(endpoint.path == "/responses")
}

@Test func responsesStreamEndpointUsesCredentialsBaseURL() throws {
    let endpoint = try ResponsesStreamEndpoint(
        request: ResponsesAPIRequest(
            model: "gpt-4o",
            input: [.message(ResponsesMessage(role: "user", content: "Hello"))]
        ),
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://custom.endpoint.com")
    )
    #expect(endpoint.baseURL == "https://custom.endpoint.com")
}

@Test func responsesStreamEndpointHasStreamingHeaders() throws {
    let endpoint = try ResponsesStreamEndpoint(
        request: ResponsesAPIRequest(
            model: "gpt-4o",
            input: [.message(ResponsesMessage(role: "user", content: "Hello"))]
        ),
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://api.example.com")
    )
    #expect(endpoint.headers["Accept"] == "text/event-stream")
    #expect(endpoint.headers["Openai-Intent"] == "conversation-panel")
}

@Test func responsesStreamEndpointHasBearerAuthorization() throws {
    let endpoint = try ResponsesStreamEndpoint(
        request: ResponsesAPIRequest(
            model: "gpt-4o",
            input: [.message(ResponsesMessage(role: "user", content: "Hello"))]
        ),
        credentials: CopilotCredentials(token: "my-secret-token", apiEndpoint: "https://api.example.com")
    )
    #expect(endpoint.headers["Authorization"] == "Bearer my-secret-token")
}

@Test func responsesStreamEndpointHasStandardCopilotHeaders() throws {
    let endpoint = try ResponsesStreamEndpoint(
        request: ResponsesAPIRequest(
            model: "gpt-4o",
            input: [.message(ResponsesMessage(role: "user", content: "Hello"))]
        ),
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://api.example.com")
    )
    #expect(endpoint.headers["Content-Type"] == "application/json")
    #expect(endpoint.headers["Openai-Organization"] == "github-copilot")
    #expect(endpoint.headers["Editor-Version"] == "Xcode/26.0")
    #expect(endpoint.headers["Editor-Plugin-Version"] == "copilot-xcode/0.1.0")
    #expect(endpoint.headers["Copilot-Integration-Id"] == "vscode-chat")
    #expect(endpoint.headers["X-Request-Id"] != nil)
}

@Test func responsesStreamEndpointHas300SecondTimeout() throws {
    let endpoint = try ResponsesStreamEndpoint(
        request: ResponsesAPIRequest(
            model: "gpt-4o",
            input: [.message(ResponsesMessage(role: "user", content: "Hello"))]
        ),
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://api.example.com")
    )
    #expect(endpoint.timeoutInterval == 300)
}

@Test func responsesStreamEndpointEncodesBodyAsJSON() throws {
    let request = ResponsesAPIRequest(
        model: "o3-mini",
        input: [.message(ResponsesMessage(role: "user", content: "Explain Swift concurrency"))]
    )
    let endpoint = try ResponsesStreamEndpoint(
        request: request,
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://api.example.com")
    )
    let body = try #require(endpoint.body)
    let decoded = try JSONSerialization.jsonObject(with: body) as? [String: Any]
    #expect(decoded?["model"] as? String == "o3-mini")
    #expect(decoded?["stream"] as? Bool == true)
}

@Test func responsesStreamEndpointBodyContainsInput() throws {
    let request = ResponsesAPIRequest(
        model: "gpt-4o",
        input: [
            .message(ResponsesMessage(role: "user", content: "Hello")),
            .message(ResponsesMessage(role: "assistant", content: "Hi there"))
        ]
    )
    let endpoint = try ResponsesStreamEndpoint(
        request: request,
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://api.example.com")
    )
    let body = try #require(endpoint.body)
    let decoded = try JSONSerialization.jsonObject(with: body) as? [String: Any]
    let input = decoded?["input"] as? [[String: Any]]
    #expect(input?.count == 2)
}

@Test func responsesStreamEndpointBuildsValidURLRequest() throws {
    let endpoint = try ResponsesStreamEndpoint(
        request: ResponsesAPIRequest(
            model: "gpt-4o",
            input: [.message(ResponsesMessage(role: "user", content: "Hello"))]
        ),
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://api.example.com")
    )
    let request = try endpoint.buildURLRequest()
    #expect(request.url?.absoluteString == "https://api.example.com/responses")
    #expect(request.httpMethod == "POST")
    #expect(request.timeoutInterval == 300)
    #expect(request.httpBody != nil)
}

@Test func responsesStreamEndpointBodyContainsInstructions() throws {
    let request = ResponsesAPIRequest(
        model: "gpt-4o",
        input: [.message(ResponsesMessage(role: "user", content: "Hello"))],
        instructions: "You are a helpful assistant"
    )
    let endpoint = try ResponsesStreamEndpoint(
        request: request,
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://api.example.com")
    )
    let body = try #require(endpoint.body)
    let decoded = try JSONSerialization.jsonObject(with: body) as? [String: Any]
    #expect(decoded?["instructions"] as? String == "You are a helpful assistant")
}

@Test func responsesStreamEndpointBodyContainsReasoning() throws {
    let request = ResponsesAPIRequest(
        model: "o3-mini",
        input: [.message(ResponsesMessage(role: "user", content: "Hello"))],
        reasoning: ResponsesReasoning(effort: "medium")
    )
    let endpoint = try ResponsesStreamEndpoint(
        request: request,
        credentials: CopilotCredentials(token: "test-token", apiEndpoint: "https://api.example.com")
    )
    let body = try #require(endpoint.body)
    let decoded = try JSONSerialization.jsonObject(with: body) as? [String: Any]
    let reasoning = decoded?["reasoning"] as? [String: Any]
    #expect(reasoning?["effort"] as? String == "medium")
}