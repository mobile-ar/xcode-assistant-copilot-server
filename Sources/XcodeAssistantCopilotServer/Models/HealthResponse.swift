import Foundation

public struct HealthResponse: Encodable, Sendable {
    public let status: String
    public let uptimeSeconds: Int
    public let mcpBridge: MCPBridgeStatus

    public init(status: String, uptimeSeconds: Int, mcpBridge: MCPBridgeStatus) {
        self.status = status
        self.uptimeSeconds = uptimeSeconds
        self.mcpBridge = mcpBridge
    }

    enum CodingKeys: String, CodingKey {
        case status
        case uptimeSeconds = "uptime_seconds"
        case mcpBridge = "mcp_bridge"
    }
}

public struct MCPBridgeStatus: Encodable, Sendable {
    public let enabled: Bool

    public init(enabled: Bool) {
        self.enabled = enabled
    }
}