@testable import XcodeAssistantCopilotServer
import Testing
import Foundation
import Synchronization

// MARK: - SSEStreamController

private final class SSEStreamController: Sendable {
    private let cont: Mutex<AsyncThrowingStream<String, Error>.Continuation?>
    let stream: AsyncThrowingStream<String, Error>

    init() {
        let holder = Mutex<AsyncThrowingStream<String, Error>.Continuation?>(nil)
        stream = AsyncThrowingStream<String, Error>(bufferingPolicy: .unbounded) { continuation in
            holder.withLock { $0 = continuation }
        }
        cont = holder
    }

    func sendLine(_ line: String) {
        _ = cont.withLock { $0?.yield(line) }
    }

    /// Sends the two-line SSE block that the parser maps to an `SSEEvent` with `event == "endpoint"`.
    func sendEndpointEvent(url: String) {
        sendLine("event: endpoint")
        sendLine("data: \(url)")
    }

    /// Sends a JSON-RPC payload as an SSE data event.
    /// Prefixes with `event: message` so the bridge's `runSSELoop` routes it to
    /// `dispatchResponse` rather than `receiveEndpointEvent`. This is required because
    /// `SSEParser` does not reset `currentEvent` between events, so any data line that
    /// follows an `event: endpoint` header would otherwise still carry `event == "endpoint"`.
    func sendJSONRPCEvent(_ json: String) {
        sendLine("event: message")
        sendLine("data: \(json)")
    }

    func finish() {
        cont.withLock { $0?.finish() }
    }

    func finish(throwing error: any Error) {
        cont.withLock { $0?.finish(throwing: error) }
    }
}

// MARK: - Service factory helper

private func makeSSEBridgeService(
    sseURL: String = "http://test.example.com/sse",
    serverName: String = "test-server",
    httpClient: MockHTTPClient
) -> MCPSSEBridgeService {
    let config = MCPServerConfiguration(type: .sse, url: sseURL)
    return MCPSSEBridgeService(
        serverName: serverName,
        serverConfig: config,
        httpClient: httpClient,
        logger: MockLogger(),
        clientName: "test-client",
        clientVersion: "1.0.0"
    )
}

