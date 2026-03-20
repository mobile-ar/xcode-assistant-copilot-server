@testable import XcodeAssistantCopilotServer
import Testing
import Foundation

// MARK: - Response data builders

private func makeInitializeResponseData(id: Int = 1) -> Data {
    """
    {"jsonrpc":"2.0","id":\(id),"result":{}}
    """.data(using: .utf8)!
}

private func makeToolsListResponseData(
    id: Int = 1,
    toolName: String = "test_tool",
    toolDescription: String = "A test tool"
) -> Data {
    """
    {"jsonrpc":"2.0","id":\(id),"result":{"tools":[{"name":"\(toolName)","description":"\(toolDescription)"}]}}
    """.data(using: .utf8)!
}

private func makeToolCallResponseData(id: Int = 1, text: String = "result") -> Data {
    """
    {"jsonrpc":"2.0","id":\(id),"result":{"content":[{"type":"text","text":"\(text)"}]}}
    """.data(using: .utf8)!
}

private func makeErrorResponseData(
    id: Int = 1,
    code: Int = -32601,
    message: String = "Method not found"
) -> Data {
    """
    {"jsonrpc":"2.0","id":\(id),"error":{"code":\(code),"message":"\(message)"}}
    """.data(using: .utf8)!
}

// MARK: - Service factory helpers

private func makeService(
    url: String? = "https://example.com/mcp",
    configHeaders: [String: String]? = nil,
    serverName: String = "test-server",
    httpClient: MockHTTPClient
) -> MCPHTTPBridgeService {
    let config = MCPServerConfiguration(type: .http, url: url, headers: configHeaders)
    return MCPHTTPBridgeService(
        serverName: serverName,
        serverConfig: config,
        httpClient: httpClient,
        logger: MockLogger(),
        clientName: "test-client",
        clientVersion: "1.0.0"
    )
}

/// Prepares the mock client and calls `start()`.
/// Indices 0 and 1 of `executeResults` are consumed by `initialize` and
/// `notifications/initialized`. Pass `extraResults` to pre-fill indices 2+
/// for subsequent operations (e.g. `listTools`, `callTool`).
private func startService(
    sessionID: String? = nil,
    serverName: String = "test-server",
    httpClient: MockHTTPClient,
    extraResults: [Result<DataResponse, Error>] = []
) async throws -> MCPHTTPBridgeService {
    let initHeaders: [String: String] = sessionID.map { ["Mcp-Session-Id": $0] } ?? [:]
    httpClient.executeResults = [
        .success(DataResponse(data: makeInitializeResponseData(), statusCode: 200, headers: initHeaders)),
        .success(DataResponse(data: Data(), statusCode: 200)),
    ] + extraResults
    let service = makeService(serverName: serverName, httpClient: httpClient)
    try await service.start()
    return service
}

// MARK: - start()

@Test func httpBridgeStartThrowsInvalidConfigWhenURLMissing() async {
    let client = MockHTTPClient()
    let service = makeService(url: nil, httpClient: client)

    do {
        try await service.start()
        Issue.record("Expected invalidConfiguration to be thrown")
    } catch MCPBridgeError.invalidConfiguration {
        // expected
    } catch {
        Issue.record("Expected MCPBridgeError.invalidConfiguration, got \(error)")
    }
}

@Test func httpBridgeStartThrowsInvalidConfigWhenURLHasNoScheme() async {
    let client = MockHTTPClient()
    // A URL without a scheme passes URL(string:) on some platforms but must be
    // rejected by the http/https scheme guard in start().
    let service = makeService(url: "example.com/mcp", httpClient: client)

    do {
        try await service.start()
        Issue.record("Expected invalidConfiguration to be thrown")
    } catch MCPBridgeError.invalidConfiguration {
        // expected
    } catch {
        Issue.record("Expected MCPBridgeError.invalidConfiguration, got \(error)")
    }
}

@Test func httpBridgeStartThrowsAlreadyStartedOnDoubleStart() async throws {
    let client = MockHTTPClient()
    let service = try await startService(httpClient: client)

    do {
        try await service.start()
        Issue.record("Expected alreadyStarted to be thrown")
    } catch MCPBridgeError.alreadyStarted {
        // expected
    } catch {
        Issue.record("Expected MCPBridgeError.alreadyStarted, got \(error)")
    }
}

