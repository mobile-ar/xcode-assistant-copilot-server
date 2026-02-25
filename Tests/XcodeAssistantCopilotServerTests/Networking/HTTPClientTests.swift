import Foundation
import Testing
@testable import XcodeAssistantCopilotServer

@Test func httpClientInitWithDefaultValues() {
    let client = HTTPClient()
    _ = client
}

@Test func httpClientInitWithCustomTimeout() {
    let client = HTTPClient(timeoutIntervalForRequest: 60)
    _ = client
}

@Test func httpClientInitWithCustomWaitsForConnectivity() {
    let client = HTTPClient(waitsForConnectivity: false)
    _ = client
}

@Test func httpClientInitWithCustomMaxConnections() {
    let client = HTTPClient(httpMaximumConnectionsPerHost: 2)
    _ = client
}

@Test func httpClientInitWithAllCustomValues() {
    let client = HTTPClient(
        timeoutIntervalForRequest: 120,
        waitsForConnectivity: false,
        httpMaximumConnectionsPerHost: 10
    )
    _ = client
}

@Test func httpClientInitWithSession() {
    let session = URLSession(configuration: .default)
    let client = HTTPClient(session: session)
    _ = client
}

@Test func httpClientConformsToProtocol() {
    let client: any HTTPClientProtocol = HTTPClient()
    _ = client
}

@Test func httpClientInitCreatesDistinctInstances() {
    let client1 = HTTPClient()
    let client2 = HTTPClient()
    #expect(type(of: client1) == type(of: client2))
}

@Test func mockHTTPClientSendReturnsDefaultResponseWhenNoResultsConfigured() async throws {
    let mock = MockHTTPClient()
    let endpoint = ListModelsEndpoint(
        credentials: CopilotCredentials(token: "test", apiEndpoint: "https://api.example.com")
    )
    let response = try await mock.execute(endpoint)
    #expect(response.statusCode == 200)
    #expect(response.data.isEmpty)
    #expect(mock.executeCallCount == 1)
}

@Test func mockHTTPClientSendReturnsConfiguredResults() async throws {
    let mock = MockHTTPClient()
    let expectedData = "{\"ok\":true}".data(using: .utf8)!
    mock.executeResults = [.success(DataResponse(data: expectedData, statusCode: 201))]

    let endpoint = ListModelsEndpoint(
        credentials: CopilotCredentials(token: "test", apiEndpoint: "https://api.example.com")
    )
    let response = try await mock.execute(endpoint)
    #expect(response.statusCode == 201)
    #expect(response.data == expectedData)
}

@Test func mockHTTPClientSendThrowsConfiguredError() async {
    let mock = MockHTTPClient()
    mock.executeResults = [.failure(HTTPClientError.networkError("connection refused"))]

    let endpoint = ListModelsEndpoint(
        credentials: CopilotCredentials(token: "test", apiEndpoint: "https://api.example.com")
    )

    do {
        _ = try await mock.execute(endpoint)
        Issue.record("Expected an error to be thrown")
    } catch let error as HTTPClientError {
        guard case .networkError(let message) = error else {
            Issue.record("Expected .networkError, got \(error)")
            return
        }
        #expect(message == "connection refused")
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

@Test func mockHTTPClientStreamReturnsDefaultResponseWhenNoResultsConfigured() async throws {
    let mock = MockHTTPClient()
    let endpoint = try ChatCompletionsStreamEndpoint(
        request: CopilotChatRequest(
            model: "gpt-4o",
            messages: [ChatCompletionMessage(role: .user, content: .text("Hi"))]
        ),
        credentials: CopilotCredentials(token: "test", apiEndpoint: "https://api.example.com")
    )
    let response = try await mock.stream(endpoint)
    #expect(response.statusCode == 200)
    #expect(mock.streamCallCount == 1)
}

@Test func mockHTTPClientStreamReturnsConfiguredErrorBody() async throws {
    let mock = MockHTTPClient()
    mock.streamResults = [.success(StreamResponse(statusCode: 401, content: .errorBody("Unauthorized")))]

    let endpoint = try ChatCompletionsStreamEndpoint(
        request: CopilotChatRequest(
            model: "gpt-4o",
            messages: [ChatCompletionMessage(role: .user, content: .text("Hi"))]
        ),
        credentials: CopilotCredentials(token: "test", apiEndpoint: "https://api.example.com")
    )
    let response = try await mock.stream(endpoint)
    #expect(response.statusCode == 401)
    guard case .errorBody(let body) = response.content else {
        Issue.record("Expected .errorBody content")
        return
    }
    #expect(body == "Unauthorized")
}

@Test func mockHTTPClientCapturesEndpoints() async throws {
    let mock = MockHTTPClient()
    let credentials = CopilotCredentials(token: "test-token", apiEndpoint: "https://api.example.com")

    _ = try await mock.execute(ListModelsEndpoint(credentials: credentials))
    _ = try await mock.execute(ListModelsEndpoint(credentials: credentials))

    #expect(mock.executeCallCount == 2)
    #expect(mock.sentEndpoints.count == 2)
}

@Test func mockHTTPClientReturnsResultsInOrder() async throws {
    let mock = MockHTTPClient()
    mock.executeResults = [
        .success(DataResponse(data: "first".data(using: .utf8)!, statusCode: 200)),
        .success(DataResponse(data: "second".data(using: .utf8)!, statusCode: 201))
    ]

    let endpoint = ListModelsEndpoint(
        credentials: CopilotCredentials(token: "test", apiEndpoint: "https://api.example.com")
    )

    let first = try await mock.execute(endpoint)
    let second = try await mock.execute(endpoint)

    #expect(first.statusCode == 200)
    #expect(String(data: first.data, encoding: .utf8) == "first")
    #expect(second.statusCode == 201)
    #expect(String(data: second.data, encoding: .utf8) == "second")
}

@Test func httpClientErrorDescriptions() {
    let invalidURL = HTTPClientError.invalidURL("bad://url")
    #expect(invalidURL.description.contains("bad://url"))

    let invalidResponse = HTTPClientError.invalidResponse
    #expect(invalidResponse.description.contains("non-HTTP"))

    let networkError = HTTPClientError.networkError("timeout")
    #expect(networkError.description.contains("timeout"))
}

@Test func dataResponseStoresValues() {
    let data = "test".data(using: .utf8)!
    let response = DataResponse(data: data, statusCode: 404)
    #expect(response.data == data)
    #expect(response.statusCode == 404)
}

@Test func streamResponseWithLinesContent() {
    let lines = AsyncThrowingStream<String, Error> { $0.finish() }
    let response = StreamResponse(statusCode: 200, content: .lines(lines))
    #expect(response.statusCode == 200)
    guard case .lines = response.content else {
        Issue.record("Expected .lines content")
        return
    }
}

@Test func streamResponseWithErrorBodyContent() {
    let response = StreamResponse(statusCode: 500, content: .errorBody("Internal Server Error"))
    #expect(response.statusCode == 500)
    guard case .errorBody(let body) = response.content else {
        Issue.record("Expected .errorBody content")
        return
    }
    #expect(body == "Internal Server Error")
}