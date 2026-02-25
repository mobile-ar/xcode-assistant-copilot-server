import Foundation
import Testing
@testable import XcodeAssistantCopilotServer

@Test func copilotTokenEndpointUsesGETMethod() {
    let endpoint = CopilotTokenEndpoint(githubToken: "ghp_test123")
    #expect(endpoint.method == .get)
}

@Test func copilotTokenEndpointHasCorrectBaseURL() {
    let endpoint = CopilotTokenEndpoint(githubToken: "ghp_test123")
    #expect(endpoint.baseURL == "https://api.github.com")
}

@Test func copilotTokenEndpointHasCorrectPath() {
    let endpoint = CopilotTokenEndpoint(githubToken: "ghp_test123")
    #expect(endpoint.path == "/copilot_internal/v2/token")
}

@Test func copilotTokenEndpointSetsTokenAuthorization() {
    let endpoint = CopilotTokenEndpoint(githubToken: "ghp_my_token_abc")
    #expect(endpoint.headers["Authorization"] == "token ghp_my_token_abc")
}

@Test func copilotTokenEndpointSetsAcceptHeader() {
    let endpoint = CopilotTokenEndpoint(githubToken: "ghp_test123")
    #expect(endpoint.headers["Accept"] == "application/json")
}

@Test func copilotTokenEndpointSetsEditorVersionHeader() {
    let endpoint = CopilotTokenEndpoint(githubToken: "ghp_test123")
    #expect(endpoint.headers["Editor-Version"] == "Xcode/26.0")
}

@Test func copilotTokenEndpointSetsEditorPluginVersionHeader() {
    let endpoint = CopilotTokenEndpoint(githubToken: "ghp_test123")
    #expect(endpoint.headers["Editor-Plugin-Version"] == "copilot-xcode/0.1.0")
}

@Test func copilotTokenEndpointHasNoBody() {
    let endpoint = CopilotTokenEndpoint(githubToken: "ghp_test123")
    #expect(endpoint.body == nil)
}

@Test func copilotTokenEndpointUsesDefaultTimeout() {
    let endpoint = CopilotTokenEndpoint(githubToken: "ghp_test123")
    #expect(endpoint.timeoutInterval == 60)
}

@Test func copilotTokenEndpointHasExactlyFourHeaders() {
    let endpoint = CopilotTokenEndpoint(githubToken: "ghp_test123")
    #expect(endpoint.headers.count == 4)
}

@Test func copilotTokenEndpointBuildsValidURLRequest() throws {
    let endpoint = CopilotTokenEndpoint(githubToken: "ghp_test123")
    let request = try endpoint.buildURLRequest()
    #expect(request.url?.absoluteString == "https://api.github.com/copilot_internal/v2/token")
    #expect(request.httpMethod == "GET")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "token ghp_test123")
    #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    #expect(request.httpBody == nil)
}

@Test func copilotTokenEndpointDoesNotSetContentTypeHeader() {
    let endpoint = CopilotTokenEndpoint(githubToken: "ghp_test123")
    #expect(endpoint.headers["Content-Type"] == nil)
}