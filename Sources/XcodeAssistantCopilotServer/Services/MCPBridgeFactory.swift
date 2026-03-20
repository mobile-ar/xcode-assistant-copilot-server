import Foundation

public struct MCPBridgeFactory: Sendable {
    public static func make(
        from configuration: ServerConfiguration,
        logger: LoggerProtocol,
        pidFile: MCPBridgePIDFileProtocol?,
        clientName: String,
        clientVersion: String,
        processRunner: ProcessRunnerProtocol
    ) -> MCPBridgeServiceProtocol? {
        let localServers = configuration.localMCPServers

        guard !localServers.isEmpty else {
            return nil
        }

        let sortedServers = localServers.sorted { $0.key < $1.key }

        if sortedServers.count == 1, let entry = sortedServers.first {
            return MCPBridgeService(
                    serverName: entry.key,
                    serverConfig: entry.value,
                    logger: logger,
                    pidFile: pidFile,
                    clientName: clientName,
                    clientVersion: clientVersion,
                    processRunner: processRunner
                )
        }

        let bridges: [(serverName: String, bridge: MCPBridgeServiceProtocol)] = sortedServers.map { name, serverConfig in
            let bridge = MCPBridgeService(
                serverName: name,
                serverConfig: serverConfig,
                logger: logger,
                pidFile: nil,
                clientName: clientName,
                clientVersion: clientVersion,
                processRunner: processRunner
            )
            return (serverName: name, bridge: bridge)
        }

        return CompositeMCPBridgeService(bridges: bridges, logger: logger)
    }
}
