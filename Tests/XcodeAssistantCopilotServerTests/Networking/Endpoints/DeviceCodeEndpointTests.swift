import Foundation
import Testing
@testable import XcodeAssistantCopilotServer

@Test func deviceCodeEndpointMethodIsPost() {
    let endpoint = DeviceCodeEndpoint(clientID: "test-client-id", scope: "user:email")
    #expect(endpoint.method == .post)
}

@Test func deviceCodeEndpointBaseURL() {
    let endpoint = DeviceCodeEndpoint(clientID: "test-client-id", scope: "user:email")
    #expect(endpoint.baseURL == "https://github.com")
}

@Test func deviceCodeEndpointPath() {
    let endpoint = DeviceCodeEndpoint(clientID: "test-client-id", scope: "user:email")
    #expect(endpoint.path == "/login/device/code")
}

@Test func deviceCodeEndpointHeadersIncludeContentType() {
    let endpoint = DeviceCodeEndpoint(clientID: "test-client-id", scope: "user:email")
    #expect(endpoint.headers["Content-Type"] == "application/json")
}

@Test func deviceCodeEndpointHeadersIncludeAccept() {
    let endpoint = DeviceCodeEndpoint(clientID: "test-client-id", scope: "user:email")
    #expect(endpoint.headers["Accept"] == "application/json")
}

@Test func deviceCodeEndpointBodyContainsClientID() throws {
    let endpoint = DeviceCodeEndpoint(clientID: "Iv1.b507a08c87ecfe98", scope: "user:email")
    let body = try #require(endpoint.body)
    let dict = try JSONSerialization.jsonObject(with: body) as? [String: String]
    #expect(dict?["client_id"] == "Iv1.b507a08c87ecfe98")
}

@Test func deviceCodeEndpointBodyContainsScope() throws {
    let endpoint = DeviceCodeEndpoint(clientID: "test-client-id", scope: "user:email")
    let body = try #require(endpoint.body)
    let dict = try JSONSerialization.jsonObject(with: body) as? [String: String]
    #expect(dict?["scope"] == "user:email")
}

@Test func deviceCodeEndpointBodyHasExactlyTwoKeys() throws {
    let endpoint = DeviceCodeEndpoint(clientID: "test-client-id", scope: "user:email")
    let body = try #require(endpoint.body)
    let dict = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
    #expect(dict.count == 2)
}

@Test func deviceCodeEndpointUsesDefaultTimeout() {
    let endpoint = DeviceCodeEndpoint(clientID: "test-client-id", scope: "user:email")
    #expect(endpoint.timeoutInterval == 60)
}

@Test func deviceCodeEndpointBuildURLRequestProducesCorrectURL() throws {
    let endpoint = DeviceCodeEndpoint(clientID: "test-client-id", scope: "user:email")
    let request = try endpoint.buildURLRequest()
    #expect(request.url?.absoluteString == "https://github.com/login/device/code")
}

@Test func deviceCodeEndpointBuildURLRequestSetsPostMethod() throws {
    let endpoint = DeviceCodeEndpoint(clientID: "test-client-id", scope: "user:email")
    let request = try endpoint.buildURLRequest()
    #expect(request.httpMethod == "POST")
}

@Test func deviceCodeEndpointBuildURLRequestIncludesBody() throws {
    let endpoint = DeviceCodeEndpoint(clientID: "test-client-id", scope: "user:email")
    let request = try endpoint.buildURLRequest()
    #expect(request.httpBody != nil)
}

@Test func deviceCodeEndpointBuildURLRequestSetsHeaders() throws {
    let endpoint = DeviceCodeEndpoint(clientID: "test-client-id", scope: "user:email")
    let request = try endpoint.buildURLRequest()
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
}

@Test func deviceCodeEndpointDoesNotIncludeAuthorizationHeader() {
    let endpoint = DeviceCodeEndpoint(clientID: "test-client-id", scope: "user:email")
    #expect(endpoint.headers["Authorization"] == nil)
}