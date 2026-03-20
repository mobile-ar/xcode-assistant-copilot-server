import Foundation

public actor MCPHTTPBridgeService: MCPBridgeServiceProtocol {
    private let serverName: String
    private let serverConfig: MCPServerConfiguration
    private let httpClient: HTTPClientProtocol
    private let logger: LoggerProtocol
    private let clientName: String
    private let clientVersion: String

    private var sessionID: String?
    private var isStarted: Bool = false
    private var cachedTools: [MCPTool]?
    private var nextRequestId: Int = 1

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
                "HTTP MCP server requires a valid http/https 'url'"
            )
        }
        try await sendInitialize()
        isStarted = true
    }

    public func stop() async throws {
        if let id = sessionID, let urlString = serverConfig.url {
            let endpoint = MCPHTTPTerminateEndpoint(
                serverURL: urlString,
                sessionID: id,
                extraHeaders: serverConfig.headers ?? [:]
            )
            _ = try? await httpClient.execute(endpoint)
        }
        isStarted = false
        sessionID = nil
        cachedTools = nil
    }

    public func listTools() async throws -> [MCPTool] {
        guard isStarted else {
            throw MCPBridgeError.notStarted
        }
        if let cached = cachedTools {
            return cached
        }
        let response = try await sendRequest(method: "tools/list")
        guard let tools = response.result?.tools else {
            logger.warn("HTTP MCP server '\(serverName)' returned no tools")
            cachedTools = []
            return []
        }
        let mcpTools = tools.map { MCPTool(from: $0, serverName: serverName) }
        cachedTools = mcpTools
        logger.info("HTTP MCP server '\(serverName)' discovered \(mcpTools.count) tool(s)")
        return mcpTools
    }

    public func callTool(name: String, arguments: [String: AnyCodable]) async throws -> MCPToolResult {
        guard isStarted else {
            throw MCPBridgeError.notStarted
        }
        logger.debug("HTTP MCP calling tool: \(name)")
        let params: [String: AnyCodable] = [
            "name": AnyCodable(.string(name)),
            "arguments": AnyCodable(.dictionary(arguments)),
        ]
        let response = try await sendRequest(method: "tools/call", params: params)
        if let error = response.error {
            throw MCPBridgeError.toolExecutionFailed("\(error.message) (code: \(error.code))")
        }
        guard let result = response.result else {
            return MCPToolResult(content: [], isError: false)
        }
        let content = (result.content ?? []).map { MCPToolResultContent(type: $0.type, text: $0.text) }
        let isError = result.raw["isError"]?.boolValue ?? false
        let toolResult = MCPToolResult(content: content, isError: isError)
        logger.debug("HTTP MCP tool '\(name)' completed: \(toolResult.textContent)")
        return toolResult
    }

    private func sendRequest(method: String, params: [String: AnyCodable]? = nil) async throws -> MCPResponse {
        guard let urlString = serverConfig.url else {
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
        let endpoint = MCPHTTPRequestEndpoint(
            serverURL: urlString,
            requestData: requestData,
            sessionID: sessionID,
            extraHeaders: serverConfig.headers ?? [:]
        )
        let dataResponse: DataResponse
        do {
            dataResponse = try await httpClient.execute(endpoint)
        } catch {
            throw MCPBridgeError.communicationFailed("HTTP request failed: \(error.localizedDescription)")
        }
        guard (200...299).contains(dataResponse.statusCode) else {
            let body = String(data: dataResponse.data, encoding: .utf8) ?? "(empty)"
            throw MCPBridgeError.communicationFailed("HTTP \(dataResponse.statusCode): \(body)")
        }
        if sessionID == nil {
            sessionID = dataResponse.headers["Mcp-Session-Id"]
        }
        let contentType = dataResponse.headers["Content-Type"] ?? ""
        if contentType.contains("text/event-stream") {
            return try parseSSEBodyForResponse(data: dataResponse.data)
        }
        do {
            return try JSONDecoder().decode(MCPResponse.self, from: dataResponse.data)
        } catch {
            throw MCPBridgeError.communicationFailed("Failed to decode response: \(error.localizedDescription)")
        }
    }

    private func parseSSEBodyForResponse(data: Data) throws -> MCPResponse {
        guard let text = String(data: data, encoding: .utf8) else {
            throw MCPBridgeError.communicationFailed("Failed to decode SSE body as UTF-8")
        }
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var trimmed = line.drop(while: { $0 == " " || $0 == "\r" })
            guard trimmed.hasPrefix("data:") else { continue }
            trimmed = trimmed.dropFirst("data:".count)
            if trimmed.first == " " { trimmed = trimmed.dropFirst() }
            let value = String(trimmed)
            guard !value.isEmpty, value != "[DONE]" else { continue }
            guard let jsonData = value.data(using: .utf8) else { continue }
            if let response = try? JSONDecoder().decode(MCPResponse.self, from: jsonData) {
                return response
            }
        }
        throw MCPBridgeError.communicationFailed("No valid JSON-RPC response found in SSE body")
    }

    private func sendNotification(method: String, params: [String: AnyCodable]? = nil) async throws {
        guard let urlString = serverConfig.url else { return }
        let notification = MCPNotification(method: method, params: params)
        let notificationData: Data
        do {
            notificationData = try JSONEncoder().encode(notification)
        } catch {
            throw MCPBridgeError.communicationFailed("Failed to encode notification: \(error.localizedDescription)")
        }
        let endpoint = MCPHTTPRequestEndpoint(
            serverURL: urlString,
            requestData: notificationData,
            sessionID: sessionID,
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
        let response = try await sendRequest(method: "initialize", params: params)
        if let error = response.error {
            throw MCPBridgeError.initializationFailed(error.message)
        }
        logger.info("HTTP MCP server '\(serverName)' initialized successfully")
        try await sendNotification(method: "notifications/initialized")
    }
}