@Test func httpBridgeStartMakesTwoRequests() async throws {
    let client = MockHTTPClient()
    _ = try await startService(httpClient: client)

    #expect(client.executeCallCount == 2)
}

@Test func httpBridgeStartSendsNotificationsInitializedAsSecondRequest() async throws {
    let client = MockHTTPClient()
    _ = try await startService(httpClient: client)

    guard let body = client.sentEndpoints[1].body,
          let bodyString = String(data: body, encoding: .utf8) else {
        Issue.record("Expected second request to carry a body")
        return
    }
    // JSONEncoder escapes "/" as "\/" by default, so we match on both sides of the slash.
    #expect(bodyString.contains("notifications") && bodyString.contains("initialized"))
}

@Test func httpBridgeStartThrowsCommunicationFailedOnHTTPError() async {
    let client = MockHTTPClient()
    client.executeResults = [.success(DataResponse(data: Data(), statusCode: 500))]
    let service = makeService(httpClient: client)

    do {
        try await service.start()
        Issue.record("Expected communicationFailed to be thrown")
    } catch MCPBridgeError.communicationFailed {
        // expected
    } catch {
        Issue.record("Expected MCPBridgeError.communicationFailed, got \(error)")
    }
}

@Test func httpBridgeStartThrowsInitializationFailedWhenServerReturnsError() async {
    let client = MockHTTPClient()
    client.executeResults = [
        .success(DataResponse(data: makeErrorResponseData(code: -32000, message: "Server error"), statusCode: 200)),
    ]
    let service = makeService(httpClient: client)

    do {
        try await service.start()
        Issue.record("Expected initializationFailed to be thrown")
    } catch MCPBridgeError.initializationFailed(let message) {
        #expect(message == "Server error")
    } catch {
        Issue.record("Expected MCPBridgeError.initializationFailed, got \(error)")
    }
}

@Test func httpBridgeStartParsesInitializeResponseFromSSEBody() async throws {
    let sseBody = "data: {\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{}}\n"
    let client = MockHTTPClient()
    client.executeResults = [
        .success(DataResponse(
            data: sseBody.data(using: .utf8)!,
            statusCode: 200,
            headers: ["Content-Type": "text/event-stream"]
        )),
        .success(DataResponse(data: Data(), statusCode: 200)),
    ]
    let service = makeService(httpClient: client)

    // Must not throw — SSE body parser must locate the JSON data line
    try await service.start()
}

@Test func httpBridgeStartExtractsSessionIDFromResponseHeader() async throws {
    let client = MockHTTPClient()
    let service = try await startService(
        sessionID: "extracted-session",
        httpClient: client,
        extraResults: [
            .success(DataResponse(data: makeToolsListResponseData(), statusCode: 200)),
        ]
    )

    _ = try await service.listTools()

    // tools/list is the third request (index 2)
    let listEndpoint = client.sentEndpoints[2]
    #expect(listEndpoint.headers["Mcp-Session-Id"] == "extracted-session")
}

// MARK: - stop()

@Test func httpBridgeStopSendsDELETEWhenSessionIDPresent() async throws {
    let client = MockHTTPClient()
    let service = try await startService(sessionID: "my-session-id", httpClient: client)

    try await service.stop()

    // initialize (0) + notifications/initialized (1) + DELETE (2)
    #expect(client.executeCallCount == 3)
    #expect(client.sentEndpoints[2].method == .delete)
}

@Test func httpBridgeStopDoesNotSendDELETEWhenNoSessionID() async throws {
    let client = MockHTTPClient()
    let service = try await startService(sessionID: nil, httpClient: client)

    try await service.stop()

    // initialize (0) + notifications/initialized (1) — no DELETE
    #expect(client.executeCallCount == 2)
}

@Test func httpBridgeStopResetsStartedState() async throws {
    let client = MockHTTPClient()
    let service = try await startService(httpClient: client)

    try await service.stop()

    do {
        _ = try await service.listTools()
        Issue.record("Expected notStarted after stop")
    } catch MCPBridgeError.notStarted {
        // expected
    } catch {
        Issue.record("Expected MCPBridgeError.notStarted, got \(error)")
    }
}

