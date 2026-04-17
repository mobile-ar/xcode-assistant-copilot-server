import Foundation

protocol MCPToolExecutorProtocol: Sendable {
    func execute(toolCall: ToolCall, serverName: String) async throws -> String
}

struct MCPToolExecutor: MCPToolExecutorProtocol, Sendable {
    private let bridgeHolder: MCPBridgeHolder
    private let configurationStore: ConfigurationStore
    private let logger: LoggerProtocol

    private static let defaultMCPToolTimeoutSeconds: Double = 60

    init(
        bridgeHolder: MCPBridgeHolder,
        configurationStore: ConfigurationStore,
        logger: LoggerProtocol
    ) {
        self.bridgeHolder = bridgeHolder
        self.configurationStore = configurationStore
        self.logger = logger
    }

    func execute(toolCall: ToolCall, serverName: String) async throws -> String {
        let configuration = await configurationStore.current()
        return try await execute(toolCall: toolCall, serverName: serverName, configuration: configuration)
    }

    private func execute(toolCall: ToolCall, serverName: String, configuration: ServerConfiguration) async throws -> String {
        guard let mcpBridge = await bridgeHolder.bridge else {
            return "Error: MCP bridge not available"
        }

        let toolName = toolCall.function.name ?? ""

        guard configuration.autoApprovePermissions.isApproved(.mcp) else {
            logger.warn("MCP tool execution not approved for '\(toolName)'")
            return "Error: MCP tool execution is not approved. Add 'mcp' to autoApprovePermissions."
        }

        guard configuration.isMCPToolAllowed(toolName) else {
            logger.warn("MCP tool '\(toolName)' is not in the allowed tools list")
            return "Error: MCP tool '\(toolName)' is not allowed by server configuration"
        }

        let arguments: [String: JSONValue]
        if let argumentsString = toolCall.function.arguments {
            logger.debug("MCP tool '\(toolName)' raw arguments (\(argumentsString.count) chars): \(argumentsString)")
            if let data = argumentsString.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([String: JSONValue].self, from: data) {
                arguments = decoded
                logger.debug("MCP tool '\(toolName)' parsed \(arguments.count) argument(s): \(arguments.keys.sorted().joined(separator: ", "))")
            } else {
                logger.error("MCP tool '\(toolName)' failed to parse arguments JSON (\(argumentsString.count) chars) — sending empty arguments")
                arguments = [:]
            }
        } else {
            logger.debug("MCP tool '\(toolName)' has no arguments")
            arguments = [:]
        }

        let timeoutSeconds = resolvedMCPToolTimeoutSeconds(serverName: serverName, configuration: configuration)

        do {
            let result = try await callMCPToolWithTimeout(
                bridge: mcpBridge,
                toolName: toolName,
                arguments: arguments,
                timeoutSeconds: timeoutSeconds
            )
            let text = result.textContent

            if TabIdentifierResolver.isTabIdentifierError(text) {
                let filePath = arguments["filePath"]?.stringValue
                    ?? arguments["sourceFilePath"]?.stringValue
                    ?? arguments["path"]?.stringValue

                if let resolvedTab = TabIdentifierResolver.resolve(from: text, filePath: filePath) {
                    logger.debug("MCP tool '\(toolName)' got invalid tabIdentifier — retrying with resolved '\(resolvedTab)'")
                    var fixedArguments = arguments
                    fixedArguments["tabIdentifier"] = .string(resolvedTab)
                    let retryResult = try await callMCPToolWithTimeout(
                        bridge: mcpBridge,
                        toolName: toolName,
                        arguments: fixedArguments,
                        timeoutSeconds: timeoutSeconds
                    )
                    return retryResult.textContent
                }
            }

            return text
        } catch is CancellationError {
            logger.debug("MCP tool '\(toolName)' cancelled")
            throw CancellationError()
        } catch let error as MCPToolExecutionError {
            switch error {
            case .timedOut(let timedOutToolName, let timedOutSeconds):
                logger.warn("MCP tool '\(timedOutToolName)' timed out after \(timedOutSeconds) seconds")
                return "Error executing tool \(timedOutToolName): timed out after \(timedOutSeconds) seconds"
            }
        } catch {
            logger.error("MCP tool \(toolName) failed: \(error)")
            return "Error executing tool \(toolName): \(error)"
        }
    }

    private func callMCPToolWithTimeout(
        bridge: MCPBridgeServiceProtocol,
        toolName: String,
        arguments: [String: JSONValue],
        timeoutSeconds: Double
    ) async throws -> MCPToolResult {
        try await withThrowingTaskGroup(of: MCPToolResult.self) { group in
            group.addTask {
                try await bridge.callTool(name: toolName, arguments: arguments)
            }

            group.addTask {
                try await Task.sleep(for: .seconds(timeoutSeconds))
                throw MCPToolExecutionError.timedOut(toolName: toolName, timeoutSeconds: timeoutSeconds)
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func resolvedMCPToolTimeoutSeconds(serverName: String, configuration: ServerConfiguration) -> Double {
        guard !serverName.isEmpty,
              let configuredTimeout = configuration.mcpServers[serverName]?.timeoutSeconds,
              configuredTimeout > 0 else {
            return Self.defaultMCPToolTimeoutSeconds
        }
        return configuredTimeout
    }
}

private enum MCPToolExecutionError: Error {
    case timedOut(toolName: String, timeoutSeconds: Double)
}