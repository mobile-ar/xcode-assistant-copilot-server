import Foundation
import Testing
@testable import XcodeAssistantCopilotServer

@Test func standardHeadersContainBearerAuthorization() {
    let headers = CopilotRequestHeaders.standard(token: "my-token-123")
    #expect(headers["Authorization"] == "Bearer my-token-123")
}

@Test func standardHeadersContainContentType() {
    let headers = CopilotRequestHeaders.standard(token: "test")
    #expect(headers["Content-Type"] == "application/json")
}

@Test func standardHeadersContainRequestId() {
    let headers = CopilotRequestHeaders.standard(token: "test")
    #expect(headers["X-Request-Id"] != nil)
    #expect(!headers["X-Request-Id"]!.isEmpty)
}

@Test func standardHeadersContainOrganization() {
    let headers = CopilotRequestHeaders.standard(token: "test")
    #expect(headers["Openai-Organization"] == "github-copilot")
}

@Test func standardHeadersContainEditorVersion() {
    let headers = CopilotRequestHeaders.standard(token: "test")
    #expect(headers["Editor-Version"] == "Xcode/26.0")
}

@Test func standardHeadersContainEditorPluginVersion() {
    let headers = CopilotRequestHeaders.standard(token: "test")
    #expect(headers["Editor-Plugin-Version"] == "copilot-xcode/0.1.0")
}

@Test func standardHeadersContainCopilotIntegrationId() {
    let headers = CopilotRequestHeaders.standard(token: "test")
    #expect(headers["Copilot-Integration-Id"] == "vscode-chat")
}

@Test func standardHeadersHaveExactlySevenEntries() {
    let headers = CopilotRequestHeaders.standard(token: "test")
    #expect(headers.count == 7)
}

@Test func standardHeadersDoNotContainAccept() {
    let headers = CopilotRequestHeaders.standard(token: "test")
    #expect(headers["Accept"] == nil)
}

@Test func standardHeadersDoNotContainOpenaiIntent() {
    let headers = CopilotRequestHeaders.standard(token: "test")
    #expect(headers["Openai-Intent"] == nil)
}

@Test func standardHeadersRequestIdIsUniquePerCall() {
    let headers1 = CopilotRequestHeaders.standard(token: "test")
    let headers2 = CopilotRequestHeaders.standard(token: "test")
    #expect(headers1["X-Request-Id"] != headers2["X-Request-Id"])
}

@Test func streamingHeadersContainAllStandardHeaders() {
    let streaming = CopilotRequestHeaders.streaming(token: "my-token")
    let standard = CopilotRequestHeaders.standard(token: "my-token")

    #expect(streaming["Authorization"] == standard["Authorization"])
    #expect(streaming["Content-Type"] == standard["Content-Type"])
    #expect(streaming["Openai-Organization"] == standard["Openai-Organization"])
    #expect(streaming["Editor-Version"] == standard["Editor-Version"])
    #expect(streaming["Editor-Plugin-Version"] == standard["Editor-Plugin-Version"])
    #expect(streaming["Copilot-Integration-Id"] == standard["Copilot-Integration-Id"])
}

@Test func streamingHeadersContainAcceptEventStream() {
    let headers = CopilotRequestHeaders.streaming(token: "test")
    #expect(headers["Accept"] == "text/event-stream")
}

@Test func streamingHeadersContainOpenaiIntent() {
    let headers = CopilotRequestHeaders.streaming(token: "test")
    #expect(headers["Openai-Intent"] == "conversation-panel")
}

@Test func streamingHeadersHaveExactlyNineEntries() {
    let headers = CopilotRequestHeaders.streaming(token: "test")
    #expect(headers.count == 9)
}

@Test func streamingHeadersRequestIdIsUniquePerCall() {
    let headers1 = CopilotRequestHeaders.streaming(token: "test")
    let headers2 = CopilotRequestHeaders.streaming(token: "test")
    #expect(headers1["X-Request-Id"] != headers2["X-Request-Id"])
}

@Test func standardHeadersTokenIsEmbeddedCorrectly() {
    let headers = CopilotRequestHeaders.standard(token: "ghu_abc123XYZ")
    #expect(headers["Authorization"] == "Bearer ghu_abc123XYZ")
}

@Test func streamingHeadersTokenIsEmbeddedCorrectly() {
    let headers = CopilotRequestHeaders.streaming(token: "ghu_abc123XYZ")
    #expect(headers["Authorization"] == "Bearer ghu_abc123XYZ")
}