import Foundation
import Testing
@testable import XcodeAssistantCopilotServer

@Test func accessTokenPollEndpointMethodIsPost() {
    let endpoint = AccessTokenPollEndpoint(clientID: "test-client", deviceCode: "device123")
    #expect(endpoint.method == .post)
}

@Test func accessTokenPollEndpointBaseURL() {
    let endpoint = AccessTokenPollEndpoint(clientID: "test-client", deviceCode: "device123")
    #expect(endpoint.baseURL == "https://github.com")
}

@Test func accessTokenPollEndpointPath() {
    let endpoint = AccessTokenPollEndpoint(clientID: "test-client", deviceCode: "device123")
    #expect(endpoint.path == "/login/oauth/access_token")
}

@Test func accessTokenPollEndpointHeadersIncludeContentType() {
    let endpoint = AccessTokenPollEndpoint(clientID: "test-client", deviceCode: "device123")
    #expect(endpoint.headers["Content-Type"] == "application/json")
}

@Test func accessTokenPollEndpointHeadersIncludeAccept() {
    let endpoint = AccessTokenPollEndpoint(clientID: "test-client", deviceCode: "device123")
    #expect(endpoint.headers["Accept"] == "application/json")
}

@Test func accessTokenPollEndpointBodyContainsClientID() throws {
    let endpoint = AccessTokenPollEndpoint(clientID: "my-client-id", deviceCode: "device123")
    let body = try #require(endpoint.body)
    let dict = try JSONSerialization.jsonObject(with: body) as? [String: String]
    #expect(dict?["client_id"] == "my-client-id")
}

@Test func accessTokenPollEndpointBodyContainsDeviceCode() throws {
    let endpoint = AccessTokenPollEndpoint(clientID: "test-client", deviceCode: "abc-device-code")
    let body = try #require(endpoint.body)
    let dict = try JSONSerialization.jsonObject(with: body) as? [String: String]
    #expect(dict?["device_code"] == "abc-device-code")
}

@Test func accessTokenPollEndpointBodyContainsGrantType() throws {
    let endpoint = AccessTokenPollEndpoint(clientID: "test-client", deviceCode: "device123")
    let body = try #require(endpoint.body)
    let dict = try JSONSerialization.jsonObject(with: body) as? [String: String]
    #expect(dict?["grant_type"] == "urn:ietf:params:oauth:grant-type:device_code")
}

@Test func accessTokenPollEndpointBodyHasExactlyThreeKeys() throws {
    let endpoint = AccessTokenPollEndpoint(clientID: "test-client", deviceCode: "device123")
    let body = try #require(endpoint.body)
    let dict = try JSONSerialization.jsonObject(with: body) as? [String: String]
    #expect(dict?.count == 3)
}

@Test func accessTokenPollEndpointUsesDefaultTimeout() {
    let endpoint = AccessTokenPollEndpoint(clientID: "test-client", deviceCode: "device123")
    #expect(endpoint.timeoutInterval == 60)
}

@Test func accessTokenPollEndpointBuildsValidURLRequest() throws {
    let endpoint = AccessTokenPollEndpoint(clientID: "test-client", deviceCode: "device123")
    let request = try endpoint.buildURLRequest()
    #expect(request.url?.absoluteString == "https://github.com/login/oauth/access_token")
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    #expect(request.httpBody != nil)
}