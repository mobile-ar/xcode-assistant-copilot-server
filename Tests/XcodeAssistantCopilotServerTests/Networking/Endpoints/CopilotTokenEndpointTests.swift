import Foundation
import Testing
@testable import XcodeAssistantCopilotServer

private let testEditorVersion = "Xcode/26.0"
private let testRequestHeaders = CopilotRequestHeaders(editorVersion: testEditorVersion)

@Test func copilotTokenEndpointUsesGETMethod() {
    let endpoint = CopilotTokenEndpoint(githubToken: "ghp_test123", requestHeaders: testRequestHeaders)
    #expect(endpoint.method == .get)
}

@Test func copilotTokenEndpointHasCorrectBaseURL() {
    let endpoint = CopilotTokenEndpoint(githubToken: "ghp_test123", requestHeaders: testRequestHeaders)
    #expect(endpoint.baseURL == "https://api.github.com")
}

@Test func copilotTokenEndpointHasCorrectPath() {
    let endpoint = CopilotTokenEndpoint(githubToken: "ghp_test123", requestHeaders: testRequestHeaders)
    #expect(endpoint.path == "/copilot_internal/v2/token")
}

@Test func copilotTokenEndpointSetsTokenAuthorization() {
    let endpoint = CopilotTokenEndpoint(githubToken: "ghp_my_token_abc", requestHeaders: testRequestHeaders)
    #expect(endpoint.headers["Authorization"] == "token ghp_my_token_abc")
}

@Test func copilotTokenEndpointSetsAcceptHeader() {
    let endpoint = CopilotTokenEndpoint(githubToken: "ghp_test123", requestHeaders: testRequestHeaders)
    #expect(endpoint.headers["Accept"] == "application/json")
}

@Test func copilotTokenEndpointSetsEditorVersionHeader() {
    let endpoint = CopilotTokenEndpoint(githubToken: "ghp_test123", requestHeaders: CopilotRequestHeaders(editorVersion: "Xcode/25.0"))
    #expect(endpoint.headers["Editor-Version"] == "Xcode/25.0")
}

@Test func copilotTokenEndpointUsesInjectedEditorVersion() {
    let endpoint = CopilotTokenEndpoint(githubToken: "ghp_test123", requestHeaders: CopilotRequestHeaders(editorVersion: "Xcode/16.2.1"))
    #expect(endpoint.headers["Editor-Version"] == "Xcode/16.2.1")
}

@Test func copilotTokenEndpointSetsEditorPluginVersionHeader() {
    let endpoint = CopilotTokenEndpoint(githubToken: "ghp_test123", requestHeaders: testRequestHeaders)
    #expect(endpoint.headers["Editor-Plugin-Version"] == CopilotConstants.plugginVersion)
}

@Test func copilotTokenEndpointHasNoBody() {
    let endpoint = CopilotTokenEndpoint(githubToken: "ghp_test123", requestHeaders: testRequestHeaders)
    #expect(endpoint.body == nil)
}

@Test func copilotTokenEndpointUsesDefaultTimeout() {
    let endpoint = CopilotTokenEndpoint(githubToken: "ghp_test123", requestHeaders: testRequestHeaders)
    #expect(endpoint.timeoutInterval == 60)
}

@Test func copilotTokenEndpointHasExactlyFourHeaders() {
    let endpoint = CopilotTokenEndpoint(githubToken: "ghp_test123", requestHeaders: testRequestHeaders)
    #expect(endpoint.headers.count == 4)
}

@Test func copilotTokenEndpointBuildsValidURLRequest() throws {
    let endpoint = CopilotTokenEndpoint(githubToken: "ghp_test123", requestHeaders: testRequestHeaders)
    let request = try endpoint.buildURLRequest()
    #expect(request.url?.absoluteString == "https://api.github.com/copilot_internal/v2/token")
    #expect(request.httpMethod == "GET")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "token ghp_test123")
    #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    #expect(request.httpBody == nil)
}

@Test func copilotTokenEndpointDoesNotSetContentTypeHeader() {
    let endpoint = CopilotTokenEndpoint(githubToken: "ghp_test123", requestHeaders: testRequestHeaders)
    #expect(endpoint.headers["Content-Type"] == nil)
}