@Test func httpBridgeStopAllowsRestartAfterwards() async throws {
    // Pre-populate results for both start calls upfront because MockHTTPClient
    // uses a monotonically increasing executeCallCount as the index into
    // executeResults. Results for the second start must be at indices 2 and 3.
    let client = MockHTTPClient()
    client.executeResults = [
        // First start: initialize (0) + notifications/initialized (1)
        .success(DataResponse(data: makeInitializeResponseData(), statusCode: 200)),
        .success(DataResponse(data: Data(), statusCode: 200)),
        // Second start: initialize (2) + notifications/initialized (3)
        .success(DataResponse(data: makeInitializeResponseData(), statusCode: 200)),
        .success(DataResponse(data: Data(), statusCode: 200)),
    ]
    let service = makeService(httpClient: client)
    try await service.start()
    try await service.stop()

    // Must not throw
    try await service.start()
}

// MARK: - listTools()

@Test func httpBridgeListToolsThrowsNotStartedBeforeStart() async {
    let client = MockHTTPClient()
    let service = makeService(httpClient: client)

    do {
        _ = try await service.listTools()
        Issue.record("Expected notStarted to be thrown")
    } catch MCPBridgeError.notStarted {
        // expected
    } catch {
        Issue.record("Expected MCPBridgeError.notStarted, got \(error)")
    }
}

@Test func httpBridgeListToolsDecodesToolsFromJSONResponse() async throws {
    let client = MockHTTPClient()
    let service = try await startService(
        serverName: "my-server",
        httpClient: client,
        extraResults: [
            .success(DataResponse(
                data: makeToolsListResponseData(toolName: "my_tool", toolDescription: "Does stuff"),
                statusCode: 200
            )),
        ]
    )

    let tools = try await service.listTools()

    #expect(tools.count == 1)
    #expect(tools[0].name == "my_tool")
    #expect(tools[0].description == "Does stuff")
    #expect(tools[0].serverName == "my-server")
}

@Test func httpBridgeListToolsReturnsCachedResultWithoutExtraHTTPCall() async throws {
    let client = MockHTTPClient()
    let service = try await startService(
        httpClient: client,
        extraResults: [
            .success(DataResponse(data: makeToolsListResponseData(), statusCode: 200)),
        ]
    )

    let first = try await service.listTools()
    let countAfterFirst = client.executeCallCount

    let second = try await service.listTools()

    #expect(first.count == second.count)
    #expect(client.executeCallCount == countAfterFirst)
}

@Test func httpBridgeListToolsIncludesSessionIDInRequest() async throws {
    let client = MockHTTPClient()
    let service = try await startService(
        sessionID: "sess-999",
        httpClient: client,
        extraResults: [
            .success(DataResponse(data: makeToolsListResponseData(), statusCode: 200)),
        ]
    )

    _ = try await service.listTools()

    let listEndpoint = client.sentEndpoints[2]
    #expect(listEndpoint.headers["Mcp-Session-Id"] == "sess-999")
}

@Test func httpBridgeListToolsHandlesEmptyToolsArray() async throws {
    let emptyTools = """
    {"jsonrpc":"2.0","id":1,"result":{"tools":[]}}
    """.data(using: .utf8)!
    let client = MockHTTPClient()
    let service = try await startService(
        httpClient: client,
        extraResults: [.success(DataResponse(data: emptyTools, statusCode: 200))]
    )

    let tools = try await service.listTools()

    #expect(tools.isEmpty)
}

// MARK: - callTool()

@Test func httpBridgeCallToolThrowsNotStartedBeforeStart() async {
    let client = MockHTTPClient()
    let service = makeService(httpClient: client)

    do {
        _ = try await service.callTool(name: "tool", arguments: [:])
        Issue.record("Expected notStarted to be thrown")
    } catch MCPBridgeError.notStarted {
        // expected
    } catch {
        Issue.record("Expected MCPBridgeError.notStarted, got \(error)")
    }
}

