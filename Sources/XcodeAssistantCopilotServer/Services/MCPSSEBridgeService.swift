import Foundation

public actor MCPSSEBridgeService: MCPBridgeServiceProtocol {
    private let serverName: String
    private let serverConfig: MCPServerConfiguration
    private let httpClient: HTTPClientProtocol
    private let logger: LoggerProtocol
    private let clientName: String
    private let clientVersion: String

    private var messagesEndpointURL: String?
    private var endpointDiscoveryContinuation: CheckedContinuation<String, Error>?
    private var pendingRequests: [Int: CheckedContinuation<MCPResponse, Error>] = [:]
    private var cachedTools: [MCPTool]?
    private var sseTask: Task<Void, Never>?
    private var nextRequestId: Int = 1
    private var isStarted: Bool = false

    public init(
        serverName: String,
        serverConfig: MCPServerConfiguration,
        httpClient: HTTPClientProtocol,
        logger: LoggerProtocol,
        clientName: String,
        clientVersion: String
    ) {
        self.serverName = serverName
        self.serverConfig = serverConfig
        self.httpClient = httpClient
        self.logger = logger
        self.clientName = clientName
        self.clientVersion = clientVersion
    }

    public func start() async throws {
        guard !isStarted else {
            throw MCPBridgeError.alreadyStarted
        }
        guard let urlString = serverConfig.url,
              let parsedURL = URL(string: urlString),
              let scheme = parsedURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw MCPBridgeError.invalidConfiguration(
                "SSE MCP server requires a valid http/https 'url'"
            )
        }
        try await connectAndInitialize(sseURL: urlString)
        isStarted = true
    }

    public func stop() async throws {
        sseTask?.cancel()
        sseTask = nil

        endpointDiscoveryContinuation?.resume(
            throwing: MCPBridgeError.communicationFailed("Bridge is stopping")
        )
        endpointDiscoveryContinuation = nil

        for (id, continuation) in pendingRequests {
            continuation.resume(throwing: MCPBridgeError.communicationFailed("Bridge is stopping"))
            pendingRequests.removeValue(forKey: id)
        }

        isStarted = false
        messagesEndpointURL = nil
        cachedTools = nil
    }

    public func listTools() async throws -> [MCPTool] {
        guard isStarted else {
            throw MCPBridgeError.notStarted
        }
        if let cached = cachedTools {
            return cached
        }
        let response = try await sendMessage(method: "tools/list")
        guard let tools = response.result?.tools else {
            logger.warn("SSE MCP server '\(serverName)' returned no tools")
            cachedTools = []
            return []
        }
        let mcpTools = tools.map { MCPTool(from: $0, serverName: serverName) }
        cachedTools = mcpTools
        logger.info("SSE MCP server '\(serverName)' discovered \(mcpTools.count) tool(s)")
        return mcpTools
    }

    public func callTool(name: String, arguments: [String: AnyCodable]) async throws -> MCPToolResult {
        guard isStarted else {
            throw MCPBridgeError.notStarted
        }
        logger.debug("SSE MCP calling tool: \(name)")
        let params: [String: AnyCodable] = [
            "name": AnyCodable(.string(name)),
            "arguments": AnyCodable(.dictionary(arguments)),
        ]
        let response = try await sendMessage(method: "tools/call", params: params)
        if let error = response.error {
            throw MCPBridgeError.toolExecutionFailed("\(error.message) (code: \(error.code))")
        }
        guard let result = response.result else {
            return MCPToolResult(content: [], isError: false)
        }
        let content = (result.content ?? []).map { MCPToolResultContent(type: $0.type, text: $0.text) }
        let isError = result.raw["isError"]?.boolValue ?? false
        let toolResult = MCPToolResult(content: content, isError: isError)
        logger.debug("SSE MCP tool '\(name)' completed: \(toolResult.textContent)")
        return toolResult
    }

    private func connectAndInitialize(sseURL: String) async throws {
        let streamResponse: StreamResponse
        do {
            streamResponse = try await httpClient.stream(
                MCPSSEConnectionEndpoint(serverURL: sseURL, extraHeaders: serverConfig.headers ?? [:])
            )
        } catch {
            throw MCPBridgeError.communicationFailed("SSE connection failed: \(error.localizedDescription)")
        }

        guard (200...299).contains(streamResponse.statusCode) else {
            throw MCPBridgeError.communicationFailed(
                "SSE connection failed: HTTP \(streamResponse.statusCode)"
            )
        }

        guard case .lines(let lines) = streamResponse.content else {
            throw MCPBridgeError.communicationFailed(
                "SSE connection returned an error body instead of a stream"
            )
        }

        sseTask = Task { await self.runSSELoop(lines: lines) }

        let endpointURL = try await withCheckedThrowingContinuation { continuation in
            endpointDiscoveryContinuation = continuation
        }

        messagesEndpointURL = endpointURL
        logger.debug("SSE MCP server '\(serverName)' messages endpoint: \(endpointURL)")

        try await sendInitialize()
    }

    private func runSSELoop(lines: AsyncThrowingStream<String, Error>) async {
        let parser = SSEParser()
        let events = parser.parseLines(lines)

        do {
            for try await event in events {
                guard !Task.isCancelled else { break }
                if event.event == "endpoint" {
                    receiveEndpointEvent(url: event.data)
                } else {
                    dispatchResponse(data: event.data)
                }
            }
        } catch {
            logger.warn("SSE MCP server '\(serverName)' stream error: \(error)")
        }

        drainPendingRequestsOnStreamEnd()
    }

    private func receiveEndpointEvent(url: String) {
        endpointDiscoveryContinuation?.resume(returning: url)
        endpointDiscoveryContinuation = nil
    }

    private func dispatchResponse(data: String) {
        guard let jsonData = data.data(using: .utf8) else {
            logger.warn("SSE MCP server '\(serverName)': failed to convert event data to UTF-8")
            return
        }
        guard let response = try? JSONDecoder().decode(MCPResponse.self, from: jsonData) else {
            logger.debug("SSE MCP server '\(serverName)': received non-JSON-RPC event data, ignoring")
            return
        }
        guard let id = response.id, let continuation = pendingRequests.removeValue(forKey: id) else {
            logger.debug("SSE MCP server '\(serverName)': received notification or unmatched response")
            return
        }
        logger.debug("SSE MCP server '\(serverName)': resolved pending request #\(id)")
        continuation.resume(returning: response)
    }

    private func drainPendingRequestsOnStreamEnd() {
        endpointDiscoveryContinuation?.resume(
            throwing: MCPBridgeError.communicationFailed("SSE stream ended unexpectedly")
        )
        endpointDiscoveryContinuation = nil

        for (id, continuation) in pendingRequests {
            continuation.resume(
                throwing: MCPBridgeError.communicationFailed("SSE stream ended unexpectedly")
            )
            pendingRequests.removeValue(forKey: id)
        }
    }

    private func failPendingRequest(id: Int, error: Error) {
        guard let continuation = pendingRequests.removeValue(forKey: id) else { return }
        continuation.resume(
            throwing: MCPBridgeError.communicationFailed(
                "POST to messages endpoint failed: \(error.localizedDescription)"
            )
        )
    }

    private func sendMessage(method: String, params: [String: AnyCodable]? = nil) async throws -> MCPResponse {
        guard let url = messagesEndpointURL else {
            throw MCPBridgeError.notStarted
        }
        let requestId = nextRequestId
        nextRequestId += 1
        let request = MCPRequest(id: requestId, method: method, params: params)
        let requestData: Data
        do {
            requestData = try JSONEncoder().encode(request)
        } catch {
            throw MCPBridgeError.communicationFailed("Failed to encode request: \(error.localizedDescription)")
        }
        let endpoint = MCPSSEMessageEndpoint(
            messagesURL: url,
            requestData: requestData,
            extraHeaders: serverConfig.headers ?? [:]
        )
        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[requestId] = continuation
            Task {
                do {
                    _ = try await self.httpClient.execute(endpoint)
                } catch {
                    self.failPendingRequest(id: requestId, error: error)
                }
            }
        }
    }

    private func sendNotification(method: String, params: [String: AnyCodable]? = nil) async throws {
        guard let url = messagesEndpointURL else { return }
        let notification = MCPNotification(method: method, params: params)
        let notificationData: Data
        do {
            notificationData = try JSONEncoder().encode(notification)
        } catch {
            throw MCPBridgeError.communicationFailed(
                "Failed to encode notification: \(error.localizedDescription)"
            )
        }
        let endpoint = MCPSSEMessageEndpoint(
            messagesURL: url,
            requestData: notificationData,
            extraHeaders: serverConfig.headers ?? [:]
        )
        _ = try? await httpClient.execute(endpoint)
    }

    private func sendInitialize() async throws {
        let params: [String: AnyCodable] = [
            "protocolVersion": AnyCodable(.string(MCPConstants.protocolVersion)),
            "capabilities": AnyCodable(.dictionary([:])),
            "clientInfo": AnyCodable(.dictionary([
                "name": AnyCodable(.string(clientName)),
                "version": AnyCodable(.string(clientVersion)),
            ])),
        ]
        let response = try await sendMessage(method: "initialize", params: params)
        if let error = response.error {
            throw MCPBridgeError.initializationFailed(error.message)
        }
        logger.info("SSE MCP server '\(serverName)' initialized successfully")
        try await sendNotification(method: "notifications/initialized")
    }
}