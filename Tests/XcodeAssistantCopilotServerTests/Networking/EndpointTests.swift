import Foundation
import Testing
@testable import XcodeAssistantCopilotServer

private struct TestEndpoint: Endpoint {
    var method: HTTPMethod = .get
    var baseURL: String = "https://api.example.com"
    var path: String = "/test"
    var headers: [String: String] = [:]
    var body: Data? = nil
    var timeoutInterval: TimeInterval = 60
}

@Test func buildURLRequestProducesCorrectURL() throws {
    let endpoint = TestEndpoint(baseURL: "https://api.example.com", path: "/v1/models")
    let request = try endpoint.buildURLRequest()
    #expect(request.url?.absoluteString == "https://api.example.com/v1/models")
}

@Test func buildURLRequestSetsHTTPMethodGET() throws {
    let endpoint = TestEndpoint(method: .get)
    let request = try endpoint.buildURLRequest()
    #expect(request.httpMethod == "GET")
}

@Test func buildURLRequestSetsHTTPMethodPOST() throws {
    let endpoint = TestEndpoint(method: .post)
    let request = try endpoint.buildURLRequest()
    #expect(request.httpMethod == "POST")
}

@Test func buildURLRequestSetsHTTPMethodPUT() throws {
    let endpoint = TestEndpoint(method: .put)
    let request = try endpoint.buildURLRequest()
    #expect(request.httpMethod == "PUT")
}

@Test func buildURLRequestSetsHTTPMethodPATCH() throws {
    let endpoint = TestEndpoint(method: .patch)
    let request = try endpoint.buildURLRequest()
    #expect(request.httpMethod == "PATCH")
}

@Test func buildURLRequestSetsHTTPMethodDELETE() throws {
    let endpoint = TestEndpoint(method: .delete)
    let request = try endpoint.buildURLRequest()
    #expect(request.httpMethod == "DELETE")
}

@Test func buildURLRequestSetsHeaders() throws {
    let endpoint = TestEndpoint(headers: [
        "Authorization": "Bearer token123",
        "Content-Type": "application/json",
        "X-Custom": "value"
    ])
    let request = try endpoint.buildURLRequest()
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token123")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    #expect(request.value(forHTTPHeaderField: "X-Custom") == "value")
}

@Test func buildURLRequestSetsBody() throws {
    let bodyData = "{\"key\":\"value\"}".data(using: .utf8)
    let endpoint = TestEndpoint(method: .post, body: bodyData)
    let request = try endpoint.buildURLRequest()
    #expect(request.httpBody == bodyData)
}

@Test func buildURLRequestSetsNilBodyByDefault() throws {
    let endpoint = TestEndpoint()
    let request = try endpoint.buildURLRequest()
    #expect(request.httpBody == nil)
}

@Test func buildURLRequestSetsTimeoutInterval() throws {
    let endpoint = TestEndpoint(timeoutInterval: 300)
    let request = try endpoint.buildURLRequest()
    #expect(request.timeoutInterval == 300)
}

@Test func buildURLRequestUsesDefaultTimeout() throws {
    let endpoint = TestEndpoint()
    let request = try endpoint.buildURLRequest()
    #expect(request.timeoutInterval == 60)
}

@Test func buildURLRequestThrowsForInvalidURL() {
    let endpoint = TestEndpoint(baseURL: "", path: "")
    do {
        _ = try endpoint.buildURLRequest()
        Issue.record("Expected HTTPClientError.invalidURL to be thrown")
    } catch let error as HTTPClientError {
        guard case .invalidURL = error else {
            Issue.record("Expected .invalidURL, got \(error)")
            return
        }
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

@Test func buildURLRequestCombinesBaseURLAndPath() throws {
    let endpoint = TestEndpoint(baseURL: "https://api.github.com", path: "/copilot_internal/v2/token")
    let request = try endpoint.buildURLRequest()
    #expect(request.url?.absoluteString == "https://api.github.com/copilot_internal/v2/token")
}

@Test func buildURLRequestWithEmptyPath() throws {
    let endpoint = TestEndpoint(baseURL: "https://api.example.com", path: "")
    let request = try endpoint.buildURLRequest()
    #expect(request.url?.absoluteString == "https://api.example.com")
}

@Test func buildURLRequestWithEmptyHeaders() throws {
    let endpoint = TestEndpoint(headers: [:])
    let request = try endpoint.buildURLRequest()
    #expect(request.allHTTPHeaderFields?.isEmpty != false)
}

@Test func defaultBodyIsNil() {
    struct MinimalEndpoint: Endpoint {
        let method: HTTPMethod = .get
        let baseURL: String = "https://example.com"
        let path: String = "/test"
        let headers: [String: String] = [:]
    }
    let endpoint = MinimalEndpoint()
    #expect(endpoint.body == nil)
}

@Test func defaultTimeoutIsSixtySeconds() {
    struct MinimalEndpoint: Endpoint {
        let method: HTTPMethod = .get
        let baseURL: String = "https://example.com"
        let path: String = "/test"
        let headers: [String: String] = [:]
    }
    let endpoint = MinimalEndpoint()
    #expect(endpoint.timeoutInterval == 60)
}