@Test func httpBridgeCallToolBuildsCorrectRequestPayload() async throws {
    let client = MockHTTPClient()
    let service = try await startService(
        httpClient: client,
        extraResults: [
            .success(DataResponse(data: makeToolCallResponseData(), statusCode: 200)),
        ]
    )

    _ = try await service.callTool(name: "file_reader", arguments: [:])

    #expect(client.executeCallCount == 3)
    let callEndpoint = client.sentEndpoints[2]
    #expect(callEndpoint.method == .post)
    guard let body = callEndpoint.body, let bodyString = String(data: body, encoding: .utf8) else {
        Issue.record("Expected call endpoint to carry a body")
        return
    }
    // JSONEncoder escapes "/" as "\/" by default, so check both sides of the slash separately.
    #expect(bodyString.contains("tools") && bodyString.contains("call"))
    #expect(bodyString.contains("file_reader"))
}

@Test func httpBridgeCallToolReturnsDecodedToolResult() async throws {
    let client = MockHTTPClient()
    let service = try await startService(
        httpClient: client,
        extraResults: [
            .success(DataResponse(data: makeToolCallResponseData(text: "42 files found"), statusCode: 200)),
        ]
    )

    let result = try await service.callTool(name: "search", arguments: [:])

    #expect(result.isError == false)
    #expect(result.textContent == "42 files found")
    #expect(result.content.count == 1)
    #expect(result.content[0].type == "text")
}

@Test func httpBridgeCallToolThrowsToolExecutionFailedOnErrorResponse() async throws {
    let client = MockHTTPClient()
    let service = try await startService(
        httpClient: client,
        extraResults: [
            .success(DataResponse(
                data: makeErrorResponseData(code: -32602, message: "Invalid params"),
                statusCode: 200
            )),
        ]
    )

    do {
        _ = try await service.callTool(name: "broken_tool", arguments: [:])
        Issue.record("Expected toolExecutionFailed to be thrown")
    } catch MCPBridgeError.toolExecutionFailed(let message) {
        #expect(message.contains("Invalid params"))
    } catch {
        Issue.record("Expected MCPBridgeError.toolExecutionFailed, got \(error)")
    }
}

@Test func httpBridgeCallToolIncludesSessionIDInRequest() async throws {
    let client = MockHTTPClient()
    let service = try await startService(
        sessionID: "session-xyz",
        httpClient: client,
        extraResults: [
            .success(DataResponse(data: makeToolCallResponseData(), statusCode: 200)),
        ]
    )

    _ = try await service.callTool(name: "tool", arguments: [:])

    let callEndpoint = client.sentEndpoints[2]
    #expect(callEndpoint.headers["Mcp-Session-Id"] == "session-xyz")
}

@Test func httpBridgeCallToolPassesArgumentsInRequestBody() async throws {
    let client = MockHTTPClient()
    let service = try await startService(
        httpClient: client,
        extraResults: [
            .success(DataResponse(data: makeToolCallResponseData(), statusCode: 200)),
        ]
    )

    _ = try await service.callTool(
        name: "echo",
        arguments: ["input": AnyCodable(.string("hello world"))]
    )

    guard let body = client.sentEndpoints[2].body,
          let bodyString = String(data: body, encoding: .utf8) else {
        Issue.record("Expected body")
        return
    }
    #expect(bodyString.contains("hello world"))
}

@Test func httpBridgeCallToolReturnsEmptyResultWhenNoContent() async throws {
    let noContent = """
    {"jsonrpc":"2.0","id":1,"result":{}}
    """.data(using: .utf8)!
    let client = MockHTTPClient()
    let service = try await startService(
        httpClient: client,
        extraResults: [.success(DataResponse(data: noContent, statusCode: 200))]
    )

    let result = try await service.callTool(name: "silent_tool", arguments: [:])

    #expect(result.content.isEmpty)
    #expect(result.isError == false)
}

// MARK: - MCPBridgeError invalidConfiguration description

@Test func mcpBridgeErrorInvalidConfigurationDescription() {
    let error = MCPBridgeError.invalidConfiguration("missing url")
    #expect(error.description == "Invalid MCP server configuration: missing url")
}

@Test func mcpBridgeErrorInvalidConfigurationEquality() {
    let a = MCPBridgeError.invalidConfiguration("x")
    let b = MCPBridgeError.invalidConfiguration("x")
    let c = MCPBridgeError.invalidConfiguration("y")
    #expect(a == b)
    #expect(a != c)
}