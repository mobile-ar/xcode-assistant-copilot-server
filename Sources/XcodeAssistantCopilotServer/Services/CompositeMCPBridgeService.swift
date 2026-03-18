import Foundation

public actor CompositeMCPBridgeService: MCPBridgeServiceProtocol {
    private let entries: [BridgeEntry]
    private let logger: LoggerProtocol
    private var startedBridges: [MCPBridgeServiceProtocol] = []
    private var toolToBridge: [String: MCPBridgeServiceProtocol] = [:]
    private var cachedTools: [MCPTool]?

    public init(
        bridges: [(serverName: String, bridge: MCPBridgeServiceProtocol)],
        logger: LoggerProtocol
    ) {
        self.entries = bridges.map { BridgeEntry(serverName: $0.serverName, bridge: $0.bridge) }
        self.logger = logger
    }

    public func start() async throws {
        var launched: [MCPBridgeServiceProtocol] = []

        await withTaskGroup(of: BridgeStartResult.self) { group in
            for entry in entries {
                group.addTask {
                    do {
                        try await entry.bridge.start()
                        return BridgeStartResult(serverName: entry.serverName, bridge: entry.bridge, error: nil)
                    } catch {
                        return BridgeStartResult(serverName: entry.serverName, bridge: nil, error: error)
                    }
                }
            }

            for await result in group {
                if let bridge = result.bridge {
                    launched.append(bridge)
                    logger.info("MCP bridge '\(result.serverName)' started successfully")
                } else if let error = result.error {
                    logger.warn("MCP bridge '\(result.serverName)' failed to start: \(error) — skipping")
                }
            }
        }

        startedBridges = launched
    }

    public func stop() async throws {
        await withTaskGroup(of: Void.self) { group in
            for bridge in startedBridges {
                group.addTask {
                    try? await bridge.stop()
                }
            }
        }
        startedBridges = []
        toolToBridge = [:]
        cachedTools = nil
    }

    public func listTools() async throws -> [MCPTool] {
        if let cached = cachedTools {
            return cached
        }

        var allTools: [MCPTool] = []
        var mapping: [String: MCPBridgeServiceProtocol] = [:]

        for bridge in startedBridges {
            let tools: [MCPTool]
            do {
                tools = try await bridge.listTools()
            } catch {
                logger.warn("Failed to list tools from a bridge: \(error) — skipping")
                continue
            }

            for tool in tools {
                if mapping[tool.name] != nil {
                    logger.warn("Tool name conflict: '\(tool.name)' is advertised by multiple bridges. First registration wins.")
                } else {
                    mapping[tool.name] = bridge
                    allTools.append(tool)
                }
            }
        }

        toolToBridge = mapping
        cachedTools = allTools
        logger.info("Composite MCP bridge discovered \(allTools.count) tool(s) across \(startedBridges.count) bridge(s)")
        return allTools
    }

    public func callTool(name: String, arguments: [String: AnyCodable]) async throws -> MCPToolResult {
        if toolToBridge.isEmpty {
            _ = try await listTools()
        }

        guard let bridge = toolToBridge[name] else {
            throw MCPBridgeError.toolExecutionFailed("No bridge found for tool: \(name)")
        }

        return try await bridge.callTool(name: name, arguments: arguments)
    }
}

private struct BridgeEntry {
    let serverName: String
    let bridge: MCPBridgeServiceProtocol
}

private struct BridgeStartResult: Sendable {
    let serverName: String
    let bridge: MCPBridgeServiceProtocol?
    let error: Error?
}