/// Drives a complete, successful `start()` sequence and returns the started service.
///
/// Steps:
/// 1. Pre-sends the `endpoint` SSE event (buffered until the internal sseTask reads it).
/// 2. Calls `start()` in a background task.
/// 3. Spins with `Task.yield()` until the `initialize` POST appears (executeCallCount ≥ 1),
///    then injects the matching JSON-RPC response via SSE.
/// 4. Spins until `notifications/initialized` POST appears (executeCallCount ≥ 2).
/// 5. Awaits the start task and returns the started service.
///
/// On return `httpClient.executeCallCount == 2`.
private func startService(
    sseURL: String = "http://test.example.com/sse",
    messagesURL: String = "http://test.example.com/messages",
    serverName: String = "test-server",
    httpClient: MockHTTPClient,
    sseController: SSEStreamController
) async throws -> MCPSSEBridgeService {
    httpClient.streamResults = [
        .success(StreamResponse(statusCode: 200, content: .lines(sseController.stream))),
    ]

    let service = makeSSEBridgeService(sseURL: sseURL, serverName: serverName, httpClient: httpClient)

    sseController.sendEndpointEvent(url: messagesURL)
    let startTask = Task<Void, Error> { try await service.start() }

    // Wait until the initialize POST is dispatched.
    // At this point pendingRequests[1] is already registered (it is set synchronously
    // inside withCheckedThrowingContinuation before the inner POST Task fires).
    while httpClient.executeCallCount < 1 { await Task.yield() }
    sseController.sendJSONRPCEvent(#"{"jsonrpc":"2.0","id":1,"result":{}}"#)

    // Wait until the notifications/initialized POST is dispatched.
    while httpClient.executeCallCount < 2 { await Task.yield() }

    try await startTask.value
    return service
}

// MARK: - start()

@Test func sseBridgeStartThrowsInvalidConfigWhenURLMissing() async {
    let client = MockHTTPClient()
    let config = MCPServerConfiguration(type: .sse, url: nil)
    let service = MCPSSEBridgeService(
        serverName: "test",
        serverConfig: config,
        httpClient: client,
        logger: MockLogger(),
        clientName: "c",
        clientVersion: "1"
    )

    do {
        try await service.start()
        Issue.record("Expected invalidConfiguration to be thrown")
    } catch MCPBridgeError.invalidConfiguration {
        // expected
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func sseBridgeStartThrowsInvalidConfigWhenURLHasNoScheme() async {
    let client = MockHTTPClient()
    // A URL without an http/https scheme must be rejected by the scheme guard in start().
    let config = MCPServerConfiguration(type: .sse, url: "example.com/sse")
    let service = MCPSSEBridgeService(
        serverName: "test",
        serverConfig: config,
        httpClient: client,
        logger: MockLogger(),
        clientName: "c",
        clientVersion: "1"
    )

    do {
        try await service.start()
        Issue.record("Expected invalidConfiguration to be thrown")
    } catch MCPBridgeError.invalidConfiguration {
        // expected
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func sseBridgeStartThrowsAlreadyStartedOnDoubleStart() async throws {
    let client = MockHTTPClient()
    let controller = SSEStreamController()
    let service = try await startService(httpClient: client, sseController: controller)

    do {
        try await service.start()
        Issue.record("Expected alreadyStarted to be thrown")
    } catch MCPBridgeError.alreadyStarted {
        // expected
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    try await service.stop()
    controller.finish()
}

@Test func sseBridgeStartThrowsCommunicationFailedOnNon2xxStreamStatus() async {
    let client = MockHTTPClient()
    client.streamResults = [
        .success(StreamResponse(statusCode: 503, content: .errorBody("Service Unavailable"))),
    ]
    let service = makeSSEBridgeService(httpClient: client)

    do {
        try await service.start()
        Issue.record("Expected communicationFailed to be thrown")
    } catch MCPBridgeError.communicationFailed {
        // expected
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func sseBridgeStartThrowsCommunicationFailedWhenHTTPStreamCallFails() async {
    let client = MockHTTPClient()
    client.streamResults = [
        .failure(HTTPClientError.networkError("Connection refused")),
    ]
    let service = makeSSEBridgeService(httpClient: client)

    do {
        try await service.start()
        Issue.record("Expected communicationFailed to be thrown")
    } catch MCPBridgeError.communicationFailed {
        // expected
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func sseBridgeStartCompletesSuccessfully() async throws {
    let client = MockHTTPClient()
    let controller = SSEStreamController()
    let service = try await startService(httpClient: client, sseController: controller)

    // initialize POST (0) + notifications/initialized POST (1)
    #expect(client.executeCallCount == 2)

    try await service.stop()
    controller.finish()
}

@Test func sseBridgeStartSendsInitializeWithCorrectProtocolVersion() async throws {
    let client = MockHTTPClient()
    let controller = SSEStreamController()
    _ = try await startService(httpClient: client, sseController: controller)

    // sentEndpoints[0] = SSE connection (stream call)
    // sentEndpoints[1] = initialize POST (first execute call)
    guard let body = client.sentEndpoints[1].body,
          let bodyString = String(data: body, encoding: .utf8) else {
        Issue.record("Expected initialize body at sentEndpoints[1]")
        controller.finish()
        return
    }
    #expect(bodyString.contains("initialize"))
    #expect(bodyString.contains("2025-11-25"))
    controller.finish()
}

@Test func sseBridgeStartSendsNotificationsInitializedAsSecondPost() async throws {
    let client = MockHTTPClient()
    let controller = SSEStreamController()
    _ = try await startService(httpClient: client, sseController: controller)

    // sentEndpoints[0] = SSE connection (stream call)
    // sentEndpoints[1] = initialize POST (first execute call)
    // sentEndpoints[2] = notifications/initialized POST (second execute call)
    guard let body = client.sentEndpoints[2].body,
          let bodyString = String(data: body, encoding: .utf8) else {
        Issue.record("Expected notifications/initialized body at sentEndpoints[2]")
        controller.finish()
        return
    }
    // JSONEncoder escapes "/" as "\/" by default, so match both sides of the slash.
    #expect(bodyString.contains("notifications") && bodyString.contains("initialized"))
    controller.finish()
}

@Test func sseBridgeStartThrowsInitializationFailedWhenServerReturnsError() async {
    let client = MockHTTPClient()
    let controller = SSEStreamController()
    client.streamResults = [
        .success(StreamResponse(statusCode: 200, content: .lines(controller.stream))),
    ]
    controller.sendEndpointEvent(url: "http://test.example.com/messages")

    let service = makeSSEBridgeService(httpClient: client)
    let startTask = Task<Void, Error> { try await service.start() }

    while client.executeCallCount < 1 { await Task.yield() }
    controller.sendJSONRPCEvent(#"{"jsonrpc":"2.0","id":1,"error":{"code":-32000,"message":"Init failed"}}"#)

    do {
        try await startTask.value
        Issue.record("Expected initializationFailed to be thrown")
    } catch MCPBridgeError.initializationFailed(let message) {
        #expect(message == "Init failed")
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
    controller.finish()
}

// MARK: - stop()

@Test func sseBridgeStopResetsStartedStateSoSubsequentCallsThrowNotStarted() async throws {
    let client = MockHTTPClient()
    let controller = SSEStreamController()
    let service = try await startService(httpClient: client, sseController: controller)

    try await service.stop()
    controller.finish()

    do {
        _ = try await service.listTools()
        Issue.record("Expected notStarted after stop")
    } catch MCPBridgeError.notStarted {
        // expected
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func sseBridgeStopDrainsPendingRequestsWithCommunicationFailed() async throws {
    let client = MockHTTPClient()
    let controller = SSEStreamController()
    let service = try await startService(httpClient: client, sseController: controller)

    // Start a callTool that will block waiting for an SSE response
    let callTask = Task<MCPToolResult, Error> {
        try await service.callTool(name: "slow_tool", arguments: [:])
    }

    // Wait until the callTool POST is dispatched (executeCallCount: 2 → 3).
    // At this point pendingRequests[2] is registered.
    while client.executeCallCount < 3 { await Task.yield() }

    // Stop before delivering the SSE response
    try await service.stop()
    controller.finish()

    do {
        _ = try await callTask.value
        Issue.record("Expected communicationFailed after stop")
    } catch MCPBridgeError.communicationFailed {
        // expected
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func sseBridgeStopAllowsRestartAfterwards() async throws {
    let client = MockHTTPClient()
    let controller1 = SSEStreamController()
    let service = try await startService(httpClient: client, sseController: controller1)

    try await service.stop()
    controller1.finish()

    // Re-start with a fresh SSE stream.
    // Note: nextRequestId was 2 after the first start, so the re-initialize uses id=2.
    //
    // MockHTTPClient.streamCallCount is 1 after the first start, so the next stream()
    // call reads streamResults[1]. We must pad index 0 with a dummy entry so that
    // the real controller2 stream ends up at index 1.
    let controller2 = SSEStreamController()
    client.streamResults = [
        .success(StreamResponse(statusCode: 200, content: .errorBody(""))),
        .success(StreamResponse(statusCode: 200, content: .lines(controller2.stream))),
    ]
    controller2.sendEndpointEvent(url: "http://test.example.com/messages")

    let restartTask = Task<Void, Error> { try await service.start() }

    // executeCallCount is 2 after first start.
    // Re-initialize POST becomes index 2 (count becomes 3).
    while client.executeCallCount < 3 { await Task.yield() }
    controller2.sendJSONRPCEvent(#"{"jsonrpc":"2.0","id":2,"result":{}}"#)

    // notifications/initialized POST becomes index 3 (count becomes 4).
    while client.executeCallCount < 4 { await Task.yield() }

    try await restartTask.value

    try await service.stop()
    controller2.finish()
}

// MARK: - listTools()

@Test func sseBridgeListToolsThrowsNotStartedBeforeStart() async {
    let client = MockHTTPClient()
    let service = makeSSEBridgeService(httpClient: client)

    do {
        _ = try await service.listTools()
        Issue.record("Expected notStarted to be thrown")
    } catch MCPBridgeError.notStarted {
        // expected
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func sseBridgeListToolsDecodesToolsFromSSEResponse() async throws {
    let client = MockHTTPClient()
    let controller = SSEStreamController()
    let service = try await startService(serverName: "srv", httpClient: client, sseController: controller)

    let listTask = Task<[MCPTool], Error> { try await service.listTools() }

    // tools/list POST becomes executeCallCount index 2 (count: 2 → 3)
    while client.executeCallCount < 3 { await Task.yield() }
    controller.sendJSONRPCEvent(#"{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"read_file","description":"Reads a file"}]}}"#)

    let tools = try await listTask.value

    #expect(tools.count == 1)
    #expect(tools[0].name == "read_file")
    #expect(tools[0].description == "Reads a file")
    #expect(tools[0].serverName == "srv")

    try await service.stop()
    controller.finish()
}

@Test func sseBridgeListToolsReturnsCachedResultWithoutExtraPost() async throws {
    let client = MockHTTPClient()
    let controller = SSEStreamController()
    let service = try await startService(httpClient: client, sseController: controller)

    let listTask1 = Task<[MCPTool], Error> { try await service.listTools() }
    while client.executeCallCount < 3 { await Task.yield() }
    controller.sendJSONRPCEvent(#"{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"t1"}]}}"#)
    let firstTools = try await listTask1.value

    let countAfterFirst = client.executeCallCount

    // Second call must be served from cache — no new POST should be issued
    let secondTools = try await service.listTools()

    #expect(firstTools.count == secondTools.count)
    #expect(client.executeCallCount == countAfterFirst)

    try await service.stop()
    controller.finish()
}

@Test func sseBridgeListToolsHandlesEmptyToolsArray() async throws {
    let client = MockHTTPClient()
    let controller = SSEStreamController()
    let service = try await startService(httpClient: client, sseController: controller)

    let listTask = Task<[MCPTool], Error> { try await service.listTools() }
    while client.executeCallCount < 3 { await Task.yield() }
    controller.sendJSONRPCEvent(#"{"jsonrpc":"2.0","id":2,"result":{"tools":[]}}"#)

    let tools = try await listTask.value
    #expect(tools.isEmpty)

    try await service.stop()
    controller.finish()
}

// MARK: - callTool()

@Test func sseBridgeCallToolThrowsNotStartedBeforeStart() async {
    let client = MockHTTPClient()
    let service = makeSSEBridgeService(httpClient: client)

    do {
        _ = try await service.callTool(name: "tool", arguments: [:])
        Issue.record("Expected notStarted to be thrown")
    } catch MCPBridgeError.notStarted {
        // expected
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func sseBridgeCallToolMatchesResponseByRequestID() async throws {
    let client = MockHTTPClient()
    let controller = SSEStreamController()
    let service = try await startService(httpClient: client, sseController: controller)

    let callTask = Task<MCPToolResult, Error> {
        try await service.callTool(name: "greet", arguments: [:])
    }

    while client.executeCallCount < 3 { await Task.yield() }
    controller.sendJSONRPCEvent(#"{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"hello"}]}}"#)

    let result = try await callTask.value
    #expect(result.isError == false)
    #expect(result.textContent == "hello")

    try await service.stop()
    controller.finish()
}

@Test func sseBridgeCallToolThrowsToolExecutionFailedOnErrorResponse() async throws {
    let client = MockHTTPClient()
    let controller = SSEStreamController()
    let service = try await startService(httpClient: client, sseController: controller)

    let callTask = Task<MCPToolResult, Error> {
        try await service.callTool(name: "bad_tool", arguments: [:])
    }

    while client.executeCallCount < 3 { await Task.yield() }
    controller.sendJSONRPCEvent(#"{"jsonrpc":"2.0","id":2,"error":{"code":-32601,"message":"Not found"}}"#)

    do {
        _ = try await callTask.value
        Issue.record("Expected toolExecutionFailed to be thrown")
    } catch MCPBridgeError.toolExecutionFailed(let message) {
        #expect(message.contains("Not found"))
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    try await service.stop()
    controller.finish()
}

@Test func sseBridgeCallToolBuildsCorrectRequestBody() async throws {
    let client = MockHTTPClient()
    let controller = SSEStreamController()
    let service = try await startService(httpClient: client, sseController: controller)

    let callTask = Task<MCPToolResult, Error> {
        try await service.callTool(
            name: "search_files",
            arguments: ["query": AnyCodable(.string("main.swift"))]
        )
    }

    // sentEndpoints[0] = SSE connection (stream call)
    // sentEndpoints[1] = initialize POST
    // sentEndpoints[2] = notifications/initialized POST
    // sentEndpoints[3] = callTool POST (executeCallCount: 2 → 3)
    while client.executeCallCount < 3 { await Task.yield() }

    guard let body = client.sentEndpoints[3].body,
          let bodyString = String(data: body, encoding: .utf8) else {
        Issue.record("Expected body at sentEndpoints[3]")
        controller.finish()
        return
    }
    // JSONEncoder escapes "/" as "\/" by default, so match both sides of the slash.
    #expect(bodyString.contains("tools") && bodyString.contains("call"))
    #expect(bodyString.contains("search_files"))
    #expect(bodyString.contains("main.swift"))

    controller.sendJSONRPCEvent(#"{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"found"}]}}"#)
    _ = try await callTask.value

    try await service.stop()
    controller.finish()
}

@Test func sseBridgeCallToolIgnoresResponsesWithUnknownID() async throws {
    let client = MockHTTPClient()
    let controller = SSEStreamController()
    let service = try await startService(httpClient: client, sseController: controller)

    let callTask = Task<MCPToolResult, Error> {
        try await service.callTool(name: "tool", arguments: [:])
    }

    while client.executeCallCount < 3 { await Task.yield() }

    // Send a stale response for an unrelated request ID first
    controller.sendJSONRPCEvent(#"{"jsonrpc":"2.0","id":999,"result":{"content":[]}}"#)
    // Then send the correct response
    controller.sendJSONRPCEvent(#"{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"ok"}]}}"#)

    let result = try await callTask.value
    #expect(result.textContent == "ok")

    try await service.stop()
    controller.finish()
}

@Test func sseBridgeCallToolThrowsCommunicationFailedWhenStreamEndsUnexpectedly() async throws {
    let client = MockHTTPClient()
    let controller = SSEStreamController()
    let service = try await startService(httpClient: client, sseController: controller)

    let callTask = Task<MCPToolResult, Error> {
        try await service.callTool(name: "wait_tool", arguments: [:])
    }

    // Wait for the callTool POST so pendingRequests[2] is registered
    while client.executeCallCount < 3 { await Task.yield() }

    // Close the stream without delivering a response
    controller.finish()

    do {
        _ = try await callTask.value
        Issue.record("Expected communicationFailed when stream ends")
    } catch MCPBridgeError.communicationFailed {
        // expected
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}
