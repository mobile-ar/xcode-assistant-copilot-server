import Foundation
import Testing
@testable import XcodeAssistantCopilotServer

private let testEditorVersion = "Xcode/26.0"
private let testRequestHeaders = CopilotRequestHeaders(editorVersion: testEditorVersion)

@Test func standardHeadersContainBearerAuthorization() {
    let headers = testRequestHeaders.standard(token: "my-token-123")
    #expect(headers["Authorization"] == "Bearer my-token-123")
}

@Test func standardHeadersContainContentType() {
    let headers = testRequestHeaders.standard(token: "test")
    #expect(headers["Content-Type"] == "application/json")
}

@Test func standardHeadersContainRequestId() {
    let headers = testRequestHeaders.standard(token: "test")
    #expect(headers["X-Request-Id"] != nil)
    #expect(!headers["X-Request-Id"]!.isEmpty)
}

@Test func standardHeadersContainOrganization() {
    let headers = testRequestHeaders.standard(token: "test")
    #expect(headers["Openai-Organization"] == "github-copilot")
}

@Test func standardHeadersContainEditorVersion() {
    let headers = testRequestHeaders.standard(token: "test")
    #expect(headers["Editor-Version"] == testEditorVersion)
}

@Test func standardHeadersReflectCustomEditorVersion() {
    let customVersion = "Xcode/16.2"
    let headers = CopilotRequestHeaders(editorVersion: customVersion).standard(token: "test")
    #expect(headers["Editor-Version"] == customVersion)
}

@Test func standardHeadersContainEditorPluginVersion() {
    let headers = testRequestHeaders.standard(token: "test")
    #expect(headers["Editor-Plugin-Version"] == CopilotConstants.plugginVersion)
}

@Test func standardHeadersContainCopilotIntegrationId() {
    let headers = testRequestHeaders.standard(token: "test")
    #expect(headers["Copilot-Integration-Id"] == "vscode-chat")
}

@Test func standardHeadersHaveExactlySevenEntries() {
    let headers = testRequestHeaders.standard(token: "test")
    #expect(headers.count == 7)
}

@Test func standardHeadersDoNotContainAccept() {
    let headers = testRequestHeaders.standard(token: "test")
    #expect(headers["Accept"] == nil)
}

@Test func standardHeadersDoNotContainOpenaiIntent() {
    let headers = testRequestHeaders.standard(token: "test")
    #expect(headers["Openai-Intent"] == nil)
}

@Test func standardHeadersRequestIdIsUniquePerCall() {
    let headers1 = testRequestHeaders.standard(token: "test")
    let headers2 = testRequestHeaders.standard(token: "test")
    #expect(headers1["X-Request-Id"] != headers2["X-Request-Id"])
}

@Test func streamingHeadersContainAllStandardHeaders() {
    let streaming = testRequestHeaders.streaming(token: "my-token")
    let standard = testRequestHeaders.standard(token: "my-token")

    #expect(streaming["Authorization"] == standard["Authorization"])
    #expect(streaming["Content-Type"] == standard["Content-Type"])
    #expect(streaming["Openai-Organization"] == standard["Openai-Organization"])
    #expect(streaming["Editor-Version"] == standard["Editor-Version"])
    #expect(streaming["Editor-Plugin-Version"] == standard["Editor-Plugin-Version"])
    #expect(streaming["Copilot-Integration-Id"] == standard["Copilot-Integration-Id"])
}

@Test func streamingHeadersContainAcceptEventStream() {
    let headers = testRequestHeaders.streaming(token: "test")
    #expect(headers["Accept"] == "text/event-stream")
}

@Test func streamingHeadersContainOpenaiIntent() {
    let headers = testRequestHeaders.streaming(token: "test")
    #expect(headers["Openai-Intent"] == "conversation-panel")
}

@Test func streamingHeadersHaveExactlyNineEntries() {
    let headers = testRequestHeaders.streaming(token: "test")
    #expect(headers.count == 9)
}

@Test func streamingHeadersRequestIdIsUniquePerCall() {
    let headers1 = testRequestHeaders.streaming(token: "test")
    let headers2 = testRequestHeaders.streaming(token: "test")
    #expect(headers1["X-Request-Id"] != headers2["X-Request-Id"])
}

@Test func streamingHeadersReflectCustomEditorVersion() {
    let customVersion = "Xcode/15.4"
    let headers = CopilotRequestHeaders(editorVersion: customVersion).streaming(token: "test")
    #expect(headers["Editor-Version"] == customVersion)
}

@Test func standardHeadersTokenIsEmbeddedCorrectly() {
    let headers = testRequestHeaders.standard(token: "ghu_abc123XYZ")
    #expect(headers["Authorization"] == "Bearer ghu_abc123XYZ")
}

@Test func streamingHeadersTokenIsEmbeddedCorrectly() {
    let headers = testRequestHeaders.streaming(token: "ghu_abc123XYZ")
    #expect(headers["Authorization"] == "Bearer ghu_abc123XYZ")
}

@Test func tokenRequestHeadersContainTokenAuthorization() {
    let headers = testRequestHeaders.tokenRequest(githubToken: "ghp_my_token")
    #expect(headers["Authorization"] == "token ghp_my_token")
}

@Test func tokenRequestHeadersContainAccept() {
    let headers = testRequestHeaders.tokenRequest(githubToken: "ghp_test")
    #expect(headers["Accept"] == "application/json")
}

@Test func tokenRequestHeadersContainEditorVersion() {
    let headers = testRequestHeaders.tokenRequest(githubToken: "ghp_test")
    #expect(headers["Editor-Version"] == testEditorVersion)
}

@Test func tokenRequestHeadersReflectCustomEditorVersion() {
    let customVersion = "Xcode/16.2.1"
    let headers = CopilotRequestHeaders(editorVersion: customVersion).tokenRequest(githubToken: "ghp_test")
    #expect(headers["Editor-Version"] == customVersion)
}

@Test func tokenRequestHeadersContainEditorPluginVersion() {
    let headers = testRequestHeaders.tokenRequest(githubToken: "ghp_test")
    #expect(headers["Editor-Plugin-Version"] == CopilotConstants.plugginVersion)
}

@Test func tokenRequestHeadersHaveExactlyFourEntries() {
    let headers = testRequestHeaders.tokenRequest(githubToken: "ghp_test")
    #expect(headers.count == 4)
}

@Test func tokenRequestHeadersDoNotContainContentType() {
    let headers = testRequestHeaders.tokenRequest(githubToken: "ghp_test")
    #expect(headers["Content-Type"] == nil)
}

@Test func tokenRequestHeadersDoNotContainCopilotIntegrationId() {
    let headers = testRequestHeaders.tokenRequest(githubToken: "ghp_test")
    #expect(headers["Copilot-Integration-Id"] == nil)
}

@Test func tokenRequestGithubTokenIsEmbeddedCorrectly() {
    let headers = testRequestHeaders.tokenRequest(githubToken: "ghp_abc456XYZ")
    #expect(headers["Authorization"] == "token ghp_abc456XYZ")
}