import Foundation

public struct MCPBridgeFactory: Sendable {
    public static func make(
        from configuration: ServerConfiguration,
        logger: LoggerProtocol,
        httpClient: HTTPClientProtocol,
        pidFile: MCPBridgePIDFileProtocol?,
        clientName: String,
        clientVersion: String,
        processRunner: ProcessRunnerProtocol
    ) -> MCPBridgeServiceProtocol? {
        guard !configuration.mcpServers.isEmpty else {
            return nil
        }

        let sortedServers = configuration.mcpServers.sorted { $0.key < $1.key }

        let bridges: [(serverName: String, bridge: MCPBridgeServiceProtocol)] = sortedServers.map { name, serverConfig in
            let bridge = makeBridge(
                serverName: name,
                serverConfig: serverConfig,
                logger: logger,
                httpClient: httpClient,
                pidFile: pidFile,
                clientName: clientName,
                clientVersion: clientVersion,
                processRunner: processRunner
            )
            return (serverName: name, bridge: bridge)
        }

        if bridges.count == 1, let entry = bridges.first {
            return entry.bridge
        }

        return CompositeMCPBridgeService(bridges: bridges, logger: logger)
    }

    private static func makeBridge(
        serverName: String,
        serverConfig: MCPServerConfiguration,
        logger: LoggerProtocol,
        httpClient: HTTPClientProtocol,
        pidFile: MCPBridgePIDFileProtocol?,
        clientName: String,
        clientVersion: String,
        processRunner: ProcessRunnerProtocol
    ) -> MCPBridgeServiceProtocol {
        switch serverConfig.type {
        case .local, .stdio:
            return MCPBridgeService(
                serverName: serverName,
                serverConfig: serverConfig,
                logger: logger,
                pidFile: pidFile,
                clientName: clientName,
                clientVersion: clientVersion,
                processRunner: processRunner
            )
        case .http:
            return MCPHTTPBridgeService(
                serverName: serverName,
                serverConfig: serverConfig,
                httpClient: httpClient,
                logger: logger,
                clientName: clientName,
                clientVersion: clientVersion
            )
        case .sse:
            return MCPSSEBridgeService(
                serverName: serverName,
                serverConfig: serverConfig,
                httpClient: httpClient,
                logger: logger,
                clientName: clientName,
                clientVersion: clientVersion
            )
        }
    